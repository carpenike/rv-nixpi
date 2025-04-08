{ pkgs, config, lib, ... }:

let
  bootstrapAgeKey = builtins.readFile ../secrets/age.key;
in {
  config = {
    environment.systemPackages = [
      pkgs.sops
      pkgs.age
    ];

    # Embed the bootstrap age key into the image (works during image build)
    environment.etc."sops/age.key".source =
      pkgs.runCommand "bootstrap-age-key"
        { }
        ''
          mkdir -p $out
          echo '${bootstrapAgeKey}' > $out/age.key
        '';

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
