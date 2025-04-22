{ config, pkgs, ... }:

{
  # Define a dedicated user and group for glances
  users.users.glances = {
    isSystemUser = true;
    group = "glances";
  };
  users.groups.glances = {};

  # Define the systemd service for glances web mode
  systemd.services.glances-web = {
    description = "Glances system monitor web UI";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      User = "glances";
      Group = "glances";
      ExecStart = "${pkgs.glances}/bin/glances -w";
      Restart = "always";
      # Optional: Specify host and port if needed, e.g., -b 0.0.0.0 -p 8080
      # ExecStart = "${pkgs.glances}/bin/glances -w -b 0.0.0.0 -p 61208";
    };
  };

  # Add glances package to system environment when this module is enabled
  environment.systemPackages = [ pkgs.glances ];

  # Open the required firewall port
  networking.firewall.allowedTCPPorts = [ 61208 ];
}
