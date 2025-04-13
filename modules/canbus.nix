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

      # Overlay to enable SPI (from a precompiled dtbo file).
      {
        name = "spi";
        dtboFile = ./firmware/spi0-0cs-final.dtbo;
      }

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
    ];
  };

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
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStartPre = "${pkgs.coreutils}/bin/sleep 5";
      ExecStart = "${pkgs.iproute2}/bin/ip link set can0 up type can bitrate 500000";
      ExecStop = "${pkgs.iproute2}/bin/ip link set can0 down";
    };
  };

  systemd.services."can1" = {
    description = "CAN1 Interface";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-modules-load.service" "can0.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStartPre = "${pkgs.coreutils}/bin/sleep 5";
      ExecStart = "${pkgs.iproute2}/bin/ip link set can1 up type can bitrate 500000";
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
