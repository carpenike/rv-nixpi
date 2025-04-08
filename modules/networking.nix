{ config, pkgs, ... }:

{
  networking = {
    networkmanager = {
      enable = true;

      ensureProfiles = {
        environmentFiles = [
          "/run/secrets/IOT_WIFI_SSID"
          "/run/secrets/IOT_WIFI_PASSWORD"
          "/run/secrets/RVPROBLEMS_WIFI_SSID"
          "/run/secrets/RVPROBLEMS_WIFI_PASSWORD"
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

  system.activationScripts.network-secrets = ''
    mkdir -p /run/secrets
    ${pkgs.coreutils}/bin/ln -sfn "${config.sops.secretsDir}/IOT_WIFI_SSID" "/run/secrets/IOT_WIFI_SSID"
    ${pkgs.coreutils}/bin/ln -sfn "${config.sops.secretsDir}/IOT_WIFI_PASSWORD" "/run/secrets/IOT_WIFI_PASSWORD"
    ${pkgs.coreutils}/bin/ln -sfn "${config.sops.secretsDir}/RVPROBLEMS_WIFI_SSID" "/run/secrets/RVPROBLEMS_WIFI_SSID"
    ${pkgs.coreutils}/bin/ln -sfn "${config.sops.secretsDir}/RVPROBLEMS_WIFI_PASSWORD" "/run/secrets/RVPROBLEMS_WIFI_PASSWORD"
  '';

  systemd.services.NetworkManager = {
    wants = ["sops-nix.service"];
    after = ["sops-nix.service"];
  };
}
