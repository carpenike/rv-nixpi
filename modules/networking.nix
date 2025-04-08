{ config, pkgs, lib, ... }:

{
  networking = {
    networkmanager.enable = false;
    wireless.iwd.enable = true;
    hostName = "nixpi";
  };

  # Use tmpfiles.d to copy the decrypted secrets to the IWD runtime path
  systemd.tmpfiles.rules = [
    "f /var/lib/iwd/iot.psk 0600 root root - ${config.sops.secrets.IOT_WIFI_PASSWORD.path}"
    "f /var/lib/iwd/rvproblems-2ghz.psk 0600 root root - ${config.sops.secrets.RVPROBLEMS_WIFI_PASSWORD.path}"
  ];
}
