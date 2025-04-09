{ config, pkgs, lib, ... }:

{
  networking = {
    networkmanager.enable = false;
    wireless.iwd.enable = true;
    hostName = "nixpi";

    wireless.iwd.settings = {
      General = {
        EnableNetworkConfiguration = true;
      };
      DriverQuirks = {
        DefaultInterface = "wlan0";
      };
    };
  };

  systemd.tmpfiles.rules = [
    "C /var/lib/iwd/iot.psk 0600 root root - ${config.sops.secrets.IOT_WIFI_PASSWORD.path}"
    "C /var/lib/iwd/rvproblems-2ghz.psk 0600 root root - ${config.sops.secrets.RVPROBLEMS_WIFI_PASSWORD.path}"
  ];

  systemd.services.iwd.serviceConfig = {
    Restart = "on-failure";
    RestartSec = 2;
  };
}
