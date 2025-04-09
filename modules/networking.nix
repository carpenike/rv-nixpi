{ config, pkgs, lib, ... }:

{
  networking = {
    networkmanager.enable = false;
    wireless.iwd.enable = true;
    hostName = "nixpi";
  };

  systemd.tmpfiles.rules = [
    "C /var/lib/iwd/iot.psk 0600 root root - ${config.sops.secrets.IOT_WIFI_PASSWORD.path}"
    "C /var/lib/iwd/rvproblems-2ghz.psk 0600 root root - ${config.sops.secrets.RVPROBLEMS_WIFI_PASSWORD.path}"
  ];

  environment.etc."iwd/main.conf".text = ''
    [General]
    EnableNetworkConfiguration=true

    [DriverQuirks]
    DefaultInterface=wlan0
  '';

  systemd.services.iwd.serviceConfig = {
    Restart = "on-failure";
    RestartSec = 2;
  };
}
