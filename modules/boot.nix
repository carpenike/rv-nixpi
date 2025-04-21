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

    initrd.kernelModules = [ "dwc2" ];

    extraModprobeConfig = ''
      options g_serial use_acm=1
      options spi_bcm2835 enable_dma=1
      options mcp251x override_rts=1
    '';

    kernelParams = [
      "modules-load=dwc2,g_serial,spi_bcm2835,can,can_dev,can_raw,mcp251x"
      "console=tty1"
      "console=ttyGS0,115200"
    ];

    # Use the Raspberry Pi-specific kernel
    kernelPackages = pkgs.linuxPackages_rpi4;

    # Enable Raspberry Pi firmware to set dtparam and dtoverlay entries
    boot.firmware.raspberryPi.enable = true;
    boot.firmware.raspberryPi.config = {
      dtparam = {
        spi  = "on";
        sdio = "on";
      };
      dtoverlay = [
        "mcp2515-can0,oscillator=16000000,interrupt=25"
        "mcp2515-can1,oscillator=16000000,interrupt=24"
      ];
    };

    # Removed the spidev-fix.patch as it is already applied in the kernel source.
  };
}