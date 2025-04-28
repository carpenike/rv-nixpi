import json
import threading
import curses
import time
import sys
import base64
from collections import defaultdict, deque # Added deque
import can # Ensure can is imported
import yaml # Added for device mapping
import os # Added for file existence check
import threading # Ensure threading is imported for Lock
import logging # Added for logging
import argparse # Added for command-line arguments

# --- Configuration ---
# Defaults, can be overridden by args
DEFAULT_RVC_SPEC_PATH = '/etc/nixos/files/rvc.json'
DEFAULT_DEVICE_MAPPING_PATH = '/etc/nixos/files/device_mapping.yaml'
DEFAULT_INTERFACES = ['can0', 'can1']

# --- Logging Setup ---
# Keep track of log records for the UI
MAX_LOG_RECORDS = 500 # Max logs to keep in memory for UI
log_records = deque(maxlen=MAX_LOG_RECORDS)
log_records_lock = threading.Lock()

# Custom handler to capture logs for the UI
class ListLogHandler(logging.Handler):
    def __init__(self, log_list, lock):
        super().__init__()
        self.log_list = log_list
        self.lock = lock

    def emit(self, record):
        try:
            msg = self.format(record)
            with self.lock:
                self.log_list.append(msg) # Append formatted message
        except Exception:
            self.handleError(record)

# Configure root logger
log_formatter = logging.Formatter('%(asctime)s - %(levelname)s - %(threadName)s - %(message)s', datefmt='%H:%M:%S')
# Configure file handler (optional, keep if useful)
# file_handler = logging.FileHandler('rvc-console.log')
# file_handler.setFormatter(log_formatter)
# logging.getLogger().addHandler(file_handler)

# Configure console handler (for initial messages before curses)
console_handler = logging.StreamHandler(sys.stderr) # Use stderr to avoid interfering with curses stdout
console_handler.setFormatter(log_formatter)
logging.getLogger().addHandler(console_handler)

# Configure our custom list handler
list_handler = ListLogHandler(log_records, log_records_lock)
list_handler.setFormatter(log_formatter)
# logging.getLogger().addHandler(list_handler) # <-- Keep this commented out here

# Set overall logging level
logging.getLogger().setLevel(logging.INFO) # Or DEBUG for more verbosity

# --- Load Definitions ---
# REMOVED the first load_definitions function

