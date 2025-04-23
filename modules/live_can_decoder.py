import argparse
import can
import cantools

# Parse command-line arguments
parser = argparse.ArgumentParser(description="Live CAN bus decoder using DBC file.")
parser.add_argument("--interface", "-i", default="can0", help="CAN interface (e.g., can0, can1)")
parser.add_argument("--dbc", "-d", default="generated_rvc.dbc", help="Path to DBC file")
args = parser.parse_args()

# Load the DBC file
db = cantools.database.load_file(args.dbc)

# Set up the CAN interface
# Use 'interface' instead of deprecated 'bustype'
bus = can.interface.Bus(channel=args.interface, interface="socketcan")

print(f"Listening on {args.interface} with DBC file '{args.dbc}'...")

try:
    while True:
        msg = bus.recv()
        if msg is None:
            continue
        try:
            decoded = db.decode_message(msg.arbitration_id, msg.data)
            print(f"[{msg.arbitration_id:03X}] {decoded}")
        except Exception:
            print(f"[{msg.arbitration_id:03X}] Raw data: {msg.data.hex()} (undecoded)")
except KeyboardInterrupt:
    print("Stopping listener...")
    bus.shutdown() # Properly close the CAN bus connection
    print("Stopped by user.")
