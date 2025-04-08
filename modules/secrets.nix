{ pkgs, config, lib, ... }:

let
  bootstrapAgeKeyFile = builtins.toFile "age.key" (builtins.readFile ../secrets/age.key);
in {
  config = {
    environment.systemPackages = [
      pkgs.sops
      pkgs.age
    ];

    environment.etc."sops/age.key".source = bootstrapAgeKeyFile;

    sops = {
      defaultSopsFile = ../secrets/secrets.sops.yaml;

      age = {
        keyFile = "/etc/sops/age.key";
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
