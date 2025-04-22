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

    # Explicitly disable ZFS ZED service if not needed
    zfs.zed.enable = false;
  };

  # Enable a serial console on ttyGS0 (USB gadget serial)
  systemd.services."serial-getty@ttyGS0".enable = true;
}
