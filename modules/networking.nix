{ config, pkgs, ... }:
let
  _ = builtins.trace "SOPS placeholders available: ${builtins.toJSON (builtins.attrNames config.sops.placeholder)}" null;

in {
  networking = {
    networkmanager.enable = false;
    wireless.iwd.enable = true;
    hostName = "nixpi";
  };

  # Declare iwd network profiles using environment.etc
  environment.etc = {
    "iwd/iot.psk".source = config.sops.secrets.IOT_WIFI_PASSWORD.path;
    "iwd/rvproblems-2ghz.psk".source = config.sops.secrets.RVPROBLEMS_WIFI_PASSWORD.path;
  };
}
