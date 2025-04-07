{ config, pkgs, ... }:
{
  fileSystems."/tmp" = {
    device = "tmpfs";
    fsType = "tmpfs";
    options = [ "nosuid" "nodev" "mode=1777" ];
  };

  fileSystems."/var/tmp" = {
    device = "tmpfs";
    fsType = "tmpfs";
    options = [ "nosuid" "nodev" "mode=1777" ];
  };

  fileSystems."/var/log" = {
    device = "tmpfs";
    fsType = "tmpfs";
    options = [ "nosuid" "nodev" "mode=0755" ];
  };

  fileSystems."/var/cache" = {
    device = "tmpfs";
    fsType = "tmpfs";
    options = [ "nosuid" "nodev" "mode=0755" ];
  };

  # If your application uses a specific directory for ephemeral data,
  # you could also mount that as tmpfs:
  #
  # fileSystems."/var/lib/myapp/cache" = {
  #   device = "tmpfs";
  #   fsType = "tmpfs";
  #   options = [ "nosuid" "nodev" "mode=0755" ];
  # };
}