# Renamed function to load both spec and mapping
def load_config_data(rvc_spec_path, device_mapping_path): # Accept paths as args
    """Loads RVC spec and device mappings, identifying light devices and command info."""
    # Load RVC Spec
    decoder_map = {} # Initialize decoder_map

    # --- Pre-check RVC Spec File --- START
    logging.info(f"  [load_config_data] Pre-checking RVC spec file path: {rvc_spec_path}")
    if not os.path.exists(rvc_spec_path):
        logging.error(f"  [load_config_data] RVC spec file does NOT exist at: {rvc_spec_path}")
        sys.exit(1)
    else:
        logging.info(f"  [load_config_data] RVC spec file exists.")
        if not os.access(rvc_spec_path, os.R_OK):
            logging.error(f"  [load_config_data] RVC spec file exists but is NOT readable: {rvc_spec_path}")
            sys.exit(1)
        else:
            logging.info(f"  [load_config_data] RVC spec file exists and is readable.")
    # --- Pre-check RVC Spec File --- END

    try:
        # Use argument path
        logging.info(f"  [load_config_data] Attempting to open RVC spec with 'open()': {rvc_spec_path}") # MOVED LOG
        with open(rvc_spec_path) as f:
            logging.info(f"  [load_config_data] Successfully opened RVC spec file: {rvc_spec_path}")
            # Handle potential KeyError if 'messages' doesn't exist
            logging.info(f"  [load_config_data] Attempting to parse JSON from: {rvc_spec_path}")
            spec_content = json.load(f)
            logging.info(f"  [load_config_data] Successfully parsed JSON from: {rvc_spec_path}")
            specs = spec_content.get('messages', []) # Default to empty list
            if not specs:
                 logging.warning(f"No 'messages' key found or it's empty in {rvc_spec_path}")

        # Key by decimal ID, ensure 'id' exists and is convertible to int
        logging.info(f"  [load_config_data] Processing {len(specs)} spec entries...")
        for entry in specs:
            if 'id' in entry:
                try:
                    # Ensure ID is treated as integer if it's hex string
                    spec_id_str = str(entry['id'])
                    if spec_id_str.startswith('0x'):
                        spec_id = int(spec_id_str, 16)
                    else:
                        spec_id = int(spec_id_str)
                    decoder_map[spec_id] = entry
                except (ValueError, TypeError) as e:
                    logging.warning(f"Skipping spec entry due to invalid ID '{entry.get('id')}': {e}")
            else:
                logging.warning(f"Skipping spec entry missing 'id': {entry}")

        logging.info(f"  [load_config_data] Finished processing spec entries.")

        logging.info(f"Loaded {len(decoder_map)} RVC message specs from {rvc_spec_path}")
    except FileNotFoundError: # Should be caught by pre-check, but keep for safety
        logging.error(f"RVC spec file not found during open: {rvc_spec_path}")
        sys.exit(1)
    except PermissionError: # Explicitly catch permission errors during open
        logging.error(f"Permission denied when trying to open RVC spec file: {rvc_spec_path}")
        sys.exit(1)
    except json.JSONDecodeError as e:
        logging.error(f"Error decoding JSON from RVC spec ({rvc_spec_path}): {e}")
        sys.exit(1)
    except Exception as e:
        # Use argument path in error message
        logging.exception(f"Error loading RVC spec ({rvc_spec_path})")
        sys.exit(1)
    finally:
        logging.info(f"  [load_config_data] Exiting 'try' block for RVC spec loading.") # ADDED FINALLY LOG

    # Load Device Mapping
    device_mapping = {} # Raw mapping loaded from YAML
    device_lookup = {} # Processed lookup: (dgn_hex, instance_str) -> mapped_config
    entity_id_lookup = {} # New lookup: entity_id -> mapped_config
    light_entity_ids = set() # Store entity_ids of devices identified as lights
    light_command_info = {} # New: Store command DGN/Instance per light entity_id

    # Use argument path
    logging.info(f"  [load_config_data] Attempting to load device mapping: {device_mapping_path}")
    if os.path.exists(device_mapping_path):
        try:
            # Use argument path
            with open(device_mapping_path) as f:
                raw_mapping = yaml.safe_load(f) or {} # Ensure raw_mapping is a dict even if file is empty
                # Process into a more direct lookup table
                templates = raw_mapping.get('templates', {})
                device_mapping = raw_mapping # Keep raw for potential future use

                # Iterate through DGNs in the mapping (excluding templates)
                for dgn_hex, instances in raw_mapping.items():
                    if dgn_hex == 'templates': continue
                    # Ensure instances is a dictionary
                    if not isinstance(instances, dict):
                        logging.warning(f"Skipping DGN '{dgn_hex}' in mapping: expected a dictionary of instances, got {type(instances).__name__}")
                        continue

                    for instance_str, configs in instances.items():
                        # Ensure configs is a list
                        if not isinstance(configs, list):
                            logging.warning(f"Skipping Instance '{instance_str}' under DGN '{dgn_hex}': expected a list of configurations, got {type(configs).__name__}")
                            continue

                        for config in configs:
                            # Ensure config is a dictionary
                            if not isinstance(config, dict):
                                logging.warning(f"Skipping config under DGN '{dgn_hex}', Instance '{instance_str}': expected a dictionary, got {type(config).__name__}")
                                continue

                            # Apply template if specified
                            template_name = config.pop('<<', None) # Use pop to remove merge key
                            if template_name and template_name in templates:
                                # Shallow merge: config overrides template
                                merged_config = {**templates[template_name], **config}
                            else:
                                merged_config = config

                            # Ensure essential keys are present (using entity_id now)
                            if 'entity_id' in merged_config and 'friendly_name' in merged_config:
                                entity_id = merged_config['entity_id'] # Get entity_id
                                # Store the final merged config
                                device_lookup[(dgn_hex.upper(), str(instance_str))] = merged_config
                                # Populate entity_id lookup only once per entity_id (first encountered wins for simplicity)
                                if entity_id not in entity_id_lookup:
                                    entity_id_lookup[entity_id] = merged_config

                                # --- Identify Lights and Command Info (using device_type now) ---
                                if str(merged_config.get('device_type', '')).lower() == 'light':
                                    light_entity_ids.add(entity_id) # Use entity_id
                                    logging.debug(f"Identified '{entity_id}' as a light.")
                                    # Check if the DGN is the command DGN (1FEDA) and store command info
                                    # Ensure dgn_hex is valid before comparing
                                    if isinstance(dgn_hex, str) and dgn_hex.upper() == '1FEDA':
                                        try:
                                            instance_int = int(instance_str) # Ensure instance is int
                                            # Store command info (overwrite if found again, assuming last is correct)
                                            light_command_info[entity_id] = {'dgn': 0x1FEDA, 'instance': instance_int}
                                            logging.debug(f"Stored command info for {entity_id}: DGN=0x1FEDA, Instance={instance_int}")
                                        except ValueError:
                                            logging.warning(f"Invalid instance '{instance_str}' for light command DGN {dgn_hex} and entity {entity_id}")
                                # --- End Identify Lights ---
                            else:
                                # Update warning message
                                logging.warning(f"Skipping mapping entry under DGN {dgn_hex}, Instance {instance_str} due to missing 'entity_id' or 'friendly_name'. Config: {config}")

            logging.info(f"Loaded {len(device_lookup)} specific device mappings from {device_mapping_path}") # Use arg path
            logging.info(f"Identified {len(light_entity_ids)} light devices.") # Use renamed set
            logging.info(f"Found command info for {len(light_command_info)} lights.")
        except yaml.YAMLError as e:
             logging.warning(f"Could not parse device mapping YAML ({device_mapping_path}): {e}") # Use arg path
        except Exception as e:
            logging.warning(f"Could not load or process device mapping ({device_mapping_path}): {e}") # Use arg path
            # Continue without device mapping if it fails, but initialize relevant vars
            device_mapping = {}
            device_lookup = {}
            entity_id_lookup = {}
            light_entity_ids = set()
            light_command_info = {}
    else:
        logging.warning(f"Device mapping file not found ({device_mapping_path}). Mapped Devices/Lights tabs will be empty.") # Use arg path
        # Ensure vars are initialized even if file not found
        device_mapping = {}
        device_lookup = {}
        entity_id_lookup = {}
        light_entity_ids = set()
        light_command_info = {}


    # Return all relevant loaded/processed data
    return decoder_map, device_mapping, device_lookup, light_entity_ids, entity_id_lookup, light_command_info

