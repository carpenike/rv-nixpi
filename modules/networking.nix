{ config, pkgs, lib, ... }:

{
  networking = {
    networkmanager.enable = false;
    wireless.iwd.enable = true;
    hostName = "nixpi";
  };

  environment.etc = {
    "var/lib/iwd/iot.psk".text = config.sops.secrets.IOT_WIFI_PASSWORD.content;
    "var/lib/iwd/rvproblems-2ghz.psk".text = config.sops.secrets.RVPROBLEMS_WIFI_PASSWORD.content;
  };
}
