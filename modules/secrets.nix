{ pkgs, config, lib, ... }:

let
  bootstrapAgeKey =
    if builtins.hasEnv "AGE_BOOTSTRAP_KEY" then
      builtins.toFile "age.key" (builtins.getEnv "AGE_BOOTSTRAP_KEY")
    else
      throw "Environment variable AGE_BOOTSTRAP_KEY not set. Use --impure and export AGE_BOOTSTRAP_KEY.";
in
{
  config = {
    environment.systemPackages = with pkgs; [
      sops
      age
    ];

    # Inject age key at build time
    environment.etc."sops/age.key".source = bootstrapAgeKey;

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