# --- Decoding Helpers ---
def get_bits(data_bytes, start_bit, length):
    raw_int = int.from_bytes(data_bytes, byteorder='little')
    mask = (1 << length) - 1
    return (raw_int >> start_bit) & mask

# Decode signals per spec entry
def decode_payload(entry, data_bytes):
    decoded = {}
    raw_values = {}
    for sig in entry.get('signals', []):
        raw = get_bits(data_bytes, sig['start_bit'], sig['length'])
        raw_values[sig['name']] = raw # Store raw integer value
        val = raw * sig.get('scale', 1) + sig.get('offset', 0)
        unit = sig.get('unit', '')
        # Smart formatting based on type/scale
        if 'enum' in sig:
             formatted = sig['enum'].get(str(raw), f"UNKNOWN ({raw})")
        elif sig.get('scale', 1) != 1 or sig.get('offset', 0) != 0 or isinstance(val, float):
             formatted = f"{val:.2f}{unit}"
        else:
             formatted = f"{int(val)}{unit}"
        decoded[sig['name']] = formatted
    return decoded, raw_values # Return both formatted and raw

# --- CAN Sending Helper ---
def send_can_command(interface, can_id, data):
    """Sends a CAN message."""
    bus = None # Initialize bus to None
    try:
        logging.debug(f"Attempting to create CAN bus for interface {interface}...")
        # Use context manager for bus cleanup
        with can.interface.Bus(channel=interface, interface='socketcan', receive_own_messages=False) as bus:
            logging.debug(f"CAN bus created for {interface}. Preparing message...")
            msg = can.Message(arbitration_id=can_id, data=data, is_extended_id=True)
            logging.debug(f"Message prepared: ID=0x{can_id:08X}, Data={data.hex().upper()}. Attempting send...")
            bus.send(msg)
            # Add log immediately after send returns
            logging.debug(f"bus.send() completed for {interface}.")
            logging.info(f"Sent CAN msg on {interface}: ID=0x{can_id:08X}, Data={data.hex().upper()}")
            return True
    except can.CanError as e:
        # Log the specific CanError
        logging.error(f"CAN Error sending message on {interface}: {type(e).__name__} - {e}")
        return False
    except Exception as e:
        # Catch specific exceptions if possible, e.g., OSError if interface down
        # Log the specific Exception type
        logging.error(f"Unexpected error sending CAN message on {interface}: {type(e).__name__} - {e}")
        return False

