{ config, pkgs, lib, ... }:

{
  ##############################################################################
  # 1) module options
  ##############################################################################
  options.services.rvcCaddy = {
    enable = lib.mkEnableOption "Enable Caddy to serve React frontend and reverse proxy FastAPI";

    hostname = lib.mkOption {
      type        = lib.types.str;
      description = "Hostname to serve over HTTPS (must match Cloudflare DNS)";
    };

    backendPort = lib.mkOption {
      type        = lib.types.port;
      default     = 8000;
      description = "Local FastAPI port to reverse proxy";
    };

    email = lib.mkOption {
      type        = lib.types.str;
      description = "Email for Let's Encrypt notifications";
    };

    reactDistPath = lib.mkOption {
      type        = lib.types.str;
      default     = "/var/lib/rvc2api-web-ui/dist";
      description = "Path to the built React frontend dist directory";
    };
  };

  ##############################################################################
  # 2) module configuration
  ##############################################################################
  config = lib.mkIf config.services.rvcCaddy.enable {
    services.caddy = {
      enable          = true;

      # uses the overlayed Caddy (with Cloudflare DNS plugin)
      package         = pkgs.caddy;

      # systemd will load this file for the env vars:
      environmentFile = "/run/secrets/caddy_cloudflare_env";

      # your LE account email
      email           = config.services.rvcCaddy.email;

      # # globally enable DNS-01 via Cloudflare
      # globalConfig    = ''
      #   dns cloudflare {env.CLOUDFLARE_API_TOKEN}
      # '';

      # Caddyfile for the domain - serve React frontend and proxy API
      virtualHosts."${config.services.rvcCaddy.hostname}" = {
        extraConfig = ''
          # TLS configuration with Cloudflare DNS validation
          tls {
            dns cloudflare {env.CLOUDFLARE_API_TOKEN}
            resolvers 1.1.1.1
          }
          
          # Serve API paths - proxy to FastAPI backend
          handle /api/* {
            reverse_proxy localhost:${toString config.services.rvcCaddy.backendPort}
          }

          # Serve WebSocket paths - proxy to FastAPI backend
          handle /ws/* {
            reverse_proxy localhost:${toString config.services.rvcCaddy.backendPort}
          }
          
          # Serve static React frontend
          handle {
            root * ${config.services.rvcCaddy.reactDistPath}
            try_files {path} /index.html
            file_server
          }
        '';
      };
    };

    networking.firewall.allowedTCPPorts = [ 80 443 ];
  };
}
