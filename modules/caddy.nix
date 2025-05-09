{ unstablePkgs }: # Argument is the full nixpkgsUnstable flake input

{ config, pkgs, lib, ... }: # Standard NixOS module arguments

with lib;
let
  cfg = config.services.rvcaddy; # Options for our custom wrapper module
in
{
  # Import the Caddy NixOS module from the unstable channel.
  # This makes the unstable Caddy options (like environmentFile) available.
  imports = [
    unstablePkgs.nixosModules.caddy # This ensures services.caddy options are from unstable
  ];

  options.services.rvcaddy = {
    enable = mkEnableOption "Enable Caddy reverse proxy for rvc.holtel.io (via rvcaddy module)";

    hostname = mkOption {
      type = types.str;
      default = "rvc.holtel.io";
      description = "The hostname Caddy will serve.";
    };

    acmeEmail = mkOption {
      type = types.str;
      example = "your-email@example.com";
      description = "Email address for ACME certificate registration.";
    };

    cloudflareApiTokenFile = mkOption {
      type = types.path;
      example = "/run/secrets/cloudflare-api-token";
      description = ''
        Path to a file containing the Cloudflare API token.
        This token needs permissions to edit DNS records for the domain.
        It is strongly recommended to manage this file using sops-nix.
      '';
    };

    proxyTarget = mkOption {
      type = types.str;
      default = "http://localhost:8000";
      description = "The backend service Caddy will proxy to (e.g., http://localhost:8000).";
    };
  };

  config = mkIf cfg.enable {
    # Configure the services.caddy options (now from the unstable module)
    services.caddy = {
      enable = true; # This enables the Caddy service itself
      # Use the Caddy package and plugin from the unstable channel's packages
      # pkgs.system here refers to the system of the main configuration (stable)
      package = unstablePkgs.legacyPackages.${pkgs.system}.caddy.override {
        plugins = [ unstablePkgs.legacyPackages.${pkgs.system}.caddyPlugins.cloudflare ];
      };
      email = cfg.acmeEmail;

      # environmentFile is now a valid option due to importing unstablePkgs.nixosModules.caddy
      environmentFile = pkgs.writeText "caddy-rvcaddy-env" ''
        CLOUDFLARE_API_TOKEN_FILE=${cfg.cloudflareApiTokenFile}
      ''; # pkgs.writeText from stable pkgs is fine here

      virtualHosts."${cfg.hostname}" = {
        extraConfig = ''
          reverse_proxy ${cfg.proxyTarget}
          tls {
            dns cloudflare {env.CLOUDFLARE_API_TOKEN_FILE}
          }
        '';
      };
    };

    networking.firewall.allowedTCPPorts = [ 80 443 ];

    # Ensure Caddy user can access the sops-managed secret
    # config.sops.secrets.* is available because sops-nix module is in commonModules
    users.users.caddy.extraGroups = [ config.sops.secrets.cloudflare_api_token.group ];
  };
}
