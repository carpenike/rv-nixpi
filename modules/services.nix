{ config, pkgs, ... }:

{
  services = {
    openssh.enable = true;
    journald.extraConfig = "Storage=volatile";

    # Enable NTP syncing with systemd-timesyncd
    timesyncd.enable = true;
  };

  # Enable a serial console on ttyGS0 (USB gadget serial)
  systemd.services."serial-getty@ttyGS0".enable = true;
}
