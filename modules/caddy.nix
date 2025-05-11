{ config, pkgs, lib, ... }:

{
  ##############################################################################
  # 1) module options
  ##############################################################################
  options.services.rvcCaddy = {
    enable = lib.mkEnableOption
      "Enable Caddy to reverse proxy FastAPI and serve Let's Encrypt certs";

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
      environmentFile = "/etc/caddy/cloudflare.env";

      # your LE account email
      email           = config.services.rvcCaddy.email;

      # globally enable DNS-01 via Cloudflare
      globalConfig    = ''
        dns cloudflare {env.CLOUDFLARE_API_TOKEN}
      '';

      # reverse-proxy stub
      virtualHosts."${config.services.rvcCaddy.hostname}".extraConfig = ''
        reverse_proxy 127.0.0.1:${toString config.services.rvcCaddy.backendPort}
      '';
    };

    networking.firewall.allowedTCPPorts = [ 80 443 ];
  };
}
