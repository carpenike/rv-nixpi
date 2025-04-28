import json
import threading
import curses
import time
import sys
import base64
from collections import defaultdict
import can
import yaml # Added for device mapping
import os # Added for file existence check

# --- Configuration ---
RVC_SPEC_PATH = '/etc/nixos/files/rvc.json'
DEVICE_MAPPING_PATH = '/etc/nixos/files/device_mapping.yaml'
INTERFACES = ['can0', 'can1']

# --- Load Definitions ---
def load_definitions():
    """Loads RVC spec and device mappings."""
    # Load RVC Spec
    try:
        with open(RVC_SPEC_PATH) as f:
            specs = json.load(f)['messages']
        decoder_map = {entry['id']: entry for entry in specs if 'id' in entry} # Key by decimal ID
        print(f"Loaded {len(decoder_map)} RVC message specs from {RVC_SPEC_PATH}")
    except Exception as e:
        print(f"Error loading RVC spec ({RVC_SPEC_PATH}): {e}", file=sys.stderr)
        sys.exit(1)

    # Load Device Mapping
    device_mapping = {}
    device_lookup = {} # Processed lookup: (dgn_hex, instance_str) -> mapped_config
    if os.path.exists(DEVICE_MAPPING_PATH):
        try:
            with open(DEVICE_MAPPING_PATH) as f:
                raw_mapping = yaml.safe_load(f)
                # Process into a more direct lookup table
                templates = raw_mapping.get('templates', {})
                device_mapping = raw_mapping # Keep raw for potential future use

                for dgn_hex, instances in raw_mapping.items():
                    if dgn_hex == 'templates': continue
                    for instance_str, configs in instances.items():
                        for config in configs:
                            # Apply template if specified
                            template_name = config.pop('<<', None) # Use pop to remove merge key
                            if template_name and template_name in templates:
                                # Shallow merge: config overrides template
                                merged_config = {**templates[template_name], **config}
                            else:
                                merged_config = config

                            # Ensure essential keys are present
                            if 'ha_name' in merged_config and 'friendly_name' in merged_config:
                                device_lookup[(dgn_hex.upper(), str(instance_str))] = merged_config
                            else:
                                print(f"Warning: Skipping mapping entry under DGN {dgn_hex}, Instance {instance_str} due to missing 'ha_name' or 'friendly_name'. Config: {config}", file=sys.stderr)

            print(f"Loaded {len(device_lookup)} device mappings from {DEVICE_MAPPING_PATH}")
        except Exception as e:
            print(f"Warning: Could not load or parse device mapping ({DEVICE_MAPPING_PATH}): {e}", file=sys.stderr)
            # Continue without device mapping if it fails
    else:
        print(f"Warning: Device mapping file not found ({DEVICE_MAPPING_PATH}). Mapped Devices tab will be empty.", file=sys.stderr)

    return decoder_map, device_mapping, device_lookup

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

# OSC52 copy to clipboard
def copy_to_clipboard(text):
    payload = base64.b64encode(text.encode()).decode()
    sys.stdout.write(f"\x1b]52;c;{payload}\x07")
    sys.stdout.flush()

# --- Global State ---
decoder_map, device_mapping, device_lookup = load_definitions()
latest_raw_records = {iface: {} for iface in INTERFACES} # Renamed from latest_records
mapped_device_states = {} # Keyed by ha_name
stop_event = threading.Event()
copy_msg = None
copy_time = 0
sort_labels = ['A→Z', 'Newest', 'Oldest'] # For raw view
mapped_sort_labels = ['Area→Name', 'Name', 'Newest'] # For mapped view

