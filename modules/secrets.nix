{ config, pkgs, lib, ... }:

let
  # Read the bootstrap key from the environment variable at build time
  bootstrapAgeKeyEnv = builtins.getEnv "AGE_BOOTSTRAP_KEY";
  
  # Create a source for the key if the environment variable is set
  bootstrapAgeKey = 
    if bootstrapAgeKeyEnv != "" then
      builtins.trace "Found AGE_BOOTSTRAP_KEY environment variable (${toString (builtins.stringLength bootstrapAgeKeyEnv)} bytes)"
      (pkgs.writeText "age.key" bootstrapAgeKeyEnv)
    else
      builtins.trace "WARNING: AGE_BOOTSTRAP_KEY environment variable is not set" null;
in {
  config = {
    environment.systemPackages = [
      pkgs.sops
      pkgs.age
    ];

    environment.etc = lib.mkIf (bootstrapAgeKey != null) {
      "sops/age.key" = {
        source = bootstrapAgeKey;
        mode = "0600";  # Restrictive permissions for the key file
        user = "root";
        group = "root";
      };
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
        IOT_WIFI_SSID = {};
        IOT_WIFI_PASSWORD = {};
        RVPROBLEMS_WIFI_SSID = {};
        RVPROBLEMS_WIFI_PASSWORD = {};
      };
    };
    
    # Service to verify age key presence on boot
    systemd.services.verify-age-key = {
      description = "Verify presence of age.key file";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.writeShellScript "check-age-key" (builtins.readFile ./check-age-key.sh)}";
      };
    };
  };
}
