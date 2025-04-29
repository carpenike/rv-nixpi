import json
import threading
import curses
import time
import sys
import base64
from collections import defaultdict, deque # Added deque
import can # type: ignore # Ensure can is imported
import yaml # type: ignore # Added for device mapping
import os # Added for file existence check
import threading # Ensure threading is imported for Lock
import logging # Added for logging
import argparse # Added for command-line arguments
import queue # Import the queue module

# --- Configuration ---
# Defaults, can be overridden by args
DEFAULT_RVC_SPEC_PATH = '/etc/nixos/files/rvc.json'
DEFAULT_DEVICE_MAPPING_PATH = '/etc/nixos/files/device_mapping.yaml'
DEFAULT_INTERFACES = ['can0', 'can1']

# --- Logging Setup ---
# Custom handler to capture logs for the UI
class ListLogHandler(logging.Handler):
    """ A logging handler that stores messages in a thread-safe queue. """
    def __init__(self, max_entries=500):
        super().__init__()
        # Use a queue instead of a list and lock
        self.log_queue = queue.Queue(maxsize=max_entries)
        # Optional: Keep track of dropped messages if queue is full
        self.dropped_messages = 0

    def emit(self, record):
        # Format the message
        log_entry = self.format(record)
        try:
            # Put the formatted message onto the queue (non-blocking put)
            self.log_queue.put_nowait(log_entry)
        except queue.Full:
            # Handle queue full scenario if necessary (e.g., drop oldest or log an error)
            # For simplicity, we'll just increment a counter here
            self.dropped_messages += 1
            # Optionally, try removing the oldest and adding the new one
            try:
                self.log_queue.get_nowait() # Remove oldest
                self.log_queue.put_nowait(log_entry) # Add newest
            except queue.Empty:
                pass # Should not happen if queue was full
            except queue.Full:
                pass # Should not happen after removing one

    def get_records(self):
        """ Retrieve all currently available log records from the queue. """
        records = []
        while True:
            try:
                records.append(self.log_queue.get_nowait())
            except queue.Empty:
                break
        # If messages were dropped, add a notification
        if self.dropped_messages > 0:
            records.append(f"... {self.dropped_messages} log messages dropped due to queue overflow ...")
            self.dropped_messages = 0 # Reset counter after notifying
        return records

# Configure root logger
log_formatter = logging.Formatter('%(asctime)s - %(levelname)s - %(threadName)s - %(message)s', datefmt='%H:%M:%S')
# Configure file handler (optional, keep if useful)
# file_handler = logging.FileHandler('rvc-console.log')
# file_handler.setFormatter(log_formatter)
# logging.getLogger().addHandler(file_handler)

# Configure console handler (for initial messages before curses)
console_handler = logging.StreamHandler(sys.stderr) # Use stderr to avoid interfering with curses stdout
console_handler.setFormatter(log_formatter)
# logging.getLogger().addHandler(console_handler) # REMOVED: Prevent adding console handler globally

# Create the ListLogHandler instance (using the new class)
list_handler = ListLogHandler(max_entries=1000) # Increased size slightly
list_handler.setFormatter(logging.Formatter('%(asctime)s - %(levelname)s - %(name)s:%(message)s', datefmt='%H:%M:%S'))

# Set overall logging level
logging.getLogger().setLevel(logging.INFO) # Or DEBUG for more verbosity

# --- Prevent initial console logging --- START
# Remove any default handlers (like StreamHandler to stderr) that might be present
# before our curses handler takes over.
for handler in logging.root.handlers[:]:
    logging.root.removeHandler(handler)
