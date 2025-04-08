{ config, pkgs, ... }:

{
  networking = {
    networkmanager = {
      enable = true;

      ensureProfiles = {
        environmentFiles = [
          config.sops.secrets.IOT_WIFI_SSID.path
          config.sops.secrets.IOT_WIFI_PASSWORD.path
          config.sops.secrets.RVPROBLEMS_WIFI_SSID.path
          config.sops.secrets.RVPROBLEMS_WIFI_PASSWORD.path
        ];

        profiles = {
          iot = {
            connection = {
              id = "iot";
              type = "wifi";
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
}
