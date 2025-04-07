{ config, lib, ... }:
{
  networking = {
    wireless.enable = true;
    wireless.networks = {
      "iot" = {
        pskFile = config.sops.secrets.iot_psk.path;
      };
      "rvproblems-2ghz" = {
        pskFile = config.sops.secrets.rvproblems_2ghz_psk.path;
      };
    };
    useDHCP = true;
    hostName = "nixpi";
  };
}