# --- Prevent initial console logging --- END

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
# Modify draw_screen to accept list_handler
def draw_screen(stdscr, interfaces, list_handler_instance): # Accept interfaces list and handler
    global copy_msg, copy_time, is_paused, last_draw_data
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

    # --- Add the ListLogHandler HERE --- # MOVED FROM MAIN
    logging.info("Adding ListLogHandler inside draw_screen...")
    logging.getLogger().addHandler(list_handler_instance)
    logging.info("ListLogHandler added.")
    # --- End Add Handler ---

    # Restore "Logs" tab
    tabs = ["Lights", "Logs"] + [f"{iface.upper()} Raw" for iface in interfaces]
    # Restore original tab keys
    tab_keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'][:len(tabs)]
    current_tab_index = 0

    # State per tab - REMOVED "Mapped Devices", ADDED "Logs"
    tab_state = {name: {'selected_idx': 0, 'v_offset': 0, 'sort_mode': 0} for name in tabs}
    # Restore logic for "Logs" tab state
    if "Logs" in tab_state:
        del tab_state["Logs"]['sort_mode']

    # Local deque to store log messages retrieved from the handler's queue
    displayed_log_records = deque(maxlen=500)

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
                # Pass current_tab_index to handle_input_for_tab
                handle_input_for_tab(c, active_tab_name, state, interfaces, current_tab_index)
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
                # Retrieve messages from the handler's queue
                new_log_records = list_handler_instance.get_records()
                if new_log_records:
                    displayed_log_records.extend(new_log_records)
                    # If not paused and on the Logs tab, scroll to the bottom
                    if not is_paused and current_tab_index == 1:
                        log_scroll_pos = max(0, len(displayed_log_records) - (h - 5))
                log_items_to_draw = list(displayed_log_records) # Use the local deque
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
        # Check state exists before accessing sort_mode
        if state:
            if active_tab_name == "Lights":
                sort_label = light_sort_labels[state['sort_mode']]
                num_sort_modes = len(light_sort_labels)
            elif " Raw" in active_tab_name:
                sort_label = sort_labels[state['sort_mode']]
                num_sort_modes = len(sort_labels)
        # Restore original logic (don't show sort for Logs)
        if sort_label:
            header_text += f"[S] Sort:{sort_label}  "
        # Other actions
        header_text += "[C] Copy  [P] Pause  [Q] Quit"
        stdscr.attron(curses.color_pair(1) | curses.A_BOLD)
        stdscr.addnstr(0, 0, header_text.ljust(w), w)
        stdscr.attroff(curses.color_pair(1) | curses.A_BOLD)
        stdscr.hline(1, 0, '-', w)

        # --- Main Content Area ---
        max_rows = h - 5 # Rows available for content list

        # Check state exists before passing to draw functions
        if state:
            if active_tab_name == "Lights":
                # Pass fetched/cached light data
                draw_lights_tab(stdscr, h, w, max_rows, state, light_items_to_draw)
            # --- Restore Drawing Call for Logs Tab ---
            elif active_tab_name == "Logs":
                draw_logs_tab(stdscr, h, w, max_rows, state, log_items_to_draw) # Pass log items
            elif " Raw" in active_tab_name and interface_for_raw_tab:
                # Pass fetched/cached data and interface name
                draw_raw_can_tab(stdscr, h, w, max_rows, state, interface_for_raw_tab, raw_names_to_draw, raw_recs_to_draw)

        # --- Copy/Action Notification ---
        if copy_msg and time.time() - copy_time < 3:
            # Use yellow for copy, red for action hint
            msg_color = curses.color_pair(5) if "copied" in copy_msg else curses.color_pair(7)
            stdscr.attron(msg_color | curses.A_BOLD)
            stdscr.addnstr(h - 2, 0, copy_msg[:w - 1].ljust(w - 1), w - 1)
            stdscr.attroff(msg_color | curses.A_BOLD)

        # --- Footer ---
        footer = "Arrows: Navigate | "
        if active_tab_name == "Lights":
             footer += "Enter: Control | " # Add hint for lights tab
        # Restore hint for logs tab
        elif active_tab_name == "Logs":
             footer += "C: Copy Line | "
        # Update tab names in footer hint
        footer += " ".join([f"{key}:{name}" for key, name in zip(tab_keys, tabs)])
        footer += " | S: Sort (where avail) | C: Copy | P: Pause | Q: Quit"
        stdscr.attron(curses.color_pair(1) | curses.A_BOLD)
        stdscr.addnstr(h - 1, 0, footer[:w-1].ljust(w-1), w - 1)
        stdscr.attroff(curses.color_pair(1) | curses.A_BOLD)

        stdscr.refresh()


