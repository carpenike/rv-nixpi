# /Users/ryan/src/rv-nixpi/modules/caddy.nix
{ config, pkgs, lib, ... }:

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

    cloudflareApiTokenFile = mkOption {
      type = types.path;
      # This should be an absolute path, typically managed by sops-nix like /run/secrets/cloudflare_api_token
      description = ''
        Path to a file containing the Cloudflare API token.
        This token needs permissions to edit DNS records for the domain.
        It is strongly recommended to manage this file using sops-nix.
      '';
      example = "/run/secrets/cloudflare-api-token";
    };

    proxyTarget = mkOption {
      type = types.str;
      default = "http://localhost:8000"; # Default for rvc2api
      description = "The backend service Caddy will proxy to (e.g., http://localhost:8000).";
    };
  };

  config = mkIf cfg.enable {
    services.caddy = {
      enable = true;
      package = pkgs.caddy.override {
        plugins = [ pkgs.caddyPlugins.cloudflare ];
      };

      environmentVariables = {
        # The caddy-dns/cloudflare plugin uses CLOUDFLARE_API_TOKEN_FILE
        # when the token is provided via a file.
        CLOUDFLARE_API_TOKEN_FILE = cfg.cloudflareApiTokenFile;
      };

      configText = ''
        ${cfg.hostname} {
          reverse_proxy ${cfg.proxyTarget}
          tls {
            dns cloudflare {env.CLOUDFLARE_API_TOKEN_FILE}
          }
        }

        # Redirect HTTP to HTTPS
        http://${cfg.hostname} {
          redir https://${cfg.hostname}{uri} permanent
        }
      '';
    };

    # Open firewall ports for Caddy (HTTP for redirects/challenges, HTTPS for serving)
    networking.firewall.allowedTCPPorts = [ 80 443 ];
  };
}
