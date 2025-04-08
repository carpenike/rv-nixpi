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
              interface-name = "wlan0";
              permissions = "user:root:";
              autoconnect = true;
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

  # This is optional now; you *could* remove it too
  # systemd.services.NetworkManager-ensure-profiles = {
  #   description = "Ensure NetworkManager Wi-Fi profiles are created from SOPS secrets";
  #   wantedBy = [ "multi-user.target" ];
  #   before = [ "NetworkManager.service" ];
  #   after = [ "network.target" ];
  #   serviceConfig = {
  #     Type = "oneshot";
  #     ExecStart = pkgs.writeShellScript "ensure-profiles" ''
  #       echo "Checking for Wi-Fi profile secrets..."
  #       test -f ${config.sops.secrets.IOT_WIFI_SSID.path} || (echo "Missing IOT_WIFI_SSID secret" && exit 1)
  #       test -f ${config.sops.secrets.IOT_WIFI_PASSWORD.path} || (echo "Missing IOT_WIFI_PASSWORD secret" && exit 1)
  #       test -f ${config.sops.secrets.RVPROBLEMS_WIFI_SSID.path} || (echo "Missing RVPROBLEMS_WIFI_SSID secret" && exit 1)
  #       test -f ${config.sops.secrets.RVPROBLEMS_WIFI_PASSWORD.path} || (echo "Missing RVPROBLEMS_WIFI_PASSWORD secret" && exit 1)
  #       echo "Secrets verified. NetworkManager profiles should be applied by now."
  #     '';
  #   };
  # };
}
