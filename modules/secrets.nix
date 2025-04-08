{ pkgs, config, lib, ... }:

{
  config = {
    environment.systemPackages = [
      pkgs.sops
      pkgs.age
    ];

    # Embed the bootstrap age key into the image
    environment.etc."sops/age.key".source = ../secrets/age.key;

    sops = {
      defaultSopsFile = ../secrets/secrets.sops.yaml;

      age = {
        # Use both the bootstrap key and the SSH host key
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
