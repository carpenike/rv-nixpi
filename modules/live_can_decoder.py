import argparse
import can
import cantools

# Parse command-line arguments
parser = argparse.ArgumentParser(description="Live CAN bus decoder using DBC file.")
parser.add_argument("--interface", "-i", default="can0", help="CAN interface (e.g., can0, can1)")
parser.add_argument("--dbc", "-d", default="rvc.dbc", help="Path to DBC file")
args = parser.parse_args()

# Load the DBC file
db = cantools.database.load_file(args.dbc)

# Set up the CAN interface
bus = can.interface.Bus(channel=args.interface, interface="socketcan")

print(f"Listening on {args.interface} with DBC file '{args.dbc}'...")

try:
    while True:
        msg = bus.recv()
        if msg is None:
            continue

        print(f"ID: {msg.arbitration_id:08X}, Extended: {msg.is_extended_id}, Data: {msg.data.hex()}")

        try:
            # Apply extended ID fix
            frame_id = msg.arbitration_id
            if msg.is_extended_id:
                frame_id |= 0x80000000

            decoded = db.decode_message(frame_id, msg.data)
            print(f"[{msg.arbitration_id:08X}] {decoded}")
        except Exception:
            print(f"[{msg.arbitration_id:08X}] Raw data: {msg.data.hex()} (undecoded)")
except KeyboardInterrupt:
    print("Stopping listener...")
    bus.shutdown()
    print("Stopped by user.")
