{ config, pkgs, lib, ... }:
let
  wifiSecrets = config.sops.secrets or {};
in {
  networking = {
    wireless.enable = true;
    wireless.networks = {
      "rvproblems-2ghz" = lib.optionalAttrs (wifiSecrets.rvproblems-2ghz != null) {
        psk = wifiSecrets.RV_WIFI.psk;
      };
      "iot" = lib.optionalAttrs (wifiSecrets.iot != null) {
        psk = wifiSecrets.Backup_WIFI.psk;
      };
    };
    useDHCP = true;
    hostName = "nixpi";
  };
}
