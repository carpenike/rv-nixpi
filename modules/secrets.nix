{ pkgs, config, lib, ... }:

let
  # Refer to the absolute path from outside the store
  ageKeyHostPath = ../secrets/age.key;

  # Build-time reference using toFile so it gets copied into /etc/sops
  bootstrapAgeKeyFile = builtins.toFile "age.key" (builtins.readFile ageKeyHostPath);
in {
  config = {
    environment.systemPackages = [
      pkgs.sops
      pkgs.age
    ];

    # Install the age key to the image
    environment.etc."sops/age.key".source = bootstrapAgeKeyFile;

    sops = {
      defaultSopsFile = ../secrets/secrets.sops.yaml;

      age = {
        keyFile = "/etc/sops/age.key"; # used at runtime
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
