# modules/cloudflared.nix
{ config, pkgs, lib, ... }:

let
  cloudflaredUser = "cloudflared";
in {
  options.services.cloudflared = {
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

  config = lib.mkIf config.services.cloudflared.enable {
    users.users.${cloudflaredUser} = {
      isSystemUser = true;
      group = cloudflaredUser;
    };

    users.groups.${cloudflaredUser} = {};

    environment.systemPackages = with pkgs; [ cloudflared ];

    environment.etc."cloudflared/config.yml".text = ''
      tunnel: ${builtins.baseNameOf config.services.cloudflared.credentialsFile}
      credentials-file: ${config.services.cloudflared.credentialsFile}

      ingress:
        - hostname: ${config.services.cloudflared.hostname}
          service: ${config.services.cloudflared.service}
        - service: http_status:404
    '';

    systemd.services.cloudflared = {
      description = "Cloudflare Tunnel Daemon";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.cloudflared}/bin/cloudflared tunnel --config ${config.services.cloudflared.configFile} run";
        Restart = "always";
        User = cloudflaredUser;
      };
    };
  };
}
