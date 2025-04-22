#!/usr/bin/env python3

import yaml
import math
import re
import sys
from collections import defaultdict

# --- Configuration ---
YAML_FILE = './rvc-spec.yml'
DBC_FILE = './rvc.dbc'
DEFAULT_TRANSMITTER = 'RVCController'
DEFAULT_RECEIVER = 'RVCController' # Or Vector__XXX if preferred

# --- Helper Functions ---

def sanitize_name(name):
    """Makes a name compliant with DBC identifier rules."""
    # Replace invalid characters with underscores
    name = re.sub(r'[^a-zA-Z0-9_]', '_', str(name))
    # Remove leading/trailing underscores
    name = name.strip('_')
    # Ensure it doesn't start with a digit
    if name and name[0].isdigit():
        name = '_' + name
    # Handle potentially empty names after sanitization
    if not name:
        return "unnamed"
    return name

def parse_bit_string(bit_str):
    """Parses bit strings like '0', '0-1', returning start bit offset and length."""
    if isinstance(bit_str, int):
        return bit_str, 1
    bit_str = str(bit_str)
    if '-' in bit_str:
        start, end = map(int, bit_str.split('-'))
        if start > end:
            raise ValueError(f"Invalid bit range: {bit_str} (start > end)")
        return start, (end - start + 1)
    else:
        try:
            return int(bit_str), 1
        except ValueError:
             raise ValueError(f"Invalid bit format: {bit_str}")

def calculate_start_bit_length(byte_info, bit_info):
    """Calculates DBC start bit (Intel format LSB=0) and length."""
    byte_start_index = 0
    num_bytes = 0

    if isinstance(byte_info, int):
        byte_start_index = byte_info
        num_bytes = 1
    elif isinstance(byte_info, str):
        if '-' in byte_info:
            start, end = map(int, byte_info.split('-'))
            if start > end:
                 raise ValueError(f"Invalid byte range: {byte_info} (start > end)")
            byte_start_index = start
            num_bytes = end - start + 1
        else:
            try:
                byte_start_index = int(byte_info)
                num_bytes = 1
            except ValueError:
                raise ValueError(f"Invalid byte format: {byte_info}")
    else:
         raise ValueError(f"Invalid byte format: {byte_info}")

    if bit_info:
        bit_offset_within_byte, bit_len = parse_bit_string(bit_info)
        # Intel format: Start bit is the LSB position.
        # Bit 0 is the LSB of the first byte (byte_start_index).
        start_bit = byte_start_index * 8 + bit_offset_within_byte
        length = bit_len
    else:
        # Full byte(s)
        start_bit = byte_start_index * 8
        length = num_bytes * 8

    return start_bit, length