# OSC52 copy to clipboard
def copy_to_clipboard(text):
    payload = base64.b64encode(text.encode()).decode()
    sys.stdout.write(f"\x1b]52;c;{payload}\x07")
    sys.stdout.flush()

# --- Global State ---
# Initialized after arg parsing
decoder_map = None
device_mapping = None
device_lookup = None
light_entity_ids = set() # Renamed from light_ha_names
light_command_info = {} # Added: Stores DGN/Instance for commanding lights
latest_raw_records = {} # Initialized after interfaces are known
# mapped_device_states = {} # REMOVED
light_device_states = {} # Keyed by entity_id for lights (Changed from ha_name)
raw_records_lock = threading.Lock()
# mapped_states_lock = threading.Lock() # REMOVED
light_states_lock = threading.Lock() # Lock for light states
stop_event = threading.Event()
copy_msg = None
copy_time = 0
sort_labels = ['A→Z', 'Newest', 'Oldest']
# mapped_sort_labels = ['Area→Name', 'Name', 'Newest'] # REMOVED
light_sort_labels = ['Area→Name', 'Name', 'Newest'] # Sort options for lights tab
is_paused = False # Pause state flag
pause_lock = threading.Lock() # Lock for pause state
# Store the data used for the last draw, to display when paused
last_draw_data = {
    # "mapped": [], # REMOVED
    "lights": [],
    "logs": [], # <-- Restore logs cache entry
    "raw0": ([], {}), # (names, recs_copy)
    "raw1": ([], {}), # (names, recs_copy)
}
INTERFACES = [] # Will be populated by args

# --- Reader Thread ---
def reader_thread(interface):
    """Reads CAN messages, decodes, and updates raw records, mapped device states, and light states."""
    try:
        bus = can.interface.Bus(channel=interface, interface='socketcan')
        logging.info(f"Successfully opened CAN interface {interface}")
    except Exception as e:
        logging.error(f"Error opening CAN interface {interface}: {e}")
        return # Exit thread if CAN interface fails

    while not stop_event.is_set():
        try:
            msg = bus.recv(1) # Timeout of 1 second
            if not msg:
                continue

            now = time.time()
            entry = decoder_map.get(msg.arbitration_id)

            # --- Update Raw Records ---
            if entry and not entry.get('name', '').startswith('UNKNOWN'):
                name = entry['name']
                # --- Update Raw Records (Locked) ---
                with raw_records_lock:
                    rec = latest_raw_records[interface].get(name, {})
                    rec.setdefault('first_received', now)
                    rec['last_received'] = now
                    decoded_data, raw_values = decode_payload(entry, msg.data)
                    rec.update({
                        'raw_id': f"0x{msg.arbitration_id:08X}",
                        'raw_data': msg.data.hex().upper(),
                        'decoded': decoded_data,
                        'spec': entry,
                        'interface': interface
                    })
                    latest_raw_records[interface][name] = rec
                # --- End Update Raw Records ---

                # --- Update Light State Only (if applicable) --- START
                dgn_hex = entry.get('dgn_hex')
                instance_raw = raw_values.get('instance') # Get raw instance value

                if dgn_hex and instance_raw is not None:
                    instance_str = str(instance_raw)
                    mapped_config = device_lookup.get((dgn_hex.upper(), instance_str))
                    if not mapped_config:
                         mapped_config = device_lookup.get((dgn_hex.upper(), 'default'))

                    if mapped_config:
                        entity_id = mapped_config.get('entity_id')
                        # Update light state if it's a light (using entity_id)
                        if entity_id and entity_id in light_entity_ids: # Check against light_entity_ids
                            state_data = {
                                'entity_id': entity_id,
                                'friendly_name': mapped_config.get('friendly_name', entity_id),
                                'suggested_area': mapped_config.get('suggested_area', 'Unknown'),
                                'last_updated': now,
                                'last_interface': interface,
                                'last_raw_values': raw_values,
                                'last_decoded_data': decoded_data,
                                'mapping_config': mapped_config,
                                'dgn_hex': dgn_hex,
                                'instance': instance_str
                            }
                            with light_states_lock:
                                light_state_entry = light_device_states.get(entity_id, {})
                                light_state_entry.update(state_data)
                                light_device_states[entity_id] = light_state_entry
                # --- Update Light State Only --- END

            # --- End Update Mapped Device State ---

        except can.CanError as e:
            logging.error(f"CAN Error on {interface}: {e}")
            time.sleep(5) # Avoid spamming errors if bus goes down
        except Exception as e:
            logging.exception(f"Unhandled error in reader thread for {interface}") # Log traceback
            time.sleep(1) # Prevent tight loop on unexpected errors

    # Cleanup
    try:
        bus.shutdown()
        logging.info(f"Closed CAN interface {interface}")
    except Exception as e:
        logging.error(f"Error shutting down CAN interface {interface}: {e}")

