{ config, pkgs, lib, ... }:

{
  hardware.enableRedistributableFirmware = true;

  # Enable static merging of device tree overlays.
  hardware.raspberry-pi."4".apply-overlays-dtmerge.enable = true;

  # Enable device tree processing for DTBs matching the standard Pi 4.
  hardware.deviceTree = {
    dtbSource = pkgs.device-tree_rpi;
    enable = true;
    filter = "*-rpi-4-*.dtb";
    name = "broadcom/bcm2711-rpi-4-b.dtb";
    overlays = [
      {
        dtboFile = pkgs.runCommand "spi0-1cs" { nativeBuildInputs = [ pkgs.dtc ]; } ''
          dtc -I dtb -o spi0-1cs.dtso -O dts ${pkgs.device-tree_rpi.overlays}/spi0-1cs.dtbo
          substituteInPlace spi0-1cs.dtso \
            --replace-fail "compatible = \"brcm,bcm2835\";" "compatible = \"brcm,bcm2711\";"
          dtc -I dts -o $out -O dtb spi0-1cs.dtso
        '';
        name = "spi0-1cs.dtbo";
      }

      # Disable PiCAN2 overlay while doing loopback test
      # { name = "pican2-duo"; dtboFile = ./firmware/pican2-simple.dtbo; }
      # Enable spidev overlay for raw SPI access
      { name = "spidev"; }

      # Overlay to disable the default spidev node for chipselect 0.
      {
        name = "disable-spidev0";
        dtsText = ''
          /dts-v1/;
          /plugin/;

          / {
            compatible = "raspberrypi";

            fragment@0 {
              target-path = "/soc/spi@7e204000/spidev@0";
              __overlay__ {
                status = "disabled";
              };
            };
          };
        '';
      }
      {
        name = "spi0-0cs-final";
        dtboFile = ./firmware/spi0-0cs-final.dtbo;
      }
      {
        name = "mcp2515-can-final";
        dtboFile = ./firmware/mcp2515-can-final.dtbo;
      }
    ];
  };

  # Removed redundant kernelModules configuration as it is already handled in boot.nix

  boot.extraModprobeConfig = ''
    options spi_bcm2835 enable_dma=1
  '';

  # Create an SPI group for permissions.
  users.groups.spi = {};

  # Set up udev rules for spidev.
  services.udev.extraRules = ''
    SUBSYSTEM=="spidev", KERNEL=="spidev0.0", GROUP="spi", MODE="0660"
  '';

  # Systemd services for the CAN interfaces.
  systemd.services."can0" = {
    description = "CAN0 Interface";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-modules-load.service" ];
    requires = [ "dev-spi0.device" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.bash}/bin/bash -c 'sleep 2 && ${pkgs.iproute2}/bin/ip link set can0 up type can bitrate 500000 restart-ms 100'";
      ExecStop = "${pkgs.iproute2}/bin/ip link set can0 down";
    };
  };

  systemd.services."can1" = {
    description = "CAN1 Interface";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-modules-load.service" "can0.service" ];
    requires = [ "dev-spi0.device" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.bash}/bin/bash -c 'sleep 2 && ${pkgs.iproute2}/bin/ip link set can1 up type can bitrate 500000 restart-ms 100'";
      ExecStop = "${pkgs.iproute2}/bin/ip link set can1 down";
    };
  };

  # Add can-utils and debugging tools.
  environment.systemPackages = with pkgs; [
    can-utils
    dtc
    usbutils
    pciutils
    i2c-tools
    python3Packages.spidev  # For SPI tools
  ];
}
