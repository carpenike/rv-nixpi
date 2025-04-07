{ config, lib, ... }:

let
  wifiSecrets = config.sops.secrets;
in {
  networking = {
    wireless.enable = true;
    wireless.networks = {
      "iot" = lib.mkIf (wifiSecrets ? iot_psk) {
        pskRaw = builtins.readFile wifiSecrets.iot_psk.path;
      };
      "rvproblems-2ghz" = lib.mkIf (wifiSecrets ? rvproblems_2ghz_psk) {
        pskRaw = builtins.readFile wifiSecrets.rvproblems_2ghz_psk.path;
      };
    };
    useDHCP = true;
    hostName = "nixpi";
  };
}
