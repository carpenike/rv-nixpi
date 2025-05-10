{ config, pkgs, lib, ... }:

let
  cloudflaredUser = "cloudflared";
in {
  options.services.rvcCloudflared = {
    enable = lib.mkEnableOption "Enable the Cloudflare Tunnel daemon";

    configFile = lib.mkOption {
      type = lib.types.path;
      default = "/etc/cloudflared/config.yml";
      description = "Path to the cloudflared tunnel configuration file";
    };

    credentialsFile = lib.mkOption {
      type = lib.types.path;
      default = config.sops.secrets.cloudflared_tunnel_credentials.path;
      description = "Path to the cloudflared tunnel credentials file (from SOPS)";
    };

    hostname = lib.mkOption {
      type = lib.types.str;
      description = "Hostname for ingress (Cloudflare DNS)";
    };

    service = lib.mkOption {
      type = lib.types.str;
      default = "http://localhost:8000";
      description = "Local service to proxy to";
    };
  };

  config = {
    users.users.${cloudflaredUser} = {
      isSystemUser = true;
      group = cloudflaredUser;
    };

    users.groups.${cloudflaredUser} = {};

    config = lib.mkIf config.services.rvcCloudflared.enable {
      environment.systemPackages = with pkgs; [ cloudflared ];

      environment.etc."cloudflared/config.yml".text = ''
        tunnel: ${builtins.baseNameOf config.services.rvcCloudflared.credentialsFile}
        credentials-file: ${config.services.rvcCloudflared.credentialsFile}

        ingress:
          - hostname: ${config.services.rvcCloudflared.hostname}
            service: ${config.services.rvcCloudflared.service}
          - service: http_status:404
      '';

      systemd.services.cloudflared = {
        description = "Cloudflare Tunnel Daemon";
        after = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          ExecStart = "${pkgs.cloudflared}/bin/cloudflared tunnel --config ${config.services.rvcCloudflared.configFile} run";
          Restart = "always";
          User = cloudflaredUser;
        };
      };
    };
  };
}
