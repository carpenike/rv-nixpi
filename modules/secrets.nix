{ config, pkgs, lib, ... }:

let
  bootstrapAgeKey =
    if builtins.getEnv "AGE_BOOTSTRAP_KEY" != "" then
      builtins.toFile "age.key" (builtins.getEnv "AGE_BOOTSTRAP_KEY")
    else
      null;
in {
  config = {
    environment.systemPackages = [
      pkgs.sops
      pkgs.age
    ];

    environment.etc = lib.mkIf (bootstrapAgeKey != null) {
      "sops/age.key".source = bootstrapAgeKey;
    };

    sops = {
      defaultSopsFile = ../secrets/secrets.sops.yaml;

      age = {
        keyFile = lib.mkIf (bootstrapAgeKey != null) "/etc/sops/age.key";
        sshKeyPaths = [
          "/etc/ssh/ssh_host_ed25519_key"
        ];
      };

      secrets = {
        ryan_password = {};

        IOT_WIFI_SSID = {
          format = "dotenv";
          mode = "0400";
          restartUnits = ["NetworkManager.service"];
        };

        IOT_WIFI_PASSWORD = {
          format = "dotenv";
          mode = "0400";
          restartUnits = ["NetworkManager.service"];
        };

        RVPROBLEMS_WIFI_SSID = {
          format = "dotenv";
          mode = "0400";
          restartUnits = ["NetworkManager.service"];
        };

        RVPROBLEMS_WIFI_PASSWORD = {
          format = "dotenv";
          mode = "0400";
          restartUnits = ["NetworkManager.service"];
        };
      };
    };
  };
}
