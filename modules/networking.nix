builtins.trace "SOPS placeholders available: ${builtins.toJSON (builtins.attrNames config.sops.placeholder)}" null;
{ config, pkgs, ... }:

{
  networking = {
    networkmanager.enable = false;
    wireless.iwd.enable = true;
    hostName = "nixpi";
  };

  # Declare iwd network profiles using environment.etc
  environment.etc = {
    "iwd/iot.psk".text = ''
      [Security]
      PreSharedKey=${config.sops.placeholder.IOT_WIFI_PASSWORD}

      [Settings]
      AutoConnect=true
    '';

    "iwd/rvproblems-2ghz.psk".text = ''
      [Security]
      PreSharedKey=${config.sops.placeholder.RVPROBLEMS_WIFI_PASSWORD}

      [Settings]
      AutoConnect=true
    '';
  };
}
