{ config, pkgs, lib, ... }:

{
  hardware.enableRedistributableFirmware = true;

  # Enable static merging of device tree overlays and skip the CPU revision overlay.
  hardware.raspberry-pi."4".apply-overlays-dtmerge.enable = true;

  # Enable device tree with a filter so that only DTBs matching the standard Pi 4 are processed.
  hardware.deviceTree = {
    enable = true;
    filter = "*-rpi-4-*.dtb";
  };

  # Apply overlays for enabling SPI and adding the MCP2515 nodes.
  hardware.deviceTree.overlays = [
    # Overlay to enable SPI (from a dtso file)
    {
      name = "spi";
      dtsoFile = ./firmware/spi0-0cs.dtso;
    }
    # Custom overlay for the MCP2515 CAN controllers on the SPI bus
    # {
    #   name = "enable-spi-mcp2515";
    #   dtsText = ''
    #     /dts-v1/;
    #     /plugin/;

    #     / {
    #       // No top-level "compatible" property

    #       fragment@0 {
    #         target = <&spi0>;
    #         __overlay__ {
    #           status = "okay";
    #         };
    #       };

    #       fragment@1 {
    #         target = <&spi0>;
    #         __overlay__ {
    #           #address-cells = <2>;
    #           #size-cells = <1>;

    #           mcp2515@0 {
    #             compatible = "microchip,mcp2515";
    #             reg = <0 0 0>;
    #             spi-max-frequency = <10000000>;
    #             interrupt-parent = <&gpio>;
    #             interrupts = <25 8>;
    #             oscillator-frequency = <16000000>;
    #             status = "okay";
    #           };

    #           mcp2515@1 {
    #             compatible = "microchip,mcp2515";
    #             reg = <0 1 0>;
    #             spi-max-frequency = <10000000>;
    #             interrupt-parent = <&gpio>;
    #             interrupts = <24 8>;
    #             oscillator-frequency = <16000000>;
    #             status = "okay";
    #           };
    #         };
    #       };
    #     };
    #   '';
    # }
  ];

  # Create an SPI group
  users.groups.spi = {};

  # Set up udev rules for spidev
  services.udev.extraRules = ''
    SUBSYSTEM=="spidev", KERNEL=="spidev0.0", GROUP="spi", MODE="0660"
  '';

  # Systemd services for the CAN interfaces
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

  environment.systemPackages = with pkgs; [
    dtc
    usbutils
    pciutils
    i2c-tools
  ];
}
