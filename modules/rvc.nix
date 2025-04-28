{ config, pkgs, lib, ... }:

let
  # Define Python environments needed by sub-modules
  consolePythonEnv = pkgs.python3.withPackages (ps: with ps; [
    python-can
    pyyaml
  ]);

  debugPythonEnv = pkgs.python3.withPackages (ps: with ps; [
    python-can
    cantools
    pyperclip
  ]);

in
{
  options.services.rvc = {
    console.enable = lib.mkEnableOption "Enable the RVC Console application";
    debugTools.enable = lib.mkEnableOption "Enable RVC CANbus debugging tools";
  };

  config = lib.mkMerge [
    # --- Shared Config Deployment (rvc-config.nix content) ---
    (lib.mkIf (config.services.rvc.console.enable || config.services.rvc.debugTools.enable) {
      environment.etc."nixos/files/rvc.json".source = ../config/rvc/rvc.json;
      environment.etc."nixos/files/device_mapping.yaml".source = ../config/rvc/device_mapping.yml;
    })

    # --- Console Configuration (rvc-console.nix content) ---
    (lib.mkIf config.services.rvc.console.enable {
      environment.systemPackages = [
        (pkgs.writeShellScriptBin "rvc-console" ''
          #!${pkgs.runtimeShell}
          set -euo pipefail
          SCRIPT_PATH="/etc/nixos/files/rvc-console.py"
          RVC_SPEC="/etc/nixos/files/rvc.json"
          DEVICE_MAP="/etc/nixos/files/device_mapping.yaml"
          if [ ! -f "$SCRIPT_PATH" ]; then echo "Error: Console script not found at $SCRIPT_PATH" >&2; exit 1; fi
          if [ ! -f "$RVC_SPEC" ]; then echo "Warning: RVC spec not found at $RVC_SPEC." >&2; fi
          if [ ! -f "$DEVICE_MAP" ]; then echo "Warning: Device mapping not found at $DEVICE_MAP." >&2; fi
          exec "${consolePythonEnv}/bin/python" "$SCRIPT_PATH" "$@"
        '')
      ];
      environment.etc."nixos/files/rvc-console.py".source = ./rvc-console.py;
    })

    # --- Debug Tools Configuration (rvc-debug-tools.nix content) ---
    (lib.mkIf config.services.rvc.debugTools.enable {
      environment.systemPackages = [
        debugPythonEnv # Use the specific python env for debug tools
        pkgs.jq
        (pkgs.writeShellScriptBin "rvc-can-test" ''
          #!/usr/bin/env bash
          set -euo pipefail
          INTERFACE=''${1:-can0}
          JSON_PATH=''${2:-/etc/nixos/files/rvc.json}
          SCRIPT="/etc/nixos/files/live_can_decoder.py"
          if [ ! -f "$JSON_PATH" ]; then echo "❌ JSON file not found at $JSON_PATH"; exit 1; fi
          if [ ! -f "$SCRIPT" ]; then echo "❌ Python script not found at $SCRIPT"; exit 1; fi
          echo "▶️ Running decoder on interface $INTERFACE with JSON defs $JSON_PATH"
          "${debugPythonEnv}/bin/python" "$SCRIPT" --interface "$INTERFACE" --json "$JSON_PATH"
        '')
        (pkgs.writeShellScriptBin "rvc-json-validate" ''
          #!/usr/bin/env bash
          set -euo pipefail
          JSON_PATH=''${1:-/etc/nixos/files/rvc.json}
          if [ ! -f "$JSON_PATH" ]; then echo "❌ JSON file not found at $JSON_PATH"; exit 1; fi
          echo "🔍 Validating JSON syntax in $JSON_PATH"
          if jq empty "$JSON_PATH"; then echo "✅ JSON syntax is valid."; else echo "❌ JSON syntax error in $JSON_PATH"; exit 1; fi
        '')
      ];
      # Deploy the live decoder script needed by rvc-can-test
      environment.etc."nixos/files/live_can_decoder.py".source = ./live_can_decoder.py;
    })
  ];
}
