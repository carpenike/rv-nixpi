import json
import threading
import curses
import time
import sys
import base64
from collections import defaultdict
import can

# Load definitions
with open('/etc/nixos/files/rvc.json') as f:
    specs = json.load(f)['messages']

# Build decoder map
def build_decoder_map(specs):
    return {entry['id']: entry for entry in specs}

# Helper to extract bits from data
def get_bits(data_bytes, start_bit, length):
    raw_int = int.from_bytes(data_bytes, byteorder='little')
    mask = (1 << length) - 1
    return (raw_int >> start_bit) & mask

# Decode signals per spec entry
def decode_payload(entry, data_bytes):
    decoded = {}
    for sig in entry['signals']:
        raw = get_bits(data_bytes, sig['start_bit'], sig['length'])
        val = raw * sig.get('scale', 1) + sig.get('offset', 0)
        unit = sig.get('unit') or ''
        if sig.get('scale', 1) != 1 or sig.get('offset', 0) != 0:
            formatted = f"{val:.2f}{unit}"
        else:
            formatted = f"{int(val)}{unit}"
        decoded[sig['name']] = formatted
    return decoded

# OSC52 copy to clipboard
def copy_to_clipboard(text):
    payload = base64.b64encode(text.encode()).decode()
    sys.stdout.write(f"\x1b]52;c;{payload}\x07")
    sys.stdout.flush()

# Global state
decoder_map = build_decoder_map(specs)
latest_records = {'can0': {}, 'can1': {}}
stop_event = threading.Event()
copy_msg = None
copy_time = 0
interfaces = ['can0', 'can1']
sort_labels = ['A→Z', 'Newest', 'Oldest']

# Reader thread

def reader_thread(interface):
    bus = can.interface.Bus(channel=interface, interface='socketcan')
    while not stop_event.is_set():
        msg = bus.recv(1)
        if not msg:
            continue
        entry = decoder_map.get(msg.arbitration_id)
        if not entry or entry['name'].startswith('UNKNOWN'):
            continue
        now = time.time()
        name = entry['name']
        rec = latest_records[interface].get(name, {})
        rec.setdefault('first_received', now)
        rec['last_received'] = now
        rec.update({
            'raw_id': f"0x{msg.arbitration_id:08X}",
            'raw_data': msg.data.hex().upper(),
            'decoded': decode_payload(entry, msg.data),
            'spec': entry
        })
        latest_records[interface][name] = rec

# Main UI drawing

