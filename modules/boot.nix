{ config, pkgs, lib, ... }:

{
  boot = {
    loader.generic-extlinux-compatible = {
      enable = true;
      configurationLimit = 1;
    };

    kernelModules = [
      "dwc2"
      "g_serial"
      "vc4"
      "bcm2835_dma"
      "spi-bcm2835"
      "mcp251x"
    ];

    initrd.kernelModules = [ "dwc2" ];

    extraModprobeConfig = ''
      options g_serial use_acm=1
    '';

    kernelParams = [
      "modules-load=dwc2,g_serial"
      "console=tty1"
      "console=ttyGS0,115200"
    ];

    # Apply kernel patch to fix spidev detection on Raspberry Pi 4.
    kernelPatches = [
      {
        name = "spidev-fix.patch";
        patch = pkgs.fetchpatch {
          url = "https://github.com/raspberrypi/linux/commit/2f223e0e4931486fbc32df3c89bc16ff1ca434bf.patch";
          hash = "sha256-//9aGbzXNO33arOTTCVz67jOV8ytyVARdYc/1iIEMc0=";
        };
      }
    ];
  };
}
