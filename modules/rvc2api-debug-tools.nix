{ config, pkgs, lib, ... }:

let
  pythonEnv = pkgs.python3.withPackages (ps: with ps; [
    python-can
    cantools
  ]);
in {
  options.services.rvc2api.debugTools.enable =
    lib.mkEnableOption "Enable RVC CANbus JSON debugging tools";

  config = lib.mkIf config.services.rvc2api.debugTools.enable {
    environment.systemPackages = [
      pythonEnv
      pkgs.jq
      # live‐CAN tester, now JSON‐based
      (pkgs.writeShellScriptBin "rvc-can-test" ''
        #!/usr/bin/env bash
        set -euo pipefail

        # Set default CAN interface if provided, else can0
        if [ $# -ge 1 ]; then
          INTERFACE="$1"
        else
          INTERFACE="can0"
        fi

        # Set default JSON defs path if provided, else /etc/nixos/files/rvc.json
        if [ $# -ge 2 ]; then
          JSON_PATH="$2"
        else
          JSON_PATH="/etc/nixos/files/rvc.json"
        fi

        SCRIPT="/etc/nixos/files/live_can_decoder.py"

        if [ ! -f "$JSON_PATH" ]; then
          echo "❌ JSON file not found at $JSON_PATH"
          exit 1
        fi

        if [ ! -f "$SCRIPT" ]; then
          echo "❌ Python script not found at $SCRIPT"
          exit 1
        fi

        echo "▶️ Running decoder on interface $INTERFACE with JSON defs $JSON_PATH"
        "${pythonEnv}/bin/python" "$SCRIPT" \
          --interface "$INTERFACE" \
          --json "$JSON_PATH"
      '')

      # JSON syntax validator
      (pkgs.writeShellScriptBin "rvc-json-validate" ''
        #!/usr/bin/env bash
        set -euo pipefail

        # Set default JSON path if provided, else /etc/nixos/files/rvc.json
        if [ $# -ge 1 ]; then
          JSON_PATH="$1"
        else
          JSON_PATH="/etc/nixos/files/rvc.json"
        fi

        if [ ! -f "$JSON_PATH" ]; then
          echo "❌ JSON file not found at $JSON_PATH"
          exit 1
        fi

        echo "🔍 Validating JSON syntax in $JSON_PATH"
        if jq empty "$JSON_PATH"; then
          echo "✅ JSON syntax is valid."
        else
          echo "❌ JSON syntax error in $JSON_PATH"
          exit 1
        fi
      '')
    ];

    # Deploy your decoder and JSON defs into /etc/nixos/files
    environment.etc."nixos/files/live_can_decoder.py".source = ./live_can_decoder.py;
    environment.etc."nixos/files/rvc.json".source          = ../docs/rvc.json;
  };
}
