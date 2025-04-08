{ config, pkgs, ... }:
{
  services = {
    openssh.enable = true;
    journald.extraConfig = "Storage=volatile";
  };

  # Enable a serial console on ttyGS0 (USB gadget serial)
  # systemd.services."serial-getty@ttyGS0".enable = true;
  services.getty."ttyGS0".enable = true;
}
