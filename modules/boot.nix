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
      "spi_bcm2835"  # Note the underscore instead of dash
      "can"
      "can_raw"
      "can_dev"
      "mcp251x"
    ];

    initrd.kernelModules = [
      "dwc2"
      "spi_bcm2835"
      "spidev"
      "can"
      "can_dev"
      "can_raw"
      "mcp251x"
    ];

    extraModprobeConfig = ''
      options g_serial use_acm=1
      options spi_bcm2835 enable_dma=1
    '';

    kernelParams = [
      "console=tty1"
      "console=ttyGS0,115200"
    ];

    # Use the Raspberry Pi-specific kernel
    kernelPackages = pkgs.linuxPackages_rpi4;

    # Removed the spidev-fix.patch as it is already applied in the kernel source.
  };
}
