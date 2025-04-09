{ config, pkgs, ... }:

{
  boot = {
    loader.generic-extlinux-compatible.enable = true;

    # Existing gadget config
    kernelModules = [ "dwc2" "g_serial" "vc4" "bcm2835_dma" ];
    initrd.kernelModules = [ "dwc2" ];

    extraModprobeConfig = ''
      options g_serial use_acm=1
    '';

    kernelParams = [
      "modules-load=dwc2,g_serial"
      "console=tty1"
      "console=ttyGS0,115200"
    ];
  };
}
