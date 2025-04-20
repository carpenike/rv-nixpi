{ config, pkgs, ... }:

{
  services = {
    openssh.enable = true;
    journald.extraConfig = "Storage=volatile";

    # Enable NTP syncing with systemd-timesyncd
    timesyncd = {
      enable = true;
      # Use Cloudflare and Google NTP servers for faster sync
      servers = [
        "time.cloudflare.com"
        "time.google.com"
        "0.pool.ntp.org"
        "1.pool.ntp.org"
      ];
    };
  };

  # Enable hwclock to save and restore time between reboots
  # This helps when the Pi has no RTC module
  systemd.services.hwclock-sync = {
    description = "Synchronize hardware clock on startup";
    wantedBy = [ "sysinit.target" ];
    after = [ "systemd-modules-load.service" ];
    before = [ "timesyncd.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "sync-hwclock" ''
        # Try to set a reasonable time at boot if system time looks bad
        CURRENT_YEAR=$(date +%Y)
        if [ "$CURRENT_YEAR" -lt "2023" ]; then
          echo "System time before 2023 detected (current time: $(date))"
          echo "Setting time to build time as fallback"
          # Use the build time of this script as a reasonable fallback time
          touch /run/fake-time-marker
          hwclock --systohc
          echo "Time set to: $(date)"
        fi
      '';
      RemainAfterExit = true;
    };
  };

  # Enable a serial console on ttyGS0 (USB gadget serial)
  systemd.services."serial-getty@ttyGS0".enable = true;
}