# --- Reader Thread ---
def reader_thread(interface):
    """Reads CAN messages, decodes, and updates raw records and mapped device states."""
    try:
        bus = can.interface.Bus(channel=interface, interface='socketcan')
    except Exception as e:
        print(f"Error opening CAN interface {interface}: {e}", file=sys.stderr)
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

                # --- Update Mapped Device State ---
                dgn_hex = entry.get('dgn_hex')
                instance_raw = raw_values.get('instance') # Get raw instance value

                if dgn_hex and instance_raw is not None:
                    instance_str = str(instance_raw)
                    # Check specific instance, then default
                    mapped_config = device_lookup.get((dgn_hex.upper(), instance_str))
                    if not mapped_config:
                         mapped_config = device_lookup.get((dgn_hex.upper(), 'default'))

                    if mapped_config:
                        ha_name = mapped_config['ha_name']
                        state_entry = mapped_device_states.get(ha_name, {})
                        state_entry.update({
                            'ha_name': ha_name,
                            'friendly_name': mapped_config.get('friendly_name', ha_name),
                            'suggested_area': mapped_config.get('suggested_area', 'Unknown'),
                            'last_updated': now,
                            'last_interface': interface,
                            'last_raw_values': raw_values, # Store raw values
                            'last_decoded_data': decoded_data, # Store formatted values
                            'mapping_config': mapped_config, # Store the mapping config itself
                            'dgn_hex': dgn_hex,
                            'instance': instance_str
                        })
                        mapped_device_states[ha_name] = state_entry
            # --- End Update Mapped Device State ---

        except can.CanError as e:
            print(f"CAN Error on {interface}: {e}", file=sys.stderr)
            time.sleep(5) # Avoid spamming errors if bus goes down
        except Exception as e:
            print(f"Error in reader thread for {interface}: {e}", file=sys.stderr)
            # Optionally add more robust error handling or thread restart logic

# --- Main UI Drawing ---
def draw_screen(stdscr):
    global copy_msg, copy_time
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

    tabs = ["Mapped Devices", "CAN0 Raw", "CAN1 Raw"]
    tab_keys = ['1', '9', '0'] # Keys to activate tabs
    current_tab_index = 0

    # State per tab (selection, offset, sort mode)
    tab_state = {
        "Mapped Devices": {'selected_idx': 0, 'v_offset': 0, 'sort_mode': 0},
        "CAN0 Raw": {'selected_idx': 0, 'v_offset': 0, 'sort_mode': 0},
        "CAN1 Raw": {'selected_idx': 0, 'v_offset': 0, 'sort_mode': 0},
    }

    while True:
        stdscr.erase()
        h, w = stdscr.getmaxyx()
        active_tab_name = tabs[current_tab_index]
        state = tab_state[active_tab_name] # Current tab's state

        # --- Header ---
        header_text = ""
        for i, name in enumerate(tabs):
            key = tab_keys[i]
            indicator = "*" if i == current_tab_index else " "
            header_text += f"[{key}]{indicator}{name}{indicator}  "

        if active_tab_name == "Mapped Devices":
             sort_label = mapped_sort_labels[state['sort_mode']]
             header_text += f"[S] Sort:{sort_label}  "
        elif "Raw" in active_tab_name:
             sort_label = sort_labels[state['sort_mode']]
             header_text += f"[S] Sort:{sort_label}  "

        header_text += "[C] Copy  [Q] Quit"
        stdscr.attron(curses.color_pair(1) | curses.A_BOLD)
        stdscr.addnstr(0, 0, header_text.ljust(w), w)
        stdscr.attroff(curses.color_pair(1) | curses.A_BOLD)
        stdscr.hline(1, 0, '-', w)

        # --- Main Content Area ---
        max_rows = h - 5 # Rows available for content list

        if active_tab_name == "Mapped Devices":
            draw_mapped_devices_tab(stdscr, h, w, max_rows, state)
        elif active_tab_name == "CAN0 Raw":
            draw_raw_can_tab(stdscr, h, w, max_rows, state, INTERFACES[0])
        elif active_tab_name == "CAN1 Raw":
            draw_raw_can_tab(stdscr, h, w, max_rows, state, INTERFACES[1])

        # --- Copy Notification ---
        if copy_msg and time.time() - copy_time < 3:
            stdscr.attron(curses.color_pair(5) | curses.A_BOLD)
            stdscr.addnstr(h - 2, 0, copy_msg[:w - 1].ljust(w - 1), w - 1)
            stdscr.attroff(curses.color_pair(5) | curses.A_BOLD)

        # --- Footer ---
        footer = "Arrows: Navigate | "
        footer += " ".join([f"{key}:{name}" for key, name in zip(tab_keys, tabs)])
        footer += " | S: Sort | C: Copy | Q: Quit"
        stdscr.attron(curses.color_pair(1) | curses.A_BOLD)
        stdscr.addnstr(h - 1, 0, footer[:w - 1].ljust(w-1), w - 1)
        stdscr.attroff(curses.color_pair(1) | curses.A_BOLD)

        stdscr.refresh()

        # --- Input Handling ---
        c = stdscr.getch() # Blocking call

        if c in (ord('q'), ord('Q'), ord('0') and active_tab_name != "CAN1 Raw"): # Allow 0 for CAN1 tab
             if active_tab_name == "CAN1 Raw" and c == ord('0'):
                 current_tab_index = tabs.index("CAN1 Raw")
             else:
                 stop_event.set()
                 break # Exit main loop

        # Tab switching
        try:
            key_char = chr(c)
            if key_char in tab_keys:
                current_tab_index = tab_keys.index(key_char)
                # Reset selection when switching tabs? Optional.
                # state['selected_idx'] = 0
                # state['v_offset'] = 0
                continue # Redraw immediately
        except ValueError: # Handle non-character keys like arrows
            pass

        # Context-aware actions (Sort, Copy, Navigation)
        handle_input_for_tab(c, active_tab_name, state)


