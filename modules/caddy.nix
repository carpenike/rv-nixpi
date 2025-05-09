{ pkgsUnstable }: # Custom arguments

{ config, pkgs, lib, ... }: # Standard NixOS module arguments

with lib;

let
  cfg = config.services.rvcaddy;
in
{
  options.services.rvcaddy = {
    enable = mkEnableOption "Enable Caddy reverse proxy for rvc.holtel.io";

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

  # Apply config only when rvcaddy is enabled, with validation
  config = mkIf cfg.enable (let
    _ensureEmail = lib.assertString cfg.acmeEmail;
    _ensureTokenFile = if !builtins.pathExists cfg.cloudflareApiTokenFile then
      builtins.error "services.rvcaddy.cloudflareApiTokenFile: file does not exist"
    else null;
  in {
    # Core Caddy service configuration
    services.caddy = {
      enable = true;
      # Use pkgsUnstable for Caddy and its plugin
      package = pkgsUnstable.caddy.override { plugins = [ pkgsUnstable.caddyPlugins.cloudflare ]; };
      email = cfg.acmeEmail;

      virtualHosts."${cfg.hostname}" = {
        extraConfig = ''
          reverse_proxy ${cfg.proxyTarget}
          tls {
            dns cloudflare {env.CLOUDFLARE_API_TOKEN_FILE}
          }
        '';
      };
    };

    # Inject Cloudflare token file into the Caddy systemd service environment
    systemd.services.caddy.serviceConfig.Environment = [
      "CLOUDFLARE_API_TOKEN_FILE=${cfg.cloudflareApiTokenFile}"
    ];

    # Open HTTP/HTTPS ports
    networking.firewall.allowedTCPPorts = [ 80 443 ];
  });
}
