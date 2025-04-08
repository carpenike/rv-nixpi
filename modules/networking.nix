{ config, pkgs, ... }:

let
  # Helper to create formatted env files from secrets
  mkSecretEnv = name: secret: {
    content = "${name}=${config.sops.placeholder.${secret}}";
    path = "/run/NetworkManager-secrets/${name}";
    mode = "0400";
  };
in {
  networking = {
    networkmanager = {
      enable = true;

      ensureProfiles = {
        environmentFiles = [
          config.sops.templates.IOT_WIFI_SSID.path
          config.sops.templates.IOT_WIFI_PASSWORD.path
          config.sops.templates.RVPROBLEMS_WIFI_SSID.path
          config.sops.templates.RVPROBLEMS_WIFI_PASSWORD.path
        ];
        profiles = {
          iot = {
            connection = {
              id = "iot";
              type = "wifi";
              interface-name = "wlan0";
              permissions = "user:root:";
            };
            wifi = {
              mode = "infrastructure";
              ssid = "$IOT_WIFI_SSID";
            };
            wifi-security = {
              auth-alg = "open";
              key-mgmt = "wpa-psk";
              psk = "$IOT_WIFI_PASSWORD";
            };
            ipv4 = {
              method = "auto";
            };
            ipv6 = {
              addr-gen-mode = "stable-privacy";
              method = "auto";
            };
          };

          rvproblems = {
            connection = {
              id = "rvproblems-2ghz";
              type = "wifi";
              interface-name = "wlan0";
              permissions = "user:root:";
            };
            wifi = {
              mode = "infrastructure";
              ssid = "$RVPROBLEMS_WIFI_SSID";
            };
            wifi-security = {
              auth-alg = "open";
              key-mgmt = "wpa-psk";
              psk = "$RVPROBLEMS_WIFI_PASSWORD";
            };
            ipv4 = {
              method = "auto";
            };
            ipv6 = {
              addr-gen-mode = "stable-privacy";
              method = "auto";
            };
          };
        };
      };
    };

    hostName = "nixpi";
  };

  sops.templates = {
    IOT_WIFI_SSID = mkSecretEnv "IOT_WIFI_SSID" "IOT_WIFI_SSID";
    IOT_WIFI_PASSWORD = mkSecretEnv "IOT_WIFI_PASSWORD" "IOT_WIFI_PASSWORD";
    RVPROBLEMS_WIFI_SSID = mkSecretEnv "RVPROBLEMS_WIFI_SSID" "RVPROBLEMS_WIFI_SSID";
    RVPROBLEMS_WIFI_PASSWORD = mkSecretEnv "RVPROBLEMS_WIFI_PASSWORD" "RVPROBLEMS_WIFI_PASSWORD";
  };

  systemd.tmpfiles.rules = [
    "d /run/NetworkManager-secrets 0750 root keys -"
  ];

  systemd.services.NetworkManager = {
    wants = ["sops-nix.service"];
    after = ["sops-nix.service"];
    # Add explicit requirement
    # requires = ["NetworkManager-ensure-profiles.service"];
  };

  # Add ordering for profile generation
  systemd.services.NetworkManager-ensure-profiles = {
    after = ["sops-nix.service"];
    requires = ["sops-nix.service"];
    serviceConfig = {
      ExecStartPre = pkgs.writeShellScript "check-secrets" ''
        [ -f ${config.sops.templates.IOT_WIFI_SSID.path} ] || exit 1
      '';
    };
  };
}
