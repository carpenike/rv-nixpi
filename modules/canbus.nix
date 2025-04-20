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
      # Enable SPI0 with 2 chip selects
      {
        dtboFile = pkgs.runCommand "spi0-2cs" { nativeBuildInputs = [ pkgs.dtc ]; } ''
          dtc -I dtb -o spi0-2cs.dtso -O dts ${pkgs.device-tree_rpi.overlays}/spi0-2cs.dtbo
          substituteInPlace spi0-2cs.dtso \
            --replace-fail "compatible = \"brcm,bcm2835\";" "compatible = \"brcm,bcm2711\";"
          dtc -I dts -o $out -O dtb spi0-2cs.dtso
        '';
        name = "spi0-2cs.dtbo";
      }

      # Overlay to disable the default spidev nodes
      {
        name = "disable-spidev";
        dtsText = ''
          /dts-v1/;
          /plugin/;

          / {
            compatible = "brcm,bcm2711";

            fragment@0 {
              target-path = "/soc/spi@7e204000/spidev@0";
              __overlay__ {
                status = "disabled";
              };
            };

            fragment@1 {
              target-path = "/soc/spi@7e204000/spidev@1";
              __overlay__ {
                status = "disabled";
              };
            };
          };
        '';
      }

      # MCP2515 CAN0 controller on SPI0.0
      {
        name = "mcp2515-can0";
        dtsText = ''
          /dts-v1/;
          /plugin/;

          / {
            compatible = "brcm,bcm2711";

            fragment@0 {
              target = <&spi0>;
              __overlay__ {
                status = "okay";
                #address-cells = <1>;
                #size-cells = <0>;

                /* First MCP2515 CAN controller */
                mcp2515_can0: mcp2515@0 {
                  compatible = "microchip,mcp2515";
                  reg = <0>;
                  spi-max-frequency = <10000000>; /* 10 MHz */
                  interrupt-parent = <&gpio>;
                  interrupts = <25 0x8>; /* GPIO 25, IRQ_TYPE_LEVEL_LOW (0x8) */
                  oscillator-frequency = <16000000>; /* 16 MHz crystal */
                  status = "okay";
                };
              };
            };

            fragment@1 {
              target = <&gpio>;
              __overlay__ {
                can0_pins: can0_pins {
                  brcm,pins = <25>;
                  brcm,function = <0>; /* Input */
                };
              };
            };
          };
        '';
      }

      # MCP2515 CAN1 controller on SPI0.1
      {
        dtsText = ''
          /dts-v1/;
          /plugin/;

          / {
            compatible = "brcm,bcm2711";

            fragment@0 {
              target = <&spi0>;
              __overlay__ {
                status = "okay";
                #address-cells = <1>;
                #size-cells = <0>;

                /* Second MCP2515 CAN controller */
                mcp2515_can1: mcp2515@1 {
                  compatible = "microchip,mcp2515";
                  reg = <1>;
                  spi-max-frequency = <10000000>; /* 10 MHz */
                  interrupt-parent = <&gpio>;
                  interrupts = <24 0x8>; /* GPIO 24, IRQ_TYPE_LEVEL_LOW (0x8) */
                  oscillator-frequency = <16000000>; /* 16 MHz crystal */
                  status = "okay";
                };
              };
            };

            fragment@1 {
              target = <&gpio>;
              __overlay__ {
                can1_pins: can1_pins {
                  brcm,pins = <24>;
                  brcm,function = <0>; /* Input */
                };
              };
            };
          };
        '';
        name = "mcp2515-can1";
      }
    ];
  };

  # Removed redundant kernelModules and extraModprobeConfig as they are already handled in boot.nix

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
    startLimitIntervalSec = 30;
    startLimitBurst = 5;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStartPre = "${pkgs.coreutils}/bin/sleep 3"; # Increased delay for module initialization
      ExecStart = ''
        ${pkgs.bash}/bin/bash -c '
          # More robust CAN interface setup with retry
          for i in {1..5}; do
            echo "Attempt $i to bring up can0..."
            if ${pkgs.iproute2}/bin/ip link set can0 up type can bitrate 500000 restart-ms 100; then
              echo "can0 interface brought up successfully"
              exit 0
            fi
            echo "Failed to bring up can0, retrying in 1 second..."
            sleep 1
          done
          echo "Failed to bring up can0 after 5 attempts"
          exit 1
        '
      '';
      ExecStop = "${pkgs.iproute2}/bin/ip link set can0 down";
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };

  systemd.services."can1" = {
    description = "CAN1 Interface";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-modules-load.service" "can0.service" ];
    requires = [ "dev-spi0.device" ];
    startLimitIntervalSec = 30;
    startLimitBurst = 5;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStartPre = "${pkgs.coreutils}/bin/sleep 3"; # Increased delay for module initialization
      ExecStart = ''
        ${pkgs.bash}/bin/bash -c '
          # More robust CAN interface setup with retry
          for i in {1..5}; do
            echo "Attempt $i to bring up can1..."
            if ${pkgs.iproute2}/bin/ip link set can1 up type can bitrate 500000 restart-ms 100; then
              echo "can1 interface brought up successfully"
              exit 0
            fi
            echo "Failed to bring up can1, retrying in 1 second..."
            sleep 1
          done
          echo "Failed to bring up can1 after 5 attempts"
          exit 1
        '
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
