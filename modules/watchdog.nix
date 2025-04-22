{
  # Enable the hardware watchdog timer
  boot.kernelModules = [ "bcm2835_wdt" ];
  systemd.services.watchdog = {
    enable = true;
    description = "Hardware Watchdog Service";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      # Use the hardware watchdog device
      ExecStart = "${pkgs.systemd}/lib/systemd/systemd-watchdog";
      WatchdogSec = "30s"; # Reboot if not touched within 30 seconds
      Restart = "always";
      RestartSec = "1s";
    };
  };

  # Configure systemd to use the watchdog
  systemd.watchdog = {
    runtime = true; # Let systemd ping the watchdog
    shutdown = "10s"; # Time to wait for shutdown before watchdog triggers
  };
}
