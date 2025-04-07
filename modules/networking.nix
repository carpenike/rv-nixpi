{ config, pkgs, lib, ... }:
let
  wifiSecrets = config.sops.secrets or {};
in {
  networking = {
    wireless.enable = true;
    wireless.networks = {
      "rvproblems-2ghz" = lib.optionalAttrs (wifiSecrets.rvproblems-2ghz != null) {
        psk = wifiSecrets.rvproblems-2ghz.psk;
      };
      "iot" = lib.optionalAttrs (wifiSecrets.iot != null) {
        psk = wifiSecrets.iot.psk;
      };
    };
    useDHCP = true;
    hostName = "nixpi";
  };
}
