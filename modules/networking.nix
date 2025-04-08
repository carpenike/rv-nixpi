{ config, pkgs, ... }:

{
  networking = {
    networkmanager = {
      enable = true;

      ensureProfiles = {
        environmentFiles = [
          config.sops.secrets.wifiEnv.path
        ];
        profiles = {
          iot = {
            connection = {
              id = "iot";
              type = "wifi";
              interface-name = "wlan0";
              permissions = "user:root:";
              autoconnect = true;
              uuid = "696c69a4-f0da-4be1-a773-40363d841364";
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
            ipv4.method = "auto";
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
              autoconnect = true;
              uuid = "e356ddcb-e83c-4e28-af65-3fce873284a6";
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
            ipv4.method = "auto";
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
