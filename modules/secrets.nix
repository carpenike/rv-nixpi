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
      # Only show warning during initial image build, not during system rebuilds
      if config.system.build ? sdImage then 
        builtins.trace "WARNING: AGE_BOOTSTRAP_KEY environment variable is not set" null
      else
        null;
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
        # Cloudflare API token for Caddy DNS challenge
        cloudflare_api_token = {
          # owner = config.services.caddy.user;  # Caddy service user
          # group = config.services.caddy.group; # Caddy service group
          mode = "0400"; # Read-only for the Caddy user
        };
        cloudflared_tunnel_credentials = {
          owner = "cloudflared";
          group = "cloudflared";
          mode = "0400";
          path = "/etc/cloudflared/2e9bd6fe-a25a-4bb0-89a5-fa1f69d62b97.json";  # Must match what's in config.yml
        }; 

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