# --- Main UI Drawing ---
def draw_screen(stdscr, interfaces): # Accept interfaces list
    # REMOVED log_records and log_records_lock from global declaration as they are not used when handler is disabled
    # global copy_msg, copy_time, is_paused, last_draw_data
    # Restore log_records and log_records_lock to global declaration
    global copy_msg, copy_time, is_paused, last_draw_data, log_records, log_records_lock
    curses.curs_set(0)
    curses.start_color()
    curses.use_default_colors()
    # Define colors
    curses.init_pair(1, curses.COLOR_WHITE, curses.COLOR_BLUE) # Header/Footer
    curses.init_pair(2, curses.COLOR_GREEN, -1)  # Selected item
    curses.init_pair(3, curses.COLOR_WHITE, -1)  # Normal text
    curses.init_pair(4, curses.COLOR_CYAN, -1)   # Data labels / Raw IDs
    curses.init_pair(5, curses.COLOR_YELLOW, -1) # Copy message / Important values
    curses.init_pair(6, curses.COLOR_MAGENTA, -1) # Area / Secondary info
    curses.init_pair(7, curses.COLOR_RED, -1)    # Error / Action Hint

    # Make getch non-blocking
    stdscr.nodelay(1)
    stdscr.timeout(100)

    # Dynamically generate tabs based on interfaces - REMOVED "Mapped Devices", ADDED "Logs"
    # REMOVED "Logs" tab as the handler is disabled
    # tabs = ["Lights"] + [f"{iface.upper()} Raw" for iface in interfaces]
    # Restore "Logs" tab
    tabs = ["Lights", "Logs"] + [f"{iface.upper()} Raw" for iface in interfaces]
    # Adjust tab keys
    # Adjusted tab keys for removed "Logs" tab
    # tab_keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9'][:len(tabs)]
    # Restore original tab keys
    tab_keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'][:len(tabs)]
    current_tab_index = 0

    # State per tab - REMOVED "Mapped Devices", ADDED "Logs"
    tab_state = {name: {'selected_idx': 0, 'v_offset': 0, 'sort_mode': 0} for name in tabs}
    # Logs tab doesn't need sorting state
    # REMOVED logic for "Logs" tab state
    # Restore logic for "Logs" tab state
    if "Logs" in tab_state:
        del tab_state["Logs"]['sort_mode']

    while True:
        # --- Input Handling ---
        c = stdscr.getch()

        if c != curses.ERR:
            if c in (ord('q'), ord('Q')):
                stop_event.set()
                break

            # Pause Toggle
            elif c in (ord('p'), ord('P')): # Ensure this elif is correctly indented
                with pause_lock:
                    is_paused = not is_paused
                # Immediately clear cached data when unpausing to force refresh
                if not is_paused:
                     last_draw_data = {
                         # "mapped": [], # REMOVED
                         "lights": [],
                         "logs": [], # <-- Restore logs cache clearing
                         **{f"raw{i}": ([], {}) for i in range(len(interfaces))}
                     }
            # Tab switching # Ensure this try block is at the same level as the elif
            try:
                key_char = chr(c)
                if key_char in tab_keys:
                    current_tab_index = tab_keys.index(key_char)
            except (ValueError, IndexError):
                 pass # Ignore non-character/invalid keys

            # Context-aware actions (pass interfaces for raw tabs) # Ensure this block is at the same level
            active_tab_name = tabs[current_tab_index]
            # Check if active_tab_name exists in tab_state before accessing
            if active_tab_name in tab_state:
                state = tab_state[active_tab_name]
                handle_input_for_tab(c, active_tab_name, state, interfaces) # Pass interfaces
            # else: # Handle case where tab might not have state (e.g., if Logs was still somehow selected)
                # pass # Or log a warning

        # --- Data Fetching (Conditional based on Pause) ---
        with pause_lock:
            paused_now = is_paused # Read pause state under lock

        active_tab_name = tabs[current_tab_index]
        # Check if active_tab_name exists in tab_state before accessing
        state = tab_state.get(active_tab_name) # Use .get for safety
        if not state:
            # Handle case where state might be missing (shouldn't happen with current logic)
            # logging.warning(f"State not found for active tab: {active_tab_name}")
            continue # Skip drawing cycle if state is missing

        # Data for drawing - fetch ONLY if not paused, otherwise use cached
        # mapped_items_to_draw = [] # REMOVED
        light_items_to_draw = []
        log_items_to_draw = [] # <-- Restore log items list
        raw_names_to_draw = []
        raw_recs_to_draw = {}
        interface_for_raw_tab = None

        if not paused_now:
            # Fetch fresh data
            # Ensure the following block is correctly indented under 'if not paused_now:'
            if active_tab_name == "Lights":
                with light_states_lock:
                    # Make a copy
                    light_items_to_draw = list(light_device_states.values())
                last_draw_data["lights"] = light_items_to_draw # Cache fresh data
            # --- Restore Fetching for Logs Tab ---
            elif active_tab_name == "Logs": # Ensure this elif aligns with the 'if' above
                with log_records_lock:
                    # Make a copy of the deque items (newest first for display)
                    log_items_to_draw = list(log_records)[::-1]
                last_draw_data["logs"] = log_items_to_draw # Cache fresh data
            elif " Raw" in active_tab_name: # Ensure this elif aligns with the 'if' above
                try:
                    # Determine interface based on tab name/index relative to "Lights"
                    # Restore original index calculation
                    iface_index = current_tab_index - 2
                    if 0 <= iface_index < len(interfaces):
                        interface_for_raw_tab = interfaces[iface_index]
                        with raw_records_lock:
                             # Make copies
                             raw_recs_to_draw = latest_raw_records[interface_for_raw_tab].copy()
                        raw_names_to_draw = list(raw_recs_to_draw.keys()) # Get names from the copy
                        # Cache fresh data (use index for key robustness)
                        last_draw_data[f"raw{iface_index}"] = (raw_names_to_draw, raw_recs_to_draw)
                    else: # Should not happen if tabs/keys are correct
                         logging.warning(f"Could not determine interface for tab: {active_tab_name}")

                except Exception as e:
                     logging.exception(f"Error fetching raw data for {active_tab_name}")

        else: # Use cached data if paused - Ensure this 'else' aligns with 'if not paused_now:'
             if active_tab_name == "Lights":
                 light_items_to_draw = last_draw_data["lights"]
             # --- Restore Cache Retrieval for Logs Tab ---
             elif active_tab_name == "Logs":
                 log_items_to_draw = last_draw_data["logs"]
             elif " Raw" in active_tab_name:
                 # Restore original index calculation
                 iface_index = current_tab_index - 2
                 if 0 <= iface_index < len(interfaces):
                     interface_for_raw_tab = interfaces[iface_index]
                     # Retrieve cached data
                     raw_names_to_draw, raw_recs_to_draw = last_draw_data.get(f"raw{iface_index}", ([], {}))

        # --- Drawing ---
        stdscr.erase()
        h, w = stdscr.getmaxyx()

        # --- Header ---
        header_text = ""
        # Pause indicator
        if paused_now:
             header_text += "[PAUSED] "
        # Tabs
        for i, name in enumerate(tabs):
            key = tab_keys[i]
            indicator = "*" if i == current_tab_index else " "
            header_text += f"[{key}]{indicator}{name}{indicator}  "
        # Sort mode
        sort_label = ""
        num_sort_modes = 0
        if active_tab_name == "Lights":
             # ...existing code...
        elif " Raw" in active_tab_name:
             # ...existing code...
        # Only show sort if applicable (not for Logs)
        # Always show sort if applicable (Logs tab removed)
        # if sort_label: header_text += f"[S] Sort:{sort_label}  "
        # Restore original logic (don't show sort for Logs)
        if sort_label: header_text += f"[S] Sort:{sort_label}  "
        # ... existing code ...

        # --- Main Content Area ---
        max_rows = h - 5 # Rows available for content list

        if active_tab_name == "Lights":
            # ...existing code...
        # --- REMOVED Drawing Call for Logs Tab ---
        # --- Restore Drawing Call for Logs Tab ---
        elif active_tab_name == "Logs":
            draw_logs_tab(stdscr, h, w, max_rows, state, log_items_to_draw) # Pass log items
        elif " Raw" in active_tab_name and interface_for_raw_tab:
            # ...existing code...

        # ... existing code ...
        # --- Footer ---
        footer = "Arrows: Navigate | "
        if active_tab_name == "Lights":
             footer += "Enter: Control | " # Add hint for lights tab
        # Update tab names in footer hint
        # Restore hint for logs tab
        elif active_tab_name == "Logs":
             footer += "C: Copy Line | "
        footer += " ".join([f"{key}:{name}" for key, name in zip(tab_keys, tabs)])
        footer += " | S: Sort (where avail) | C: Copy | P: Pause | Q: Quit"
        # ... existing code ...