def get_scaling_offset_signed(param_name, param_type, unit):
    """Determines scaling factor, offset, and signedness."""
    factor = 1.0
    offset = 0.0
    signed = False
    unit_str = str(unit) if unit else ""

    type_lower = str(param_type).lower() if param_type else ""

    # Signed types
    if 'int' in type_lower and 'uint' not in type_lower:
        signed = True

    # Unit-based scaling (add more rules as needed)
    if unit_str == 'V':
        if '16' in type_lower or '32' in type_lower: factor = 0.001
        elif '8' in type_lower: factor = 0.1 # e.g., Z0004 voltage levels
    elif unit_str == 'A':
        if '32' in type_lower: factor = 0.001
        elif '16' in type_lower: factor = 0.1
        # uint8 amps often factor 1
    elif unit_str == 'Deg C':
        if '16' in type_lower:
            factor = 0.1
            # Specific params have offset
            if param_name in ["source_temperature", "fet_temperature", "transformer_temperature", "ambient_temp"]:
                 offset = -40.0
                 # signed = True # Temperature can be negative, but DBC uses offset for this
        elif '8' in type_lower:
            factor = 1.0
            offset = -40.0
            # signed = True
    elif unit_str == 'pct':
        if '8' in type_lower:
            # Specific params use 0.5 scaling
            specific_pct_params = [
                "state_of_charge", "state_of_health", "relative_capacity",
                "fan_speed", "max_fan_speed", "max_ac_output_level",
                "air_conditioning_output_level", "engine_load",
                "charge_curr_pct_of_max", "maximum_charge_current_as_percent",
                "charge_rate_limit_as_percent", "operating_status", "desired_level",
                "master_brightness", "red_brightness", "green_brightness", "blue_brightness",
                "brightness", "motor_duty", "indicator_brightness"
            ]
            if param_name in specific_pct_params:
                factor = 0.5
            # else factor 1
    elif unit_str == 'kph' and '16' in type_lower: factor = 0.01
    elif unit_str == 'mV/s' and '16' in type_lower: factor = 0.001
    elif unit_str == 'lph' and '16' in type_lower: factor = 0.01
    elif unit_str == 'Ah':
         if '16' in type_lower and param_name == "capacity_remaining": factor = 0.1
         # else factor 1 (e.g., battery_bank_size)
    elif unit_str == 'Hz':
         if '16' in type_lower: factor = 0.01
         # uint8 factor 1
    elif unit_str == 'v': # Lowercase 'v' often means 0.001 scaling in this spec
        if '16' in type_lower or '32' in type_lower: factor = 0.001
    elif unit_str == 'a': # Lowercase 'a' often means 0.1 scaling
        if '16' in type_lower: factor = 0.1
    elif unit_str == 'mV/K' and '8' in type_lower: factor = 0.001 # Temp comp constant
    elif unit_str == 'VAr' and '16' in type_lower: factor = 1 # Reactive power
    elif unit_str == 'W' and '16' in type_lower: factor = 1 # Real power
    elif unit_str == 'w' and '16' in type_lower: factor = 1 # Load sense threshold
    elif unit_str == 'V' and param_name == 'hp_dc_voltage': factor = 0.000001 # Special case

    # Format factor/offset nicely for DBC
    factor_str = f"{factor:.10g}".rstrip('0').rstrip('.')
    offset_str = f"{offset:.10g}".rstrip('0').rstrip('.')

    return factor_str, offset_str, signed

def generate_val_table_line(msg_id_dec, signal_name, values_dict):
    """Generates the VAL_ line string."""
    if not values_dict or not isinstance(values_dict, dict):
        return None
    val_items = []
    for val, desc in values_dict.items():
        # Ensure description is quoted, escape existing quotes
        desc_quoted = f'"{str(desc).replace("\"", "\\\"")}"'
        try:
            # Ensure value is treated as integer if possible
            val_int = int(str(val))
            val_items.append(f"{val_int} {desc_quoted}")
        except ValueError:
             print(f"Warning: Non-integer value '{val}' in VAL table for {signal_name}, using as string.", file=sys.stderr)
             val_items.append(f'"{val}" {desc_quoted}') # Fallback to string if not int

    if not val_items:
        return None

    return f'VAL_ {msg_id_dec} {signal_name} {" ".join(val_items)} ;'

