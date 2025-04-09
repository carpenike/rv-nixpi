{ config, pkgs, lib, ... }:

{
  hardware.enableRedistributableFirmware = true;

  # Enable static merging of device tree overlays.
  hardware.raspberry-pi."4".apply-overlays-dtmerge.enable = true;

  # Enable device tree processing for DTBs matching the standard Pi 4.
  hardware.deviceTree = {
    enable = true;
    filter = "*-rpi-4-*.dtb";
  };

  # Apply overlays in this order:
  # 1. The SPI overlay from the precompiled dtbo file,
  # 2. Your custom overlay that adds the MCP2515 nodes, and
  # 3. A final overlay that disables the default spidev node (which conflicts on chipselect 0).
  hardware.deviceTree.overlays = [
    # Overlay to enable SPI (from a precompiled dtbo file).
    {
      name = "spi";
      dtboFile = ./firmware/spi0-0cs.dtbo;
    }
    # Custom overlay for the MCP2515 CAN controllers on the SPI bus.
    {
      name = "enable-spi-mcp2515";
      dtsText = ''
        /dts-v1/;
        /plugin/;

        / {
          compatible = "raspberrypi";

          fragment@0 {
            target-path = "/soc/spi@7e204000";
            __overlay__ {
              #address-cells = <1>;
              #size-cells = <0>;
              cs-gpios = <&gpio 8 1>, <&gpio 7 1>;  // GPIO 8 for CS0, GPIO 7 for CS1.
              status = "okay";

              mcp2515@0 {
                compatible = "microchip,mcp2515";
                reg = <0>;  // Chipselect 0.
                spi-max-frequency = <10000000>;  // 10 MHz SPI frequency.
                interrupt-parent = <&gpio>;
                interrupts = <25 8>;  // GPIO 25, active low.
                oscillator-frequency = <16000000>;
                status = "okay";
              };

              mcp2515@1 {
                compatible = "microchip,mcp2515";
                reg = <1>;  // Chipselect 1.
                spi-max-frequency = <10000000>;  // 10 MHz SPI frequency.
                interrupt-parent = <&gpio>;
                interrupts = <24 8>;  // GPIO 24, active low.
                oscillator-frequency = <16000000>;
                status = "okay";
              };
            };
          };
        };
      '';
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
  ];
}