# --- Drawing Functions ---

# REMOVE draw_mapped_devices_tab function entirely
# def draw_mapped_devices_tab(stdscr, h, w, max_rows, state, items):
#    ...

# --- REMOVE Drawing Function for Logs Tab ---
# --- Restore Drawing Function for Logs Tab ---
def draw_logs_tab(stdscr, h, w, max_rows, state, items):
    """Draws the 'Logs' tab content."""
    global copy_msg, copy_time
    pad = 1

    # No titles needed, just list the logs
    stdscr.hline(1, 0, '-', w) # Keep separator below header

    total = len(items)
    selected_idx = state['selected_idx']
    v_offset = state['v_offset']

    # Adjust view window (Logs are newest first, so index 0 is newest)
    if total:
        selected_idx = max(0, min(selected_idx, total - 1))
        if selected_idx < v_offset:
            v_offset = selected_idx
        elif selected_idx >= v_offset + max_rows:
            v_offset = selected_idx - max_rows + 1
        state['selected_idx'] = selected_idx
        state['v_offset'] = v_offset
    else:
        state['selected_idx'] = state['v_offset'] = 0

    # --- Scroll Indicators ---
    if v_offset > 0:
        stdscr.addstr(2, w - 1, "↑", curses.A_DIM) # Start drawing from row 2
    if v_offset + max_rows < total:
        stdscr.addstr(h - 3, w - 1, "↓", curses.A_DIM)

    # Draw list items (log messages)
    for idx in range(v_offset, min(v_offset + max_rows, total)):
        row = 2 + idx - v_offset # Start drawing from row 2
        item_text = items[idx] # Items are already formatted strings
        is_selected = (idx == selected_idx)

        # Color based on log level
        attr = curses.color_pair(3) # Default white
        if "ERROR" in item_text:
            attr = curses.color_pair(7) # Red
        elif "WARNING" in item_text:
            attr = curses.color_pair(5) # Yellow
        elif "DEBUG" in item_text:
            attr = curses.color_pair(6) # Magenta/Dim

        if is_selected:
            attr |= curses.A_REVERSE # Highlight selected line

        stdscr.addnstr(row, pad, item_text.ljust(w - pad * 2), w - pad * 2, attr)

    # --- Copy Action for Logs Tab ---
    if state.get('_copy_action', False):
        if total:
            item_to_copy = items[selected_idx]
            copy_to_clipboard(item_to_copy)
            copy_msg = f"Log line copied."
            copy_time = time.time()
        state['_copy_action'] = False # Reset flag

