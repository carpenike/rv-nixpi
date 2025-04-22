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
      "spi_bcm2835"
      "can"
      "can_raw"
      "can_dev"
      "mcp251x"
    ];

    initrd.kernelModules = [ "dwc2" ];

    extraModprobeConfig = ''
      options g_serial use_acm=1
      # options spi_bcm2835 enable_dma=1 # Removed ignored option
    '';

    kernelParams = [
      "console=tty1"
      "console=ttyGS0,115200"
    ];

    # Use the Raspberry Pi-specific kernel
    kernelPackages = pkgs.linuxPackages_rpi4;

  };
}