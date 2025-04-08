{ config, pkgs, ... }:

{
  networking = {
    networkmanager.enable = false;
    wireless.iwd.enable = true;
    hostName = "nixpi";
  };

  # Just place the decrypted full .psk content at the expected location
  environment.etc = {
    "var/lib/iwd/iot.psk".source = config.sops.secrets.IOT_WIFI_PASSWORD.path;
    "var/lib/iwd/rvproblems-2ghz.psk".source = config.sops.secrets.RVPROBLEMS_WIFI_PASSWORD.path;
  };
}