# --- Drawing Functions ---

# --- Restore Drawing Function for Logs Tab ---
def draw_logs_tab(stdscr, h, w, max_rows, state, items):
    """Draws the 'Logs' tab content."""
    global copy_msg, copy_time
    pad = 1

    # No titles needed, just list the logs
    # stdscr.hline(1, 0, '-', w) # REMOVED: Redundant separator, already drawn in draw_screen

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


def draw_lights_tab(stdscr, h, w, max_rows, state, items): # Accept items
    """Draws the 'Lights' tab content."""
    global copy_msg, copy_time
    # Column setup (similar to mapped devices)
    col_area_w = max(15, w // 6)
    col_name_w = max(25, w // 3)
    col_state_w = w - col_area_w - col_name_w - 3 # Remaining width for state
    pad = 2
    area_start = pad
    name_start = area_start + col_area_w + 1 + pad
    state_start = name_start + col_name_w + 1 + pad

    # Titles
    stdscr.addnstr(2, area_start, "Area".ljust(col_area_w), col_area_w, curses.A_BOLD)
    stdscr.addnstr(2, name_start, "Light Name".ljust(col_name_w), col_name_w, curses.A_BOLD)
    stdscr.addnstr(2, state_start, "Status / Control".ljust(col_state_w), col_state_w, curses.A_BOLD)
    stdscr.hline(3, 0, '-', w)
    # Vertical separators
    for y in range(2, h - 2):
        stdscr.addch(y, area_start + col_area_w, '|')
        stdscr.addch(y, name_start + col_name_w, '|')

    # Sort the passed-in items list using light_sort_labels
    sort_mode = state['sort_mode']
    if sort_mode == 0: # Area -> Name
        items.sort(key=lambda x: (x.get('suggested_area', 'zzz').lower(), x.get('friendly_name', 'zzz').lower()))
    elif sort_mode == 1: # Name
        items.sort(key=lambda x: x.get('friendly_name', 'zzz').lower())
    elif sort_mode == 2: # Newest
        items.sort(key=lambda x: x.get('last_updated', 0), reverse=True)

    total = len(items)
    selected_idx = state['selected_idx']
    v_offset = state['v_offset']

    # Adjust view window
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
        stdscr.addstr(4, w - 1, "↑", curses.A_DIM)
    if v_offset + max_rows < total:
        stdscr.addstr(h - 3, w - 1, "↓", curses.A_DIM)

    # Draw list items
    for idx in range(v_offset, min(v_offset + max_rows, total)):
        row = 4 + idx - v_offset
        item = items[idx]
        is_selected = (idx == selected_idx)
        attr = curses.color_pair(2) | curses.A_BOLD if is_selected else curses.color_pair(3)
        area_attr = curses.color_pair(6) if not is_selected else attr # Different color for area

        stdscr.addnstr(row, area_start, item.get('suggested_area', 'N/A').ljust(col_area_w), col_area_w, area_attr)
        stdscr.addnstr(row, name_start, item.get('friendly_name', 'N/A').ljust(col_name_w), col_name_w, attr)

        # --- Modified State Display Logic ---
        decoded = item.get('last_decoded_data', {})
        state_str = ""
        state_attr = attr # Default attribute

        if not decoded:
            state_str = "[No Data]" # Indicate no decoded data received yet
            state_attr = curses.color_pair(7) # Red
        elif 'state' not in decoded:
            state_str = "[State Missing]" # Indicate state signal wasn't in last message
            state_attr = curses.color_pair(5) # Yellow
        else:
            state_str = str(decoded['state']) # Use the actual state value
            # Optional: Add color based on actual state value here if needed
            # state_attr = attr # Already set as default

        brightness = decoded.get('brightness')
        if brightness is not None:
             # Check if state_str is one of our debug strings before appending brightness
             if state_str not in ("[No Data]", "[State Missing]"):
                 state_str += f" ({brightness})"

        # Add control hint if selected
        if is_selected:
            # Only add control hint if we have actual state data
            if state_str not in ("[No Data]", "[State Missing]"):
                 state_str += " [Enter to Control]"
                 # Override state_attr only if adding hint
                 state_attr = curses.color_pair(7) | curses.A_BOLD
            else:
                 # If selected but no data/state, show different hint
                 state_str += " [No State Data]"
                 state_attr = curses.color_pair(5) | curses.A_BOLD # Yellow/Bold
        # Ensure state_attr is set correctly if not selected but in an error state
        elif state_str in ("[No Data]", "[State Missing]"):
             pass # Already set above based on the error condition
        # else: # If not selected and not error state, state_attr is already 'attr'

        stdscr.addnstr(row, state_start, state_str.ljust(col_state_w), col_state_w, state_attr)
        # --- End Modified State Display Logic ---

    # --- Copy Action for Lights Tab ---
    if state.get('_copy_action', False):
        if total:
            item_to_copy = items[selected_idx]
            # Copy relevant info (similar to mapped devices)
            copy_data = {
                "mapping": item_to_copy.get('mapping_config', {}),
                "last_state": item_to_copy.get('last_decoded_data', {}),
                "last_raw_values": item_to_copy.get('last_raw_values', {}),
                "last_updated": time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(item_to_copy.get('last_updated'))),
                "dgn": item_to_copy.get('dgn_hex'),
                "instance": item_to_copy.get('instance'),
                "entity_id": item_to_copy.get('entity_id') # Add entity_id
            }
            txt = json.dumps(copy_data, indent=2)
            copy_to_clipboard(txt)
            copy_msg = f"Light '{item_to_copy.get('friendly_name')}' data copied."
            copy_time = time.time()
        state['_copy_action'] = False # Reset flag


def draw_raw_can_tab(stdscr, h, w, max_rows, state, interface, names, recs): # Accept names, recs
    """Draws the content for a Raw CAN tab."""
    global copy_msg, copy_time
    # Column setup (similar to original)
    left_w = max(25, w // 4)
    mid_w = max(35, (w - left_w - 3) // 2)
    spec_w = w - left_w - mid_w - 3
    left_pad = 2; mid_pad = 2; spec_pad = 2
    left_cw = left_w - left_pad * 2
    mid_start = left_w + 1 + mid_pad
    mid_cw = mid_w - mid_pad * 2
    spec_start = left_w + mid_w + 2 + spec_pad
    spec_cw = spec_w - spec_pad * 2

    # Titles
    stdscr.addnstr(2, left_pad, 'Message Name'.center(left_cw), left_cw, curses.A_BOLD)
    stdscr.addnstr(2, mid_start, 'Raw & Decoded'.center(mid_cw), mid_cw, curses.A_BOLD)
    stdscr.addnstr(2, spec_start, 'Spec JSON'.center(spec_cw), spec_cw, curses.A_BOLD)
    stdscr.hline(3, 0, '-', w)
    # Vertical separators
    for y in range(2, h - 2):
        stdscr.addch(y, left_w, '|')
        stdscr.addch(y, left_w + mid_w + 1, '|')

    # Sort the passed-in names list based on the passed-in recs data
    sort_mode = state['sort_mode']
    if sort_mode == 0: # A->Z
        names.sort()
    elif sort_mode == 1: # Newest
        names.sort(key=lambda n: recs.get(n, {}).get('last_received', 0), reverse=True)
    else: # Oldest
        names.sort(key=lambda n: recs.get(n, {}).get('first_received', 0))

    total = len(names)
    selected_idx = state['selected_idx']
    v_offset = state['v_offset']

    # Adjust view window
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
        stdscr.addstr(4, w - 1, "↑", curses.A_DIM)
    if v_offset + max_rows < total:
        stdscr.addstr(h - 3, w - 1, "↓", curses.A_DIM)

    # Left pane: names
    for idx in range(v_offset, min(v_offset + max_rows, total)):
        row = 4 + idx - v_offset
        name = names[idx]
        is_selected = (idx == selected_idx)
        attr = curses.color_pair(2) | curses.A_BOLD if is_selected else curses.color_pair(3)
        # Show time since last seen
        rec_data = recs.get(name, {})
        time_since = time.time() - rec_data.get('last_received', time.time())
        time_str = f" ({time_since:.1f}s)" if time_since < 600 else "" # Show if < 10 mins
        display_name = (name + time_str).ljust(left_cw)
        stdscr.addnstr(row, left_pad, display_name, left_cw, attr)

    # Right panes: raw/decoded + spec
    if total:
        rec = recs.get(names[selected_idx], {}) # Use .get for safety
        if rec: # Only draw if record exists
            # Raw ID & data
            stdscr.addnstr(4, mid_start, f"ID  : {rec.get('raw_id', 'N/A')}".ljust(mid_cw), mid_cw, curses.color_pair(4) | curses.A_BOLD)
            stdscr.addnstr(5, mid_start, f"Data: {rec.get('raw_data', 'N/A')}".ljust(mid_cw), mid_cw, curses.color_pair(4) | curses.A_BOLD)
            stdscr.addnstr(6, mid_start, f"IFace:{interface}".ljust(mid_cw), mid_cw, curses.color_pair(6))
            # Decoded signals
            line_offset = 8
            decoded_data = rec.get('decoded', {})
            for i, (s, v) in enumerate(decoded_data.items()):
                row = line_offset + i
                if row < h - 2:
                    stdscr.addnstr(row, mid_start, f"{s}: {v}".ljust(mid_cw), mid_cw)
            # Full spec JSON
            try:
                spec_data = rec.get('spec', {})
                spec_lines = json.dumps(spec_data, indent=2).splitlines()
                for i, ln in enumerate(spec_lines):
                    row = 4 + i
                    if row < h - 2:
                        # Highlight DGN if present
                        spec_attr = curses.color_pair(3)
                        if '"dgn_hex":' in ln:
                            spec_attr = curses.color_pair(5) | curses.A_BOLD
                        stdscr.addnstr(row, spec_start, ln.ljust(spec_cw), spec_cw, spec_attr)
            except Exception as e:
                 stdscr.addnstr(4, spec_start, f"Error dumping spec: {e}", spec_cw, curses.A_BOLD | curses.color_pair(5))


    # --- Copy Action for Raw Tab ---
    if state.get('_copy_action', False):
        if total:
            rec_to_copy = recs.get(names[selected_idx], {})
            txt = json.dumps(rec_to_copy.get('spec', {}), indent=2)
            copy_to_clipboard(txt)
            copy_msg = f"Spec for '{names[selected_idx]}' copied."
            copy_time = time.time()
        state['_copy_action'] = False # Reset flag


# Modify handle_input to accept interfaces and current_tab_index
def handle_input_for_tab(c, active_tab_name, state, interfaces, current_tab_index):
    """Handles key presses based on the active tab."""
    # Restore log_records and log_records_lock to global declaration
    # REMOVED log_records, log_records_lock from global list
    global copy_msg, copy_time, light_command_info, INTERFACES
    # Get current state vars
    selected_idx = state['selected_idx']
    v_offset = state['v_offset']
    # Use get for sort_mode as it might not exist if state wasn't found (though we try to prevent that)
    sort_mode = state.get('sort_mode', 0)

    # Determine total items based on tab (using cached data for consistency if paused)
    total = 0
    num_sort_modes = 0
    current_id = None # ID of the item currently selected, used for stable sort selection

    if active_tab_name == "Lights":
        items_list = last_draw_data["lights"] # Use cached light data
        total = len(items_list)
        num_sort_modes = len(light_sort_labels)
        if 0 <= state['selected_idx'] < total:
             current_id = items_list[state['selected_idx']].get('entity_id') # Use entity_id
    # --- Restore Logic for Logs Tab ---
    elif active_tab_name == "Logs":
        # Use cached log data to get the count
        items_list = last_draw_data["logs"] # Get cached log list
        total = len(items_list)
        num_sort_modes = 0 # No sorting for logs
        # ID for logs is just the index, but we don't need stable selection on sort
        current_id = state['selected_idx'] if 0 <= state['selected_idx'] < total else None
    elif " Raw" in active_tab_name:
        iface_index = -1
        try: # Find interface index based on tab name
            iface_name_part = active_tab_name.split(" ")[0].lower()
            # Restore original index calculation
            iface_index = current_tab_index - 2
        except (ValueError, IndexError):
             pass

        if iface_index != -1:
             # Use the correct key for raw data cache
             names_list, _ = last_draw_data.get(f"raw{iface_index}", ([], {})) # Use cached
             total = len(names_list)
             num_sort_modes = len(sort_labels)
             if 0 <= state['selected_idx'] < total:
                 current_id = names_list[state['selected_idx']] # Use name as ID

    # --- Input Handling Logic (Up/Down/Sort/Copy/Enter) ---
    # --- Navigation ---
    if c == curses.KEY_DOWN and total:
        state['selected_idx'] = min(selected_idx + 1, total - 1)
    elif c == curses.KEY_UP and total:
        state['selected_idx'] = max(selected_idx - 1, 0) # Corrected decrement
    elif c == curses.KEY_NPAGE and total: # Page Down
        state['selected_idx'] = min(selected_idx + (curses.LINES - 5), total - 1) # Adjust step size
    elif c == curses.KEY_PPAGE and total: # Page Up
        state['selected_idx'] = max(selected_idx - (curses.LINES - 5), 0)
    elif c == curses.KEY_HOME:
        state['selected_idx'] = 0
    elif c == curses.KEY_END and total:
        state['selected_idx'] = total - 1

    # --- Sorting ---
    elif c in (ord('s'), ord('S')) and num_sort_modes > 0: # Check if sorting is applicable
        # current_id was determined above using cached data
        state['sort_mode'] = (state['sort_mode'] + 1) % num_sort_modes

        # Re-find the selected item's index AFTER sorting (using cached data again)
        if current_id is not None: # Check if we have a valid ID
            new_items_sorted = [] # This will be a list of IDs (entity_id or message name)
            if active_tab_name == "Lights":
                items_list = last_draw_data["lights"] # Use cached light data
                sm = state['sort_mode']
                items_list_copy = list(items_list)
                if sm == 0: items_list_copy.sort(key=lambda x: (x.get('suggested_area', 'zzz').lower(), x.get('friendly_name', 'zzz').lower()))
                elif sm == 1: items_list_copy.sort(key=lambda x: x.get('friendly_name', 'zzz').lower())
                elif sm == 2: items_list_copy.sort(key=lambda x: x.get('last_updated', 0), reverse=True)
                new_items_sorted = [item.get('entity_id') for item in items_list_copy]

            elif " Raw" in active_tab_name:
                iface_index = -1
                try:
                    iface_name_part = active_tab_name.split(" ")[0].lower()
                    # Restore original index calculation
                    iface_index = current_tab_index - 2
                except (ValueError, IndexError): pass

                if iface_index != -1:
                    # Use correct cache key
                    names_list, recs_dict = last_draw_data.get(f"raw{iface_index}", ([], {})) # Use cached
                    sm = state['sort_mode']
                    names_list_copy = list(names_list)
                    if sm == 0: new_items_sorted = sorted(names_list_copy)
                    elif sm == 1: new_items_sorted = sorted(names_list_copy, key=lambda n: recs_dict.get(n, {}).get('last_received', 0), reverse=True)
                    else: new_items_sorted = sorted(names_list_copy, key=lambda n: recs_dict.get(n, {}).get('first_received', 0))

            try:
                # Find index of the original ID in the newly sorted list of IDs
                state['selected_idx'] = new_items_sorted.index(current_id)
            except (ValueError, IndexError): # Handle cases where ID might not be found (e.g., data changed rapidly)
                state['selected_idx'] = 0 # Fallback
        else:
             state['selected_idx'] = 0 # Fallback if no current_id

        state['v_offset'] = 0 # Reset scroll on sort

    # --- Copying ---
    elif c in (ord('c'), ord('C')):
        # Restore original logic (allow copy on Logs tab)
        state['_copy_action'] = True # Signal draw function to perform copy

    # --- Command/Control (Lights Only for now) ---
    elif c == curses.KEY_ENTER or c == ord('\n'):
        if active_tab_name == "Lights" and total:
            # Use cached data to identify the selected item without needing lock
            selected_item_data = last_draw_data["lights"][state['selected_idx']]
            entity_id = selected_item_data.get('entity_id')
            light_name = selected_item_data.get('friendly_name', 'Unknown Light')

            if not entity_id:
                copy_msg = "Error: Could not get entity_id for selected light."
                copy_time = time.time()
                return # Exit if no entity_id

            # Get command info from the global lookup
            cmd_info = light_command_info.get(entity_id)
            if not cmd_info:
                copy_msg = f"Error: No command info found for '{light_name}' (DGN 1FEDA mapping missing?)."
                copy_time = time.time()
                return # Exit if no command info

            instance = cmd_info['instance']
            dgn = cmd_info['dgn'] # Should be 0x1FEDA

            # Determine current state and desired command (Simple Toggle ON/OFF)
            current_state = selected_item_data.get('last_decoded_data', {}).get('state', 'Unknown').upper()
            command = 0 # Default to Set Level (ON)
            brightness = 100 # Default brightness for ON (0-100%)
            duration = 251 # Instant
            action_desc = "Turning ON"

            # Check if the light is currently considered ON
            # Be lenient with state check (e.g., "ON", "ON (50%)", "1")
            if current_state != 'OFF' and current_state != 'UNKNOWN' and current_state != '0':
                command = 3 # OFF command
                brightness = 0 # Brightness irrelevant for OFF command per spec
                action_desc = "Turning OFF"

            # Construct CAN ID (Priority 6, PGN 0x1FEDA, Source 0x63)
            priority = 6
            source_addr = 0x63 # 99
            # J1939 ID construction: (Prio << 26) | (PGN << 8) | SourceAddr
            # PGN for 1FEDA is 0x1FEDA
            can_id = (priority << 26) | (dgn << 8) | source_addr

            # Construct Data Payload (8 bytes) - RVC_LIGHT_COMMAND (1FEDA)
            # Byte 0: Instance
            # Byte 1: Reserved (FF)
            # Byte 2: Level (0-100%, FE=Ignore, FF=Invalid)
            # Byte 3: Command (0=Set Level, 3=Off)
            # Byte 4: Duration (0-25.0s, 251=Instant, 254=Ignore, 255=Invalid)
            # Bytes 5-7: Reserved (FF FF FF)
            data = bytearray(8)
            data[0] = instance & 0xFF
            data[1] = 0xFF
            data[2] = brightness & 0xFF
            data[3] = command & 0xFF
            data[4] = duration & 0xFF
            data[5] = 0xFF
            data[6] = 0xFF
            data[7] = 0xFF

            # Send command on the first interface
            if INTERFACES:
                target_interface = INTERFACES[0]
                logging.info(f"Attempting to send command for '{light_name}' ({action_desc}) via {target_interface}")
                if send_can_command(target_interface, can_id, bytes(data)):
                    copy_msg = f"Sent {action_desc} command for '{light_name}'."
                    # Optimistically update the cached state? Risky without confirmation.
                    # Maybe clear state to 'Updating...'?
                    # For now, just rely on the next status message received.
                else:
                    copy_msg = f"Error sending command for '{light_name}'."
            else:
                copy_msg = "Error: No CAN interfaces defined to send command."

            copy_time = time.time()

        # elif active_tab_name == "Mapped Devices" and total:
        #     # Placeholder for potential future actions on other devices
        #     pass

# --- Entry Point ---
if __name__ == '__main__':
    # Argument Parsing
    parser = argparse.ArgumentParser(description='RV-C CAN Bus Monitor')
    parser.add_argument('-i', '--interfaces', nargs='+', default=DEFAULT_INTERFACES, help='CAN interface names (e.g., can0 can1)')
    parser.add_argument('-d', '--definitions', default=DEFAULT_RVC_SPEC_PATH, help='Path to the RVC definitions JSON file') # Use constant
    parser.add_argument('-m', '--mapping', default=DEFAULT_DEVICE_MAPPING_PATH, help='Path to the device mapping YAML file') # Use constant
    args = parser.parse_args()

    # --- Load Definitions & Mapping ---
    logging.info(f"Attempting to load RVC spec from: {args.definitions}")
    sys.stderr.flush() # Force flush after first log
    logging.info(f"Attempting to load device mapping from: {args.mapping}")
    sys.stderr.flush() # Force flush after second log
    # Call the renamed function with both paths and unpack all return values
    decoder_map, device_mapping, device_lookup, light_entity_ids, entity_id_lookup, light_command_info = load_config_data(args.definitions, args.mapping)

    # Check if decoder_map loaded successfully (load_config_data now handles sys.exit)
    # No need for explicit check here if sys.exit is used on critical load errors

    # REMOVED erroneous load_device_mapping call

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

    # --- Pre-populate light_device_states --- START
    logging.info("Pre-populating light states...") # Added log
    # Iterate over the entity_id_lookup created during loading
    for entity_id, config in entity_id_lookup.items():
        # Check if this entity was identified as a light
        if entity_id in light_entity_ids:
            # Add placeholder state using the config from entity_id_lookup
            with light_states_lock:
                light_device_states[entity_id] = {
                    'entity_id': entity_id,
                    'friendly_name': config.get('friendly_name', entity_id),
                    'suggested_area': config.get('suggested_area', 'Unknown'),
                    'last_updated': 0, # Placeholder
                    'last_interface': 'N/A',
                    'last_raw_values': {},
                    'last_decoded_data': {'state': 'unavailable'}, # Initial state
                    'mapping_config': config,
                    # DGN/Instance might not be directly in this config if template was used,
                    # but command info is in light_command_info. We can add them if needed for display.
                    # 'dgn_hex': config.get('dgn'), # Example if needed
                    # 'instance': config.get('instance'), # Example if needed
                }
    logging.info(f"Pre-populated {len(light_device_states)} light entities.") # Log count based on populated states
    # --- Pre-populate light_device_states --- END

    # Start reader threads only if definitions loaded successfully
    # Note: decoder_map check is implicitly true if we reached here
    logging.info("Starting CAN reader threads...") # Log before starting threads
    threads = []
    for interface in INTERFACES:
        thread = threading.Thread(target=reader_thread, args=(interface,), name=f"Reader-{interface}")
        thread.daemon = True
        threads.append(thread)
        thread.start()
        logging.info(f"Started reader thread for {interface}.") # Log after each thread start

    # --- Start Curses UI ---
    # REMOVE Add the ListLogHandler *just before* starting curses
    # logging.info("Adding ListLogHandler before starting UI...")
    # logging.getLogger().addHandler(list_handler)

    logging.info("Attempting to start curses UI...") # Log before curses
    # Remove the console handler *just before* starting curses
    logging.getLogger().removeHandler(console_handler)
    try:
        # Pass the list_handler instance to curses.wrapper
        curses.wrapper(draw_screen, INTERFACES, list_handler) # Pass interfaces list and handler
    except Exception as e:
        # Ensure console handler is back if curses fails
        logging.getLogger().addHandler(console_handler)
        logging.exception("Unhandled exception in curses main loop!")
    finally:
        # Ensure console handler is back after curses finishes or crashes
        if console_handler not in logging.getLogger().handlers:
             logging.getLogger().addHandler(console_handler)
        # Remove the list handler during cleanup
        logging.info("Removing ListLogHandler...")
        logging.getLogger().removeHandler(list_handler)
        logging.info("Requesting threads to stop...")
        stop_event.set()
        for t in threads:
            t.join(timeout=1.0) # Add a timeout to prevent hanging
        logging.info("Threads stopped. Exiting.")
