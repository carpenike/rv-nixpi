{ config, pkgs, ... }:
{
  boot = {
    loader.generic-extlinux-compatible.enable = true;

    kernelModules = [ "dwc2" "g_serial" ];
    initrd.kernelModules = [ "dwc2" ];

    extraModprobeConfig = ''
      options g_serial use_acm=1
    '';

    kernelParams = [
      "modules-load=dwc2,g_serial"
      "console=ttyGS0,115200"
    ];

    # 👇 This is the key addition
    loader.raspberryPi.firmwareConfig = ''
      dtoverlay=dwc2
    '';
  };
}
