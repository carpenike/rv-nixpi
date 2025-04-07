{ config, lib, ... }:

let
  wifiSecrets = config.sops.secrets;
in {
  networking = {
    wireless.enable = true;

    # Disable the default network list
    wireless.networks = {};

    wireless.wpaSupplicantConf = ''
      ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=wheel
      update_config=1

      network={
        ssid="iot"
        psk="${builtins.readFile wifiSecrets.iot_psk.path}"
      }

      network={
        ssid="rvproblems-2ghz"
        psk="${builtins.readFile wifiSecrets.rvproblems_2ghz_psk.path}"
      }
    '';

    useDHCP = true;
    hostName = "nixpi";
  };
}
