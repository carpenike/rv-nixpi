{ config, pkgs, lib, ... }:
{
  boot = {
    loader.generic-extlinux-compatible.enable = true;
    kernelModules = lib.filter (mod: mod != "sun4i-drm") [ "dwc2" "g_serial" ];
    extraModprobeConfig = ''
      options g_serial use_acm=1
    '';
    kernelParams = [
      "modules-load=dwc2,g_serial"
      "console=ttyGS0,115200"
    ];
    initrd.kernelModules = [ "dwc2" ];
  };
}
