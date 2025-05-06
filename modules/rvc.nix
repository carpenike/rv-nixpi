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

  # New service: HTTP/WebSocket API for CANbus
  options.services.rvc2api = {
    enable      = lib.mkEnableOption "Run the rvc2api FastAPI CANbus service";
    package     = lib.mkOption {
      type        = lib.types.package;
      description = "The Python package providing the rvc2api service";
    };
    specFile    = lib.mkOption {
      type        = lib.types.str;
      default     = "/etc/rvc2api/rvc.json";
      description = "Path to the RV‑C spec JSON";
    };
    mappingFile = lib.mkOption {
      type        = lib.types.str;
      default     = "/etc/rvc2api/device_mapping.yml";
      description = "Path to the device‑mapping YAML";
    };
    channels    = lib.mkOption {
      type        = lib.types.listOf lib.types.str;
      default     = [ "can0" "can1" ];
      description = "SocketCAN interfaces to listen on";
    };
    bustype     = lib.mkOption {
      type        = lib.types.str;
      default     = "socketcan";
      description = "python‑can bus type";
    };
    bitrate     = lib.mkOption {
      type        = lib.types.int;
      default     = 500000;
      description = "CAN bus bitrate";
    };
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
    # Deploy the API service only if enabled
    (lib.mkIf config.services.rvc2api.enable {
      # Ensure the spec & mapping live on disk
      environment.etc."rvc2api/rvc.json".source         = config.services.rvc2api.specFile;
      environment.etc."rvc2api/device_mapping.yml".source = config.services.rvc2api.mappingFile;

      # systemd unit for rvc2api
      systemd.services.rvc2api = {
        description = "RV‑C HTTP/WebSocket API";
        after       = [ "network.target" "can0.service" "can1.service" ];
        requires    = [ "can0.service" "can1.service" ];
        wantedBy    = [ "multi-user.target" ];

        serviceConfig = {
          # Run the uvicorn module using the Python interpreter from the rvc2api package
          ExecStart = lib.concatStringsSep " " [
            "${config.services.rvc2api.package}/bin/python"  # Use the package's python
            "-m" "uvicorn"                                  # Run uvicorn as a module
            "core_daemon.app:app" 
            "--host" "0.0.0.0"
          ];
          # Set environment variables for the service
          Environment = [
            "CAN_BUSTYPE=${config.services.rvc2api.bustype}"
            "CAN_CHANNELS=${lib.concatStringsSep "," config.services.rvc2api.channels}"
            "CAN_BITRATE=${toString config.services.rvc2api.bitrate}"
            "CAN_SPEC_PATH=/etc/rvc2api/rvc.json"
            "CAN_MAP_PATH=/etc/rvc2api/device_mapping.yml"
            # PYTHONPATH might not be strictly needed when using the package's python,
            # but doesn't hurt.
            "PYTHONPATH=${config.services.rvc2api.package}/${pkgs.python3.sitePackages}"
          ];
          Restart    = "always";
          RestartSec = 5;
        };
      };
    })
  ];
}
