{ config, pkgs, ... }:
{
  services = {
    openssh.enable = true;
    getty."ttyGS0".enable = true;
    journald.extraConfig = "Storage=volatile";
  };
}
