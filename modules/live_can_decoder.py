#!/usr/bin/env python3
import argparse
import json
import can
import sys

def extract_raw_value(data_int, start_bit, bit_length):
    """Grab a little‐endian bitfield out of data_int."""
    mask = (1 << bit_length) - 1
    return (data_int >> start_bit) & mask

def decode_message(msg, msg_defs):
    """If we know this ID, extract all its signals. Return dict or None."""
    d = msg_defs.get(msg.arbitration_id)
    if not d:
        return None
    raw = int.from_bytes(msg.data, byteorder="little")
    out = {}
    for sig in d["signals"]:
        val = extract_raw_value(raw, sig["start_bit"], sig["length"])
        if "scale" in sig:
            val = val * sig["scale"]
        if "offset" in sig:
            val = val + sig["offset"]
        out[sig["name"]] = val
    return out

def main():
    p = argparse.ArgumentParser(description="Live CAN → JSON “DBC” decoder")
    p.add_argument("-i", "--interface", default="can0",
                   help="socketcan interface (e.g. can0)")
    p.add_argument("-j", "--json", default="rvc.json",
                   help="path to JSON message definition")
    args = p.parse_args()

    # load your JSON defs
    try:
        with open(args.json) as f:
            jd = json.load(f)
    except Exception as e:
        print(f"❌ failed to load JSON file '{args.json}': {e}", file=sys.stderr)
        sys.exit(1)

    msg_defs = { msg["id"]: msg for msg in jd["messages"] }

    bus = can.interface.Bus(channel=args.interface, interface="socketcan")
    print(f"🛰  Listening on {args.interface}, defs from '{args.json}'…")

    try:
        while True:
            msg = bus.recv()
            if msg is None:
                continue

            arb = msg.arbitration_id
            raw = msg.data.hex()
            msg_def = msg_defs.get(arb)

            if msg_def is None:
                # completely unknown ID
                print(f"ID: {arb:08X}  ext={msg.is_extended_id}  data={raw}")
                print(f"[{arb:08X}]  Unknown ID (no definition in JSON)")
                continue

            decoded = decode_message(msg, msg_defs)
            if decoded is None:
                # definition existed but decode_message refused
                print(f"ID: {arb:08X}  ext={msg.is_extended_id}  data={raw}")
                print(f"[{arb:08X}]  Definition found but failed to decode")
            # else: we know it and decoded it successfully, so stay silent

    except KeyboardInterrupt:
        print("\nStopping listener…")
        bus.shutdown()

if __name__ == "__main__":
    main()
