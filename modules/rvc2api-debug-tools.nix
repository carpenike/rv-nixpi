{ config, pkgs, lib, ... }:

let
  pythonEnv = pkgs.python3.withPackages (ps: with ps; [
    python-can
    cantools
  ]);
in {
  options = {
    services.rvc2api.debugTools.enable = lib.mkEnableOption "Enable RVC CANbus DBC debugging tools";
  };

  config = lib.mkIf config.services.rvc2api.debugTools.enable {
    environment.systemPackages = [
      pythonEnv

      (pkgs.writeShellScriptBin "rvc-dbc-test" ''
        #!/usr/bin/env bash
        set -euo pipefail

        INTERFACE=''${1:-can0}
        DBC_PATH="/etc/nixos/files/rvc.dbc"
        SCRIPT="/etc/nixos/files/live_can_decoder.py"

        if [ ! -f "$DBC_PATH" ]; then
          echo "❌ DBC file not found at $DBC_PATH"
          exit 1
        fi

        if [ ! -f "$SCRIPT" ]; then
          echo "❌ Python script not found at $SCRIPT"
          exit 1
        fi

        echo "▶️ Running decoder on interface $INTERFACE"
        "${pythonEnv}/bin/python" "$SCRIPT" --interface "$INTERFACE" --dbc "$DBC_PATH"
      '')

      (pkgs.writeShellScriptBin "rvc-dbc-validate" ''
        #!/usr/bin/env bash
        set -euo pipefail

        # Set default DBC path if no argument is provided
        DBC_PATH="$1"
        if [ -z "$DBC_PATH" ]; then
          DBC_PATH="/etc/nixos/files/rvc.dbc"
        fi

        if [ ! -f "$DBC_PATH" ]; then
          echo "❌ DBC file not found at $DBC_PATH"
          exit 1
        fi

        echo "🔍 Validating DBC file: $DBC_PATH"
        # Use Nix interpolation for the Python environment path
        "${pythonEnv}/bin/cantools" dump "$DBC_PATH"
        echo "✅ DBC file is valid."
      '')
    ];

    # Deploy the helper script and DBC file
    environment.etc."nixos/files/live_can_decoder.py".source = ./live_can_decoder.py;
    environment.etc."nixos/files/rvc.dbc".source = ../docs/rvc.dbc;
  };
}
