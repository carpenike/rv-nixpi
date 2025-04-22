{ config, pkgs, lib, ... }:

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

                can0_osc: can0_osc@0 {
                  compatible = "fixed-clock";
                  #clock-cells = <0>;
                  clock-frequency = <16000000>; // 16MHz oscillator on PiCAN2 Duo
                };

                can0_mcp: mcp2515@0 {
                  reg = <0>; // Chip Select 0
                  compatible = "microchip,mcp2515";
                  pinctrl-names = "default";
                  pinctrl-0 = <&can0_pins>;
                  spi-max-frequency = <10000000>;
                  interrupt-parent = <&gpio>;
                  interrupts = <25 8>;
                  clocks = <&can0_osc>;
                };
              };
            };

            // Define CAN1 device on SPI0 CS1 (Matches schematic CAN1)
            fragment@4 {
              target = <&spi0>;
              __overlay__ {
                can1_osc: can1_osc@1 {
                  compatible = "fixed-clock";
                  #clock-cells = <0>;
                  clock-frequency = <16000000>;
                };

                can1_mcp: mcp2515@1 {
                  reg = <1>;
                  compatible = "microchip,mcp2515";
                  pinctrl-names = "default";
                  pinctrl-0 = <&can1_pins>;
                  spi-max-frequency = <10000000>;
                  interrupt-parent = <&gpio>;
                  interrupts = <24 8>;
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

            // Alias nodes so the kernel names them correctly
            fragment@7 {
              target-path = "/";
              __overlay__ {
                aliases {
                  can0 = &can0_mcp;
                  can1 = &can1_mcp;
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

  # Keep spidev rule in extraRules
  services.udev.extraRules = ''
    # Rule for spidev permissions (keep if needed, though spidev is disabled in DT)
    SUBSYSTEM=="spidev", KERNEL=="spidev0.*", GROUP="spi", MODE="0660"
  '';

  # Disable IPv6 for CAN interfaces to prevent irrelevant udev errors
  boot.kernel.sysctl = {
    "net.ipv6.conf.can0.disable_ipv6" = 1;
    "net.ipv6.conf.can1.disable_ipv6" = 1;
  };

  # Systemd services for the CAN interfaces.
  systemd.services."can0" = {
    description = "CAN0 Interface (Physical CAN0 Port)";
    wantedBy = [ "multi-user.target" ];
    # Wait for networkd to rename the interface
    after = [ "systemd-networkd.service" "systemd-modules-load.service" ];
    requires = [ "dev-spi0.device" ];
    # Bind to the renamed device
    bindsTo = [ "sys-subsystem-net-devices-can0.device" ];
    startLimitIntervalSec = 30;
    startLimitBurst = 5;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "setup-can0" ''
        #!/bin/sh
        ${pkgs.iproute2}/bin/ip link set can0 down
        for i in {1..5}; do
          # Change bitrate to 250000
          if ${pkgs.iproute2}/bin/ip link set can0 up type can bitrate 250000 restart-ms 0; then
            echo 0 > /sys/class/net/can0/statistics/bus_error || true
            exit 0
          fi
          sleep 1 # Keep short sleep between retries
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
    # Wait for networkd and can0 service
    after = [ "systemd-networkd.service" "systemd-modules-load.service" "can0.service" ];
    requires = [ "dev-spi0.device" ];
    # Bind to the renamed device
    bindsTo = [ "sys-subsystem-net-devices-can1.device" ];
    startLimitIntervalSec = 30;
    startLimitBurst = 5;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "setup-can1" ''
        #!/bin/sh
        ${pkgs.iproute2}/bin/ip link set can1 down
        for i in {1..5}; do
          # Change bitrate to 250000
          if ${pkgs.iproute2}/bin/ip link set can1 up type can bitrate 250000 restart-ms 0; then
            echo 0 > /sys/class/net/can1/statistics/bus_error || true
            exit 0
          fi
          sleep 1 # Keep short sleep between retries
        done
        exit 1
      '';
      ExecStop = "${pkgs.iproute2}/bin/ip link set can1 down";
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };

  # Configure networkd-wait-online to only wait for specific interfaces
  systemd.services.systemd-networkd-wait-online.serviceConfig = {
    ExecStart = pkgs.lib.mkForce "${pkgs.systemd}/lib/systemd/systemd-networkd-wait-online --timeout=120 --interface=wlan0 --interface=end0";
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
