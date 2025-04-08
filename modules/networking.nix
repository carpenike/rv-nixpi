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
}