# ... existing code ...

# Modify handle_input to accept interfaces and pass them down if needed
def handle_input_for_tab(c, active_tab_name, state, interfaces):
    """Handles key presses based on the active tab."""
    # REMOVED log_records and log_records_lock from global declaration
    # Restore log_records and log_records_lock to global declaration
    global copy_msg, copy_time, light_command_info, INTERFACES, log_records, log_records_lock
    # ... existing code ...
    if active_tab_name == "Lights":
        # ...existing code...
    # --- REMOVED Logic for Logs Tab ---
    # --- Restore Logic for Logs Tab ---
    elif active_tab_name == "Logs":
        # Use log_records_lock when accessing log_records for count
        with log_records_lock:
            items_list = list(log_records) # Get a temporary list under lock
        total = len(items_list)
        num_sort_modes = 0 # No sorting for logs
        # ID for logs is just the index, but we don't need stable selection on sort
        current_id = state['selected_idx'] if 0 <= state['selected_idx'] < total else None
    elif " Raw" in active_tab_name:
        iface_index = -1
        try: # Find interface index based on tab name
            iface_name_part = active_tab_name.split(" ")[0].lower()
            # Adjust index based on preceding tabs ("Lights", "Logs")
            # iface_index = current_tab_index - 1 # Adjusted index
            # Restore original index calculation
            iface_index = current_tab_index - 2
        except (ValueError, IndexError):
             pass
        # ... existing code ...

    # ... existing code ...
    elif c in (ord('s'), ord('S')) and num_sort_modes > 0: # Check if sorting is applicable
        # ... existing code ...
        if current_id is not None: # Check if we have a valid ID
            new_items_sorted = [] # This will be a list of IDs (entity_id or message name)
            if active_tab_name == "Lights":
                 # ... existing light sorting ...
                 new_items_sorted = [item.get('entity_id') for item in items_list_copy]

            elif " Raw" in active_tab_name:
                 iface_index = -1
                 try:
                     iface_name_part = active_tab_name.split(" ")[0].lower()
                     # Adjust index based on preceding tabs ("Lights", "Logs")
                     # iface_index = current_tab_index - 1 # Adjusted index
                     # Restore original index calculation
                     iface_index = current_tab_index - 2
                 except (ValueError, IndexError): pass
                 # ... existing raw sorting ...

            # ... existing code ...

    # --- Copying ---
    elif c in (ord('c'), ord('C')):
        # Only trigger copy action if the tab supports it (i.e., not Logs)
        # if active_tab_name != "Logs": # Check added for safety, though Logs tab is removed
        # Restore original logic (allow copy on Logs tab)
        state['_copy_action'] = True # Signal draw function to perform copy

    # ... existing code ...

# --- Entry Point ---
if __name__ == '__main__':
    # ... existing code ...
    # Initialize global state dependent on args
    logging.info("Initializing global state...") # Added log
    INTERFACES = args.interfaces # Set global interfaces list
    latest_raw_records = {iface: {} for iface in INTERFACES}
    light_device_states = {} # Initialize light state dict (keyed by entity_id)
    # light_entity_ids and light_command_info are already populated by load_config_data
    last_draw_data = { # Initialize cache structure based on interfaces and new tabs
         "lights": [],
         "logs": [], # <-- Ensure logs cache is initialized
         **{f"raw{i}": ([], {}) for i in range(len(INTERFACES))}
    }
    logging.info("Global state initialized.") # Added log

    # ... existing code ...

    # --- Start Curses UI ---
    # Add the ListLogHandler *just before* starting curses
    logging.info("Adding ListLogHandler before starting UI...")
    logging.getLogger().addHandler(list_handler)

    logging.info("Attempting to start curses UI...") # Log before curses
    # Remove the console handler *just before* starting curses
    logging.getLogger().removeHandler(console_handler)
    try:
        curses.wrapper(draw_screen, INTERFACES) # Pass interfaces list
    # ... existing code ...
