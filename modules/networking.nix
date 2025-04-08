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
          "/run/NetworkManager-secrets/IOT_WIFI_SSID"
          "/run/NetworkManager-secrets/IOT_WIFI_PASSWORD"
          "/run/NetworkManager-secrets/RVPROBLEMS_WIFI_SSID"
          "/run/NetworkManager-secrets/RVPROBLEMS_WIFI_PASSWORD"
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

  # Replace tmpfiles rules with SOPS templates
  sops.templates = {
    IOT_WIFI_SSID = mkSecretEnv "IOT_WIFI_SSID" "IOT_WIFI_SSID";
    IOT_WIFI_PASSWORD = mkSecretEnv "IOT_WIFI_PASSWORD" "IOT_WIFI_PASSWORD";
    RVPROBLEMS_WIFI_SSID = mkSecretEnv "RVPROBLEMS_WIFI_SSID" "RVPROBLEMS_WIFI_SSID";
    RVPROBLEMS_WIFI_PASSWORD = mkSecretEnv "RVPROBLEMS_WIFI_PASSWORD" "RVPROBLEMS_WIFI_PASSWORD";
  };

  # Create directory for NM secrets
  systemd.tmpfiles.rules = [
    "d /run/NetworkManager-secrets 0700 root root -"
  ];

  # Tighten service dependencies
  systemd.services.NetworkManager = {
    wants = ["sops-nix.service"];
    after = ["sops-nix.service"];
    serviceConfig.SupplementaryGroups = [ "keys" ];
  };
}