def draw_mapped_devices_tab(stdscr, h, w, max_rows, state):
    """Draws the 'Mapped Devices' tab content."""
    global copy_msg, copy_time
    # Column setup
    col_area_w = max(15, w // 6)
    col_name_w = max(25, w // 3)
    col_state_w = w - col_area_w - col_name_w - 3 # Remaining width for state
    pad = 2
    area_start = pad
    name_start = area_start + col_area_w + 1 + pad
    state_start = name_start + col_name_w + 1 + pad

    # Titles
    stdscr.addnstr(2, area_start, "Area".ljust(col_area_w), col_area_w, curses.A_BOLD)
    stdscr.addnstr(2, name_start, "Friendly Name".ljust(col_name_w), col_name_w, curses.A_BOLD)
    stdscr.addnstr(2, state_start, "State / Last Data".ljust(col_state_w), col_state_w, curses.A_BOLD)
    stdscr.hline(3, 0, '-', w)
    # Vertical separators
    for y in range(2, h - 2):
        stdscr.addch(y, area_start + col_area_w, '|')
        stdscr.addch(y, name_start + col_name_w, '|')

    # Prepare sorted list of devices
    items = list(mapped_device_states.values())
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

    # Draw list items
    for idx in range(v_offset, min(v_offset + max_rows, total)):
        row = 4 + idx - v_offset
        item = items[idx]
        is_selected = (idx == selected_idx)
        attr = curses.color_pair(2) | curses.A_BOLD if is_selected else curses.color_pair(3)
        area_attr = curses.color_pair(6) if not is_selected else attr # Different color for area

        stdscr.addnstr(row, area_start, item.get('suggested_area', 'N/A').ljust(col_area_w), col_area_w, area_attr)
        stdscr.addnstr(row, name_start, item.get('friendly_name', 'N/A').ljust(col_name_w), col_name_w, attr)

        # Display state - customize this based on device types
        state_str = ", ".join(f"{k}={v}" for k, v in item.get('last_decoded_data', {}).items())
        # Maybe add time since last update: f"{time.time() - item.get('last_updated', 0):.1f}s ago"
        stdscr.addnstr(row, state_start, state_str.ljust(col_state_w), col_state_w, attr)

    # --- Copy Action for Mapped Tab ---
    if state.get('_copy_action', False):
        if total:
            item_to_copy = items[selected_idx]
            # Copy relevant info: mapping config + last state
            copy_data = {
                "mapping": item_to_copy.get('mapping_config', {}),
                "last_state": item_to_copy.get('last_decoded_data', {}),
                "last_raw_values": item_to_copy.get('last_raw_values', {}),
                "last_updated": time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(item_to_copy.get('last_updated'))),
                "dgn": item_to_copy.get('dgn_hex'),
                "instance": item_to_copy.get('instance')
            }
            txt = json.dumps(copy_data, indent=2)
            copy_to_clipboard(txt)
            copy_msg = f"Mapped device '{item_to_copy.get('friendly_name')}' data copied."
            copy_time = time.time()
        state['_copy_action'] = False # Reset flag


def draw_raw_can_tab(stdscr, h, w, max_rows, state, interface):
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

    # Prepare sorted list
    recs = latest_raw_records[interface]
    names = []
    sort_mode = state['sort_mode']
    if sort_mode == 0: # A->Z
        names = sorted(recs.keys())
    elif sort_mode == 1: # Newest
        names = sorted(recs.keys(), key=lambda n: recs[n]['last_received'], reverse=True)
    else: # Oldest
        names = sorted(recs.keys(), key=lambda n: recs[n]['first_received'])

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

    # Left pane: names
    for idx in range(v_offset, min(v_offset + max_rows, total)):
        row = 4 + idx - v_offset
        name = names[idx]
        is_selected = (idx == selected_idx)
        attr = curses.color_pair(2) | curses.A_BOLD if is_selected else curses.color_pair(3)
        # Show time since last seen
        time_since = time.time() - recs[name]['last_received']
        time_str = f" ({time_since:.1f}s)" if time_since < 600 else "" # Show if < 10 mins
        display_name = (name + time_str).ljust(left_cw)
        stdscr.addnstr(row, left_pad, display_name, left_cw, attr)

    # Right panes: raw/decoded + spec
    if total:
        rec = recs[names[selected_idx]]
        # Raw ID & data
        stdscr.addnstr(4, mid_start, f"ID  : {rec['raw_id']}".ljust(mid_cw), mid_cw, curses.color_pair(4) | curses.A_BOLD)
        stdscr.addnstr(5, mid_start, f"Data: {rec['raw_data']}".ljust(mid_cw), mid_cw, curses.color_pair(4) | curses.A_BOLD)
        stdscr.addnstr(6, mid_start, f"IFace:{interface}".ljust(mid_cw), mid_cw, curses.color_pair(6))
        # Decoded signals
        line_offset = 8
        for i, (s, v) in enumerate(rec['decoded'].items()):
            row = line_offset + i
            if row < h - 2:
                stdscr.addnstr(row, mid_start, f"{s}: {v}".ljust(mid_cw), mid_cw)
        # Full spec JSON
        try:
            spec_lines = json.dumps(rec['spec'], indent=2).splitlines()
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
            txt = json.dumps(recs[names[selected_idx]]['spec'], indent=2)
            copy_to_clipboard(txt)
            copy_msg = f"Spec for '{names[selected_idx]}' copied."
            copy_time = time.time()
        state['_copy_action'] = False # Reset flag


def handle_input_for_tab(c, active_tab_name, state):
    """Handles key presses based on the active tab."""
    selected_idx = state['selected_idx']
    v_offset = state['v_offset']
    sort_mode = state['sort_mode']

    # Determine total items based on tab
    total = 0
    if active_tab_name == "Mapped Devices":
        total = len(mapped_device_states)
        num_sort_modes = len(mapped_sort_labels)
    elif active_tab_name == "CAN0 Raw":
        total = len(latest_raw_records[INTERFACES[0]])
        num_sort_modes = len(sort_labels)
    elif active_tab_name == "CAN1 Raw":
        total = len(latest_raw_records[INTERFACES[1]])
        num_sort_modes = len(sort_labels)

    # --- Navigation ---
    if c == curses.KEY_DOWN and total:
        state['selected_idx'] = min(selected_idx + 1, total - 1)
    elif c == curses.KEY_UP and total:
        state['selected_idx'] = max(selected_idx - 1, 0)
    elif c == curses.KEY_NPAGE and total: # Page Down
        state['selected_idx'] = min(selected_idx + (curses.LINES - 5), total - 1) # Adjust step size
    elif c == curses.KEY_PPAGE and total: # Page Up
        state['selected_idx'] = max(selected_idx - (curses.LINES - 5), 0)
    elif c == curses.KEY_HOME:
        state['selected_idx'] = 0
    elif c == curses.KEY_END and total:
        state['selected_idx'] = total - 1

    # --- Sorting ---
    elif c in (ord('s'), ord('S')):
        # Need to get the currently selected item's identifier BEFORE sorting
        current_id = None
        items = []
        if active_tab_name == "Mapped Devices":
            items = list(mapped_device_states.values())
            if 0 <= selected_idx < len(items): current_id = items[selected_idx].get('ha_name')
        elif "Raw" in active_tab_name:
            iface = INTERFACES[0] if active_tab_name == "CAN0 Raw" else INTERFACES[1]
            items = list(latest_raw_records[iface].keys())
            if 0 <= selected_idx < len(items): current_id = items[selected_idx] # Name is the ID here

        state['sort_mode'] = (sort_mode + 1) % num_sort_modes

        # Re-find the selected item's index AFTER sorting
        if current_id:
            new_items = []
            if active_tab_name == "Mapped Devices":
                 new_items_list = list(mapped_device_states.values())
                 # Re-sort based on new mode to find index
                 sm = state['sort_mode']
                 if sm == 0: new_items_list.sort(key=lambda x: (x.get('suggested_area', 'zzz').lower(), x.get('friendly_name', 'zzz').lower()))
                 elif sm == 1: new_items_list.sort(key=lambda x: x.get('friendly_name', 'zzz').lower())
                 elif sm == 2: new_items_list.sort(key=lambda x: x.get('last_updated', 0), reverse=True)
                 new_items = [item.get('ha_name') for item in new_items_list]

            elif "Raw" in active_tab_name:
                 iface = INTERFACES[0] if active_tab_name == "CAN0 Raw" else INTERFACES[1]
                 recs = latest_raw_records[iface]
                 sm = state['sort_mode']
                 if sm == 0: new_items = sorted(recs.keys())
                 elif sm == 1: new_items = sorted(recs.keys(), key=lambda n: recs[n]['last_received'], reverse=True)
                 else: new_items = sorted(recs.keys(), key=lambda n: recs[n]['first_received'])

            try:
                state['selected_idx'] = new_items.index(current_id)
            except ValueError:
                state['selected_idx'] = 0 # Fallback if not found
        else:
             state['selected_idx'] = 0 # Fallback if no item was selected

        state['v_offset'] = 0 # Reset scroll on sort

    # --- Copying ---
    elif c in (ord('c'), ord('C')):
        state['_copy_action'] = True # Signal draw function to perform copy

    # --- Command/Control (Placeholder) ---
    # elif c == curses.KEY_ENTER or c == ord('\n'):
    #     if active_tab_name == "Mapped Devices" and total:
    #         selected_item = list(mapped_device_states.values())[selected_idx]
    #         # TODO: Implement command logic based on selected_item['mapping_config']
    #         # Example: Show menu, construct CAN message, send via bus.write()
    #         copy_msg = f"Action on '{selected_item.get('friendly_name')}' (Not Implemented)"
    #         copy_time = time.time()


# --- Entry Point ---
if __name__ == '__main__':
    # Start reader threads only if definitions loaded successfully
    if decoder_map:
        print("Starting CAN reader threads...")
        threads = []
        for iface in INTERFACES:
            thread = threading.Thread(target=reader_thread, args=(iface,), daemon=True)
            thread.start()
            threads.append(thread)

        # Give threads a moment to start and potentially fail on CAN init
        time.sleep(0.5)

        # Check if threads are alive before starting curses
        if any(t.is_alive() for t in threads):
             print("Starting UI...")
             curses.wrapper(draw_screen)
             print("UI exited. Waiting for threads to stop...")
        else:
             print("No reader threads started successfully. Exiting.", file=sys.stderr)
             stop_event.set() # Ensure any potentially stuck threads are signalled

        # Wait for threads to finish after stop_event is set
        for t in threads:
             if t.is_alive():
                 t.join(timeout=2) # Wait max 2 seconds per thread
        print("All threads stopped.")

    else:
        print("Could not load RVC specifications. Exiting.", file=sys.stderr)
