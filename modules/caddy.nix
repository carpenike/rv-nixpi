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

  # Only apply config when rvcaddy is enabled, with assertions
  config = mkIf cfg.enable (let
    _emailOk = lib.assertString cfg.acmeEmail;
    _tokenFileExists = if !builtins.pathExists cfg.cloudflareApiTokenFile then builtins.error "services.rvcaddy.cloudflareApiTokenFile: file does not exist" else null;
  in {
    services.caddy = {
      enable = true;
      package = pkgs.caddy.override { plugins = [ pkgs.caddyPlugins.cloudflare ]; };

      # Set the ACME email for certificate issuance
      email = cfg.acmeEmail;

      # Expose CF token file path via systemd environment
      serviceConfig = {
        Environment = [ "CLOUDFLARE_API_TOKEN_FILE=${cfg.cloudflareApiTokenFile}" ];
      };

      virtualHosts."${cfg.hostname}" = {
        extraConfig = ''
          reverse_proxy ${cfg.proxyTarget}
          tls {
            dns cloudflare {env.CLOUDFLARE_API_TOKEN_FILE}
          }
        '';
      };
    };

    # Open HTTP/HTTPS ports for Caddy
    networking.firewall.allowedTCPPorts = [ 80 443 ];
  });
}
