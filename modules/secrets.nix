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

    environment.etc."sops/age.key".source = lib.mkIf (bootstrapAgeKey != null) bootstrapAgeKey;

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
        IOT_WIFI_SSID = {};
        IOT_WIFI_PASSWORD = {};
        RVPROBLEMS_WIFI_SSID = {};
        RVPROBLEMS_WIFI_PASSWORD = {};
      };
    };
  };
}
