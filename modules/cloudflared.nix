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
      description = "External hostname (Cloudflare DNS) for ingress";
    };

    # The local service endpoint. Use localhost for portability if your Caddy box IP may change.
    service = lib.mkOption {
      type = lib.types.str;
      default = "https://localhost:443";
      description = "Local service to proxy to (Caddy endpoint listening on 443)";
    };
  };

  config = {
    # Create a system user for cloudflared
    users.users.${cloudflaredUser} = {
      isSystemUser = true;
      group = cloudflaredUser;
    };

    users.groups.${cloudflaredUser} = {};

    # Install the cloudflared binary
    environment.systemPackages = lib.mkIf config.services.rvcCloudflared.enable (with pkgs; [ cloudflared ]);

    # Generate the cloudflared config.yml
    environment.etc."cloudflared/config.yml".text = lib.mkIf config.services.rvcCloudflared.enable ''
      tunnel: ${builtins.baseNameOf config.services.rvcCloudflared.credentialsFile}
      credentials-file: ${config.services.rvcCloudflared.credentialsFile}

      ingress:
        - hostname: ${config.services.rvcCloudflared.hostname}
          service: ${config.services.rvcCloudflared.service}
          originRequest:
            serverName: ${config.services.rvcCloudflared.hostname}
            noTLSVerify: true
        - service: http_status:404
    '';

    # Define the systemd service
    systemd.services.cloudflared = lib.mkIf config.services.rvcCloudflared.enable {
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
}
