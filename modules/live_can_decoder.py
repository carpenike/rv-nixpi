import argparse
import can
import cantools

parser = argparse.ArgumentParser(description="Live CAN bus decoder using DBC file.")
parser.add_argument("--interface", "-i", default="can0", help="CAN interface (e.g., can0, can1)")
parser.add_argument("--dbc", "-d", default="rvc.dbc", help="Path to DBC file")
args = parser.parse_args()

db = cantools.database.load_file(args.dbc)

bus = can.interface.Bus(channel=args.interface, interface="socketcan")

print(f"Listening on {args.interface} with DBC file '{args.dbc}'...")

try:
    while True:
        msg = bus.recv()
        if msg is None:
            continue

        print(f"ID: {msg.arbitration_id:08X}, Extended: {msg.is_extended_id}, Data: {msg.data.hex()}")

        try:
            decoded = db.decode_message(msg.arbitration_id, msg.data)
            print(f"[{msg.arbitration_id:08X}] {decoded}")
        except Exception as e:
            print(f"[{msg.arbitration_id:08X}] Raw data: {msg.data.hex()} (undecoded) -- Error={repr(e)}")

except KeyboardInterrupt:
    print("Stopping listener...")
    bus.shutdown()
    print("Stopped by user.")