# --- Main Script ---
def main():
    print(f"Reading YAML spec from: {YAML_FILE}")
    try:
        with open(YAML_FILE, 'r') as f:
            spec = yaml.safe_load(f)
    except FileNotFoundError:
        print(f"Error: YAML file not found at {YAML_FILE}", file=sys.stderr)
        sys.exit(1)
    except yaml.YAMLError as e:
        print(f"Error parsing YAML file {YAML_FILE}: {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"An unexpected error occurred reading {YAML_FILE}: {e}", file=sys.stderr)
        sys.exit(1)

    if not spec or not isinstance(spec, dict):
        print("Error: YAML file is empty or not a valid dictionary.", file=sys.stderr)
        sys.exit(1)

    dbc_lines = []
    dbc_lines.append('VERSION ""')
    dbc_lines.append("")
    dbc_lines.append("NS_ :")
    dbc_lines.append("    NS_DESC_")
    dbc_lines.append("    CM_")
    dbc_lines.append("    BA_DEF_")
    dbc_lines.append("    BA_")
    dbc_lines.append("    VAL_")
    dbc_lines.append("")
    dbc_lines.append("BS_:")
    dbc_lines.append("")
    dbc_lines.append(f"BU_: {DEFAULT_TRANSMITTER}") # Assuming one node
    dbc_lines.append("")

    processed_messages = {} # hex_id -> {'bo': str, 'sg': [str], 'val': [str], 'dlc': int, 'transmitter': str}
    z_templates = {}      # hex_id -> {'sg': [str], 'val': [str], 'max_bit': int}
    alias_map = defaultdict(list) # target_hex_id -> [source_hex_id]
    message_order = [] # Preserve order from YAML where possible

    # --- Pass 1: Parse definitions and identify aliases ---
    print("Parsing definitions and aliases...")
    for msg_id_hex, msg_data in spec.items():
        msg_id_hex_str = str(msg_id_hex)
        message_order.append(msg_id_hex_str)

        if not isinstance(msg_data, dict) or 'name' not in msg_data:
            # print(f"Skipping non-message entry: {msg_id_hex_str}")
            continue # Skip API_VERSION etc.

        msg_name = sanitize_name(msg_data['name'])
        is_template = msg_id_hex_str.startswith('Z')
        has_params = 'parameters' in msg_data and isinstance(msg_data['parameters'], list) and msg_data['parameters']
        alias_target = msg_data.get('alias')

        if alias_target:
            alias_map[str(alias_target)].append(msg_id_hex_str)

        if has_params:
            signals = []
            value_tables = []
            max_bit_pos = -1

            for param in msg_data['parameters']:
                if not isinstance(param, dict) or 'name' not in param or 'byte' not in param:
                     print(f"Warning: Skipping invalid parameter in {msg_id_hex_str}: {param}", file=sys.stderr)
                     continue

                param_name_orig = param['name']
                param_name = sanitize_name(param_name_orig)
                byte_info = param.get('byte')
                bit_info = param.get('bit')
                param_type = param.get('type')
                unit = param.get('unit', "")

                # Handle reserved names to avoid conflicts
                if param_name.lower().startswith("reserved"):
                    # Try to make unique using byte/bit info
                    try:
                        start_b, _ = calculate_start_bit_length(byte_info, bit_info)
                        param_name = f"reserved_{start_b}"
                    except ValueError:
                        param_name = f"reserved_{len(signals)}" # Fallback

                try:
                    start_bit, length = calculate_start_bit_length(byte_info, bit_info)
                except ValueError as e:
                    print(f"Warning: Skipping parameter '{param_name_orig}' in {msg_id_hex_str} due to invalid byte/bit: {e}", file=sys.stderr)
                    continue

                current_max_bit = start_bit + length - 1
                max_bit_pos = max(max_bit_pos, current_max_bit)

                factor_str, offset_str, signed = get_scaling_offset_signed(param_name, param_type, unit) # Get formatted strings
                signed_char = "-" if signed else "+"
                unit_str_quoted = f'"{unit}"' if unit else '""'

                # Calculate min/max based on bits and signedness if possible
                if length <= 64: # Avoid calculating for excessively large bit lengths
                    try: # Add try-except for potential float conversion errors
                        factor_float = float(factor_str)
                        offset_float = float(offset_str)
                        if signed:
                            raw_max = (1 << (length - 1)) - 1
                            raw_min = -(1 << (length - 1))
                        else:
                            raw_max = (1 << length) - 1
                            raw_min = 0
                        # Apply scaling
                        phys_min = raw_min * factor_float + offset_float
                        phys_max = raw_max * factor_float + offset_float
                        # Format min/max nicely
                        min_max_str = f"[{phys_min:.10g}|{phys_max:.10g}]"
                    except ValueError:
                         min_max_str = "[0|0]" # Default if conversion fails
                else:
                    min_max_str = "[0|0]" # Default if too large

                # CORRECTED SG_ line formatting: Use factor_str and offset_str explicitly
                sg_line = f' SG_ {param_name} : {start_bit}|{length}@0{signed_char} ({factor_str},{offset_str}) {min_max_str} {unit_str_quoted} {DEFAULT_RECEIVER}'
                signals.append(sg_line)

                # Generate VAL_ table if values exist
                if 'values' in param:
                    try:
                        msg_id_dec_int = int(msg_id_hex_str, 16) # Need decimal ID for VAL_
                        val_line = generate_val_table_line(msg_id_dec_int, param_name, param.get('values'))
                        if val_line:
                            value_tables.append(val_line)
                    except ValueError:
                         # This happens for Z templates, handle VAL generation later
                         if not is_template:
                              print(f"Warning: Could not parse message ID {msg_id_hex_str} for VAL table.", file=sys.stderr)
                    except Exception as e:
                         print(f"Warning: Error generating VAL table for {param_name} in {msg_id_hex_str}: {e}", file=sys.stderr)


            # Store parsed data
            if is_template:
                z_templates[msg_id_hex_str] = {
                    'sg': signals,
                    'val_defs': value_tables, # Store definitions, ID needs adjustment later
                    'max_bit': max_bit_pos
                }
            else:
                try:
                    msg_id_dec = int(msg_id_hex_str, 16)
                    dlc = math.ceil((max_bit_pos + 1) / 8) if max_bit_pos >= 0 else 1 # Default DLC 1 if no signals
                    dlc = min(dlc, 8) # Max DLC is 8
                    transmitter = DEFAULT_TRANSMITTER # Could be customized later if needed
                    bo_line = f"BO_ {msg_id_dec} {msg_name}: {dlc} {transmitter}"

                    processed_messages[msg_id_hex_str] = {
                        'bo': bo_line,
                        'sg': signals,
                        'val': value_tables, # VAL lines already have correct ID here
                        'dlc': dlc,
                        'transmitter': transmitter
                    }
                except ValueError:
                    print(f"Warning: Skipping message {msg_id_hex_str} due to invalid ID.", file=sys.stderr)

    # --- Pass 2: Generate DBC lines, handling aliases ---
    print("Generating DBC output...")
    added_msgs = set() # Track which messages have been added to avoid duplicates

    for msg_id_hex_str in message_order:
        if msg_id_hex_str in added_msgs or msg_id_hex_str.startswith('Z'):
            continue # Skip templates and already processed messages

        msg_data = spec.get(msg_id_hex_str)
        if not isinstance(msg_data, dict) or 'name' not in msg_data:
            continue # Skip non-message entries

        msg_name = sanitize_name(msg_data['name'])
        alias_target_hex = str(msg_data.get('alias')) if msg_data.get('alias') else None
        has_own_params = msg_id_hex_str in processed_messages

        definition_to_use = None
        is_direct_alias = False

        if has_own_params:
            definition_to_use = processed_messages[msg_id_hex_str]
        elif alias_target_hex:
            is_direct_alias = True
            # Find the definition from the target (either another message or a Z template)
            if alias_target_hex in processed_messages:
                definition_to_use = processed_messages[alias_target_hex]
            elif alias_target_hex in z_templates:
                 # Use template definition
                 template_def = z_templates[alias_target_hex]
                 # Calculate DLC for this specific alias instance based on template signals
                 max_bit_pos = template_def['max_bit']
                 dlc = math.ceil((max_bit_pos + 1) / 8) if max_bit_pos >= 0 else 1
                 dlc = min(dlc, 8)
                 definition_to_use = {
                     'sg': template_def['sg'],
                     'val_defs': template_def.get('val_defs', []), # Template VAL defs need ID adjustment later
                     'dlc': dlc,
                     'transmitter': DEFAULT_TRANSMITTER # Assume default for aliases of templates
                 }
            else:
                print(f"Warning: Alias target '{alias_target_hex}' for message '{msg_id_hex_str}' not found.", file=sys.stderr)
                continue
        else:
             # Message with no params and no alias - create empty BO
             try:
                 msg_id_dec = int(msg_id_hex_str, 16)
                 # Add a placeholder signal to ensure DLC > 0 if needed by tools
                 placeholder_sg = f' SG_ placeholder_{msg_id_dec} : 0|1@0+ (1,0) [0|0] "" {DEFAULT_RECEIVER}'
                 bo_line = f"BO_ {msg_id_dec} {msg_name}: 1 {DEFAULT_TRANSMITTER}"
                 dbc_lines.append(bo_line)
                 dbc_lines.append(placeholder_sg)
                 dbc_lines.append("")
                 added_msgs.add(msg_id_hex_str)
                 print(f"  Added empty message: {msg_id_hex_str} ({msg_name})")
             except ValueError:
                 print(f"Warning: Skipping message {msg_id_hex_str} due to invalid ID.", file=sys.stderr)
             continue # Move to next message


        # Add the primary message (or the alias itself if it was the entry point)
        if definition_to_use:
            try:
                current_msg_id_dec = int(msg_id_hex_str, 16)
                # Generate BO line for the current message ID
                bo_line = f"BO_ {current_msg_id_dec} {msg_name}: {definition_to_use['dlc']} {definition_to_use['transmitter']}"
                dbc_lines.append(bo_line)
                dbc_lines.extend(definition_to_use['sg'])
                dbc_lines.append("")
                added_msgs.add(msg_id_hex_str)
                print(f"  Added message: {msg_id_hex_str} ({msg_name})")

                # Add VAL tables, adjusting ID if from a template
                final_val_lines = []
                if is_direct_alias and alias_target_hex.startswith('Z'):
                    # Adjust VAL table IDs from template
                    for val_def_line in definition_to_use.get('val_defs', []):
                         parts = val_def_line.split(" ", 2) # VAL_ {id} {rest}
                         if len(parts) == 3:
                             # Reconstruct with current message's decimal ID
                             adjusted_val_line = f"VAL_ {current_msg_id_dec} {parts[2]}"
                             final_val_lines.append(adjusted_val_line)
                elif 'val' in definition_to_use: # Use pre-generated VAL for non-template messages
                    final_val_lines.extend(definition_to_use['val'])

                if final_val_lines:
                    dbc_lines.extend(final_val_lines)
                    dbc_lines.append("")

            except ValueError:
                 print(f"Warning: Skipping message {msg_id_hex_str} due to invalid ID.", file=sys.stderr)
                 continue

            # --- Handle other messages that alias THIS definition ---
            # Find the original definition ID (could be msg_id_hex_str or its alias target)
            original_def_id = alias_target_hex if is_direct_alias else msg_id_hex_str

            if original_def_id in alias_map:
                for alias_source_hex in alias_map[original_def_id]:
                    if alias_source_hex == msg_id_hex_str: continue # Don't re-add the one we just did
                    if alias_source_hex in added_msgs: continue # Skip if already processed

                    alias_msg_data = spec.get(alias_source_hex)
                    if not alias_msg_data or 'name' not in alias_msg_data: continue

                    alias_msg_name = sanitize_name(alias_msg_data['name'])
                    try:
                        alias_msg_id_dec = int(alias_source_hex, 16)
                        # Create BO line for the alias using the original definition's DLC/Transmitter
                        alias_bo_line = f"BO_ {alias_msg_id_dec} {alias_msg_name}: {definition_to_use['dlc']} {definition_to_use['transmitter']}"
                        dbc_lines.append(alias_bo_line)
                        dbc_lines.extend(definition_to_use['sg']) # Copy signals
                        dbc_lines.append("")
                        added_msgs.add(alias_source_hex)
                        print(f"    Added alias: {alias_source_hex} ({alias_msg_name}) -> {original_def_id}")

                        # Add VAL tables, adjusting ID
                        alias_val_lines = []
                        val_source = definition_to_use.get('val_defs', []) if original_def_id.startswith('Z') else definition_to_use.get('val', [])
                        for val_def_line in val_source:
                             parts = val_def_line.split(" ", 2)
                             if len(parts) == 3:
                                 adjusted_val_line = f"VAL_ {alias_msg_id_dec} {parts[2]}"
                                 alias_val_lines.append(adjusted_val_line)

                        if alias_val_lines:
                            dbc_lines.extend(alias_val_lines)
                            dbc_lines.append("")

                    except ValueError:
                        print(f"Warning: Skipping alias message {alias_source_hex} due to invalid ID.", file=sys.stderr)
                    except Exception as e:
                         print(f"Warning: Error processing alias {alias_source_hex}: {e}", file=sys.stderr)


    # --- Write DBC file ---
    print(f"\nWriting DBC output to: {DBC_FILE}")
    try:
        with open(DBC_FILE, 'w') as f:
            f.write("\n".join(dbc_lines))
        print("DBC file generated successfully.")
    except IOError as e:
        print(f"Error writing DBC file {DBC_FILE}: {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"An unexpected error occurred writing {DBC_FILE}: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
