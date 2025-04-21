{ config, pkgs, lib, ... }:

let
  # Rule to rename physical CAN0 (spi0.0, likely kernel can1) to temporary name
  udevRule70 = pkgs.writeTextFile {
    name = "70-can-rename-temp.rules";
    text = ''
      SUBSYSTEM=="net", ACTION=="add", DEVPATH=="*/spi0.0/net/can*", NAME="can_temp0"
    '';
  };

  # Rule to rename physical CAN1 (spi0.1, likely kernel can0) to final name can1
  udevRule71 = pkgs.writeTextFile {
    name = "71-can-rename-can1.rules";
    text = ''
      SUBSYSTEM=="net", ACTION=="add", DEVPATH=="*/spi0.1/net/can*", NAME="can1"
    '';
  };

  # Rule to rename temporary interface (can_temp0) to final name can0
  udevRule72 = pkgs.writeTextFile {
    name = "72-can-rename-can0.rules";
    text = ''
      # Match the interface now named can_temp0 and rename it to can0
      SUBSYSTEM=="net", KERNEL=="can_temp0", ACTION=="add", NAME="can0"
    '';
  };

in
{
  hardware.enableRedistributableFirmware = true;

  # Enable device tree processing for DTBs matching the standard Pi 4.
  hardware.deviceTree = {
    enable = true;
    filter = "*-rpi-4-*.dtb";

    overlays = [
      # Combined overlay for SPI0 and both MCP2515 CAN controllers
      {
        name = "pican2-duo-spi0";
        dtsText = ''
          /dts-v1/;
          /plugin/;

          / {
            compatible = "brcm,bcm2711";

            // Enable SPI0
            fragment@0 {
              target = <&spi0>;
              __overlay__ { status = "okay"; };
            };

            // Define GPIO pins for CAN0 interrupt
            fragment@1 {
              target = <&gpio>;
              __overlay__ {
                can0_pins: can0_pins {
                  brcm,pins = <25>;     // GPIO25 for CAN0 INT
                  brcm,function = <0>;  // Input
                  brcm,pull = <2>;      // Pull-up
                };
              };
            };

            // Define GPIO pins for CAN1 interrupt
            fragment@2 {
              target = <&gpio>;
              __overlay__ {
                can1_pins: can1_pins {
                  brcm,pins = <24>;     // GPIO24 for CAN1 INT
                  brcm,function = <0>;  // Input
                  brcm,pull = <2>;      // Pull-up
                };
              };
            };

            // Define CAN0 device on SPI0 CS0 (Matches schematic CAN0)
            fragment@3 {
              target = <&spi0>;
              __overlay__ {
                #address-cells = <1>;
                #size-cells = <0>;

                can0_osc: can0_osc@0 { // Unique node name
                  compatible = "fixed-clock";
                  #clock-cells = <0>;
                  clock-frequency = <16000000>; // 16MHz oscillator on PiCAN2 Duo
                };

                can0_mcp: mcp2515@0 { // Node for CS0
                  reg = <0>; // Chip Select 0
                  compatible = "microchip,mcp2515";
                  pinctrl-names = "default";
                  pinctrl-0 = <&can0_pins>; // Use GPIO25 pins (schematic CAN0 INT)
                  spi-max-frequency = <10000000>;
                  interrupt-parent = <&gpio>;
                  interrupts = <25 8>; // Use GPIO25 interrupt (schematic CAN0 INT)
                  clocks = <&can0_osc>;
                };
              };
            };

            // Define CAN1 device on SPI0 CS1 (Matches schematic CAN1)
            fragment@4 {
              target = <&spi0>;
              __overlay__ {
                // spi0 node already has #address-cells and #size-cells defined by fragment@3

                can1_osc: can1_osc@1 { // Unique node name
                  compatible = "fixed-clock";
                  #clock-cells = <0>;
                  clock-frequency = <16000000>; // 16MHz oscillator on PiCAN2 Duo
                };

                can1_mcp: mcp2515@1 { // Node for CS1
                  reg = <1>; // Chip Select 1
                  compatible = "microchip,mcp2515";
                  pinctrl-names = "default";
                  pinctrl-0 = <&can1_pins>; // Use GPIO24 pins (schematic CAN1 INT)
                  spi-max-frequency = <10000000>;
                  interrupt-parent = <&gpio>;
                  interrupts = <24 8>; // Use GPIO24 interrupt (schematic CAN1 INT)
                  clocks = <&can1_osc>;
                };
              };
            };

            // Disable default spidev on CS0
            fragment@5 {
              target = <&spi0>;
              __overlay__ {
                spidev0: spidev@0 {
                  status = "disabled";
                };
              };
            };

            // Disable default spidev on CS1
            fragment@6 {
              target = <&spi0>;
              __overlay__ {
                spidev1: spidev@1 {
                  status = "disabled";
                };
              };
            };
          };
        '';
      }
    ];
  };

  # Create an SPI group for permissions.
  users.groups.spi = {};

  # Remove previous renaming rules from extraRules
  services.udev.extraRules = ''
    # Existing rule for spidev permissions (though spidev is disabled in DT)
    SUBSYSTEM=="spidev", KERNEL=="spidev0.*", GROUP="spi", MODE="0660"
  '';

  # Add ordered rule files via packages
  services.udev.packages = [ udevRule70 udevRule71 udevRule72 ];

  # Disable systemd-networkd as it's not needed for udev renaming
  # and causes warnings with networking.useDHCP=true + networking.useNetworkd=false
  systemd.network.enable = false;

  # Systemd services for the CAN interfaces.
  systemd.services."can0" = {
    description = "CAN0 Interface (Physical CAN0 Port)";
    wantedBy = [ "multi-user.target" ];
    # Wait for udev to settle, hoping the rename has happened
    after = [ "systemd-udev-settle.service" "systemd-modules-load.service" ];
    requires = [ "dev-spi0.device" ];
    startLimitIntervalSec = 30;
    startLimitBurst = 5;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStartPre = "${pkgs.coreutils}/bin/sleep 3";
      ExecStart = pkgs.writeShellScript "setup-can0" ''
        #!/bin/sh
        ${pkgs.iproute2}/bin/ip link set can0 down
        sleep 1
        for i in {1..5}; do
          # Change bitrate to 250000
          if ${pkgs.iproute2}/bin/ip link set can0 up type can bitrate 250000 restart-ms 0; then
            echo 0 > /sys/class/net/can0/statistics/bus_error || true
            exit 0
          fi
          sleep 1
        done
        exit 1
      '';
      ExecStop = "${pkgs.iproute2}/bin/ip link set can0 down";
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };

  systemd.services."can1" = {
    description = "CAN1 Interface (Physical CAN1 Port)";
    wantedBy = [ "multi-user.target" ];
    # Wait for udev to settle, hoping the rename has happened
    after = [ "systemd-udev-settle.service" "systemd-modules-load.service" "can0.service" ];
    requires = [ "dev-spi0.device" ];
    startLimitIntervalSec = 30;
    startLimitBurst = 5;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStartPre = "${pkgs.coreutils}/bin/sleep 3";
      ExecStart = pkgs.writeShellScript "setup-can1" ''
        #!/bin/sh
        ${pkgs.iproute2}/bin/ip link set can1 down
        sleep 1
        for i in {1..5}; do
          # Change bitrate to 250000
          if ${pkgs.iproute2}/bin/ip link set can1 up type can bitrate 250000 restart-ms 0; then
            echo 0 > /sys/class/net/can1/statistics/bus_error || true
            exit 0
          fi
          sleep 1
        done
        exit 1
      '';
      ExecStop = "${pkgs.iproute2}/bin/ip link set can1 down";
      Restart = "on-failure";
      RestartSec = "5s";
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
