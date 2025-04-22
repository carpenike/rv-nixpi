{ config, pkgs, lib, ... }:

{
  # Enable the hardware watchdog timer
  boot.kernelModules = [ "bcm2835_wdt" ];

  # This service is not strictly needed if systemd itself handles the watchdog,
  # but can provide clearer status.
  # systemd.services.watchdog = { ... }; # We can potentially remove this later if desired.

  # Configure systemd to use the watchdog
  systemd.extraConfig = ''
    RuntimeWatchdogSec=30s
    ShutdownWatchdogSec=10s
  '';

  # Remove the incorrect block:
  # systemd.watchdog = {
  #   runtime = true;
  #   shutdown = "10s";
  # };
}
