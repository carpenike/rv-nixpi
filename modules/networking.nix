{ config, pkgs, lib, ... }:
let
  wifiSecrets = config.sops.secrets or {};
in {
  networking = {
    wireless.enable = true;
    wireless.networks = {
      "iot" = {
        psk = builtins.readFile config.sops.secrets.iot_psk.path;
      };
      "rvproblems-2ghz" = {
        psk = builtins.readFile config.sops.secrets.rvproblems_2ghz_psk.path;
      };
    };
    useDHCP = true;
    hostName = "nixpi";
  };
}