def draw_screen(stdscr):
    global copy_msg, copy_time
    curses.curs_set(0)
    curses.start_color()
    curses.use_default_colors()
    curses.init_pair(1, curses.COLOR_WHITE, curses.COLOR_BLUE)
    curses.init_pair(2, curses.COLOR_GREEN, -1)
    curses.init_pair(3, curses.COLOR_WHITE, -1)
    curses.init_pair(4, curses.COLOR_CYAN, -1)
    curses.init_pair(5, curses.COLOR_YELLOW, -1)

    current_tab = 0
    selected_idx = 0
    v_offset = 0
    sort_mode = 0

    while True:
        stdscr.erase()
        h, w = stdscr.getmaxyx()
        # Column widths and padding
        left_w = max(20, w // 5)
        mid_w = max(30, (w - left_w - 3) // 2)
        spec_w = w - left_w - mid_w - 3
        left_pad = 4; mid_pad = 4; spec_pad = 4
        left_cw = left_w - left_pad
        mid_start = left_w + 1 + mid_pad
        mid_cw = mid_w - mid_pad
        spec_start = left_w + mid_w + 2 + spec_pad
        spec_cw = spec_w - spec_pad
        max_rows = h - 7

        # Header bar
        stdscr.attron(curses.color_pair(1) | curses.A_BOLD)
        hdr = f"[1] CAN0  [2] CAN1  [S] Sort:{sort_labels[sort_mode]}  [C] Copy  [0/Q] Quit"
        stdscr.addnstr(0, 0, hdr.ljust(w), w)
        stdscr.attroff(curses.color_pair(1) | curses.A_BOLD)
        stdscr.hline(1, 0, '-', w)
        # Column titles
        stdscr.addnstr(2, left_pad, 'Name'.center(left_cw), left_cw, curses.A_BOLD)
        stdscr.addnstr(2, mid_start, 'Raw & Decoded'.center(mid_cw), mid_cw, curses.A_BOLD)
        stdscr.addnstr(2, spec_start, 'Spec JSON'.center(spec_cw), spec_cw, curses.A_BOLD)
        stdscr.hline(3, 0, '-', w)
        for y in range(2, h-1):
            stdscr.addch(y, left_w, '|')
            stdscr.addch(y, left_w + mid_w + 1, '|')

        # Prepare sorted list
        iface = interfaces[current_tab]
        recs = latest_records[iface]
        names = []
        if sort_mode == 0:
            names = sorted(recs.keys())
        elif sort_mode == 1:
            names = sorted(recs.keys(), key=lambda n: recs[n]['last_received'], reverse=True)
        else:
            names = sorted(recs.keys(), key=lambda n: recs[n]['first_received'])
        total = len(names)
        if total:
            selected_idx = max(0, min(selected_idx, total-1))
            if selected_idx < v_offset:
                v_offset = selected_idx
            elif selected_idx >= v_offset + max_rows:
                v_offset = selected_idx - max_rows + 1
        else:
            selected_idx = v_offset = 0

        # Left pane: names
        for idx in range(v_offset, min(v_offset+max_rows, total)):
            row = 4 + idx - v_offset
            name = names[idx]
            attr = curses.color_pair(2) | curses.A_BOLD if idx == selected_idx else curses.color_pair(3)
            stdscr.addnstr(row, left_pad, name.ljust(left_cw), left_cw, attr)

        # Right panes: raw/decoded + spec
        if total:
            rec = recs[names[selected_idx]]
            # Raw ID & data
            stdscr.addnstr(4, mid_start, f"ID  : {rec['raw_id']}".ljust(mid_cw), mid_cw, curses.color_pair(4)|curses.A_BOLD)
            stdscr.addnstr(5, mid_start, f"Data: {rec['raw_data']}".ljust(mid_cw), mid_cw, curses.color_pair(4)|curses.A_BOLD)
            # Decoded signals
            for i, (s, v) in enumerate(rec['decoded'].items()):
                row = 7 + i
                if row < h-2:
                    stdscr.addnstr(row, mid_start, f"{s}: {v}".ljust(mid_cw), mid_cw)
            # Full spec JSON
            spec_lines = json.dumps(rec['spec'], indent=2).splitlines()
            for i, ln in enumerate(spec_lines):
                row = 4 + i
                if row < h-2:
                    stdscr.addnstr(row, spec_start, ln.ljust(spec_cw), spec_cw)

        # Copy notification
        if copy_msg and time.time() - copy_time < 2:
            stdscr.addnstr(h-2, 0, copy_msg[:w-1].ljust(w-1), w-1, curses.color_pair(5)|curses.A_BOLD)

        # Footer
        footer = "Arrows:Navigate  S:Sort  C:Copy  1/2:Switch  0/Q:Quit"
        stdscr.addnstr(h-1, 0, footer[:w-1], w-1)
        stdscr.refresh()

        # Input
        c = stdscr.getch()
        if c in (ord('q'), ord('0')):
            stop_event.set(); break
        if c == ord('1'):
            current_tab, selected_idx, v_offset = 0, 0, 0
        elif c == ord('2'):
            current_tab, selected_idx, v_offset = 1, 0, 0
        elif c == ord('s') and total:
            prev = names[selected_idx]
            sort_mode = (sort_mode+1) % 3
            selected_idx = names.index(prev)
            v_offset = 0
        elif c == curses.KEY_DOWN and total:
            selected_idx = min(selected_idx+1, total-1)
        elif c == curses.KEY_UP and total:
            selected_idx = max(selected_idx-1, 0)
        elif c == ord('c') and total:
            txt = json.dumps(latest_records[iface][names[selected_idx]]['spec'], indent=2)
            copy_to_clipboard(txt)
            copy_msg = "Spec copied to clipboard"
            copy_time = time.time()

# Entry point
if __name__ == '__main__':
    for iface in interfaces:
        threading.Thread(target=reader_thread, args=(iface,), daemon=True).start()
    curses.wrapper(draw_screen)
