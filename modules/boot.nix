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
      # Don't add CAN modules here - they're in canbus.nix
    ];

    initrd.kernelModules = [ "dwc2" ];

    extraModprobeConfig = ''
      options g_serial use_acm=1
    '';

    # Include SPI and CAN related kernel parameters along with your existing ones
    kernelParams = [
      "modules-load=dwc2,g_serial"
      "console=tty1"
      "console=ttyGS0,115200"
      "dtparam=spi=on"
      "dtoverlay=mcp2515-can0,oscillator=16000000,interrupt=25"
      "dtoverlay=mcp2515-can1,oscillator=16000000,interrupt=24"
    ];
  };

  hardware.enableRedistributableFirmware = true;
}
