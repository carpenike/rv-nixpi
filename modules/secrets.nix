{ pkgs, config, lib, ... }:

let
  # Safely include age.key only if it exists (for --impure builds)
  bootstrapAgeKeyFile =
    if builtins.pathExists ../secrets/age.key then
      builtins.toFile "age.key" (builtins.readFile ../secrets/age.key)
    else
      throw ''
        Missing ../secrets/age.key during evaluation.

        You must build with:
          nix build --impure --extra-experimental-features nix-command --extra-experimental-features flakes .#packages.aarch64-linux.sdcard

        Or ensure age.key is placed at ../secrets/age.key.
      '';
in {
  config = {
    environment.systemPackages = [
      pkgs.sops
      pkgs.age
    ];

    # Place the age key in the image under /etc/sops/
    environment.etc."sops/age.key".source = bootstrapAgeKeyFile;

    sops = {
      defaultSopsFile = ../secrets/secrets.sops.yaml;

      age = {
        keyFile = "/etc/sops/age.key"; # This gets used at boot time
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
