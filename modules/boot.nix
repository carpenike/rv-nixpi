{ config, pkgs, ... }:

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
    ];

    initrd.kernelModules = [ "dwc2" ];

    extraModprobeConfig = ''
      options g_serial use_acm=1
    '';

    # Remove the dtoverlay parameters that weren't being processed correctly
    kernelParams = [
      "modules-load=dwc2,g_serial"
      "console=tty1"
      "console=ttyGS0,115200"
      "dtparam=spi=on"
      # Remove these two lines:
      # "dtoverlay=mcp2515-can0,oscillator=16000000,interrupt=25"
      # "dtoverlay=mcp2515-can1,oscillator=16000000,interrupt=24"
    ];
  };

  hardware.enableRedistributableFirmware = true;
}
