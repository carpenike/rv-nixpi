{ config, pkgs, lib, ... }:

{
  hardware.enableRedistributableFirmware = true;

  # Enable device tree processing for DTBs matching the standard Pi 4.
  hardware.deviceTree = {
    enable = true;
    filter = "*-rpi-4-*.dtb";

    # Simple overlays that exactly match what works in Debian
    overlays = [
      {
        name = "spi-on";
        dtsText = ''
          /dts-v1/;
          /plugin/;
          
          / {
            compatible = "brcm,bcm2711";
            
            fragment@0 {
              target = <&spi0>;
              __overlay__ {
                status = "okay";
              };
            };
          };
        '';
      }
      
      {
        name = "mcp2515-can0";
        dtsText = ''
          /dts-v1/;
          /plugin/;
          
          / {
            compatible = "brcm,bcm2711";
            
            fragment@0 {
              target = <&gpio>;
              __overlay__ {
                can0_pins: can0_pins {
                  brcm,pins = <25>;
                  brcm,function = <0>; /* Input */
                  brcm,pull = <2>; /* Pull-up */
                };
              };
            };
            
            fragment@1 {
              target = <&spi0>;
              __overlay__ {
                /* needed to avoid dtc warning */
                #address-cells = <1>;
                #size-cells = <0>;
                
                can0: mcp2515@0 {
                  reg = <0>;
                  compatible = "microchip,mcp2515";
                  pinctrl-names = "default";
                  pinctrl-0 = <&can0_pins>;
                  spi-max-frequency = <10000000>;
                  interrupt-parent = <&gpio>;
                  interrupts = <25 8>; /* active low */
                  clocks = <&can0_osc>;
                  status = "okay";
                  
                  can0_osc: can0_osc {
                    compatible = "fixed-clock";
                    #clock-cells = <0>;
                    clock-frequency = <16000000>;
                  };
                };
              };
            };
          };
        '';
      }
      
      {
        name = "mcp2515-can1";
        dtsText = ''
          /dts-v1/;
          /plugin/;
          
          / {
            compatible = "brcm,bcm2711";
            
            fragment@0 {
              target = <&gpio>;
              __overlay__ {
                can1_pins: can1_pins {
                  brcm,pins = <24>;
                  brcm,function = <0>; /* Input */
                  brcm,pull = <2>; /* Pull-up */
                };
              };
            };
            
            fragment@1 {
              target = <&spi0>;
              __overlay__ {
                /* needed to avoid dtc warning */
                #address-cells = <1>;
                #size-cells = <0>;
                
                can1: mcp2515@1 {
                  reg = <1>;
                  compatible = "microchip,mcp2515";
                  pinctrl-names = "default";
                  pinctrl-0 = <&can1_pins>;
                  spi-max-frequency = <10000000>;
                  interrupt-parent = <&gpio>;
                  interrupts = <24 8>; /* active low */
                  clocks = <&can1_osc>;
                  status = "okay";
                  
                  can1_osc: can1_osc {
                    compatible = "fixed-clock";
                    #clock-cells = <0>;
                    clock-frequency = <16000000>;
                  };
                };
              };
            };
          };
        '';
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
      ExecStartPre = "${pkgs.coreutils}/bin/sleep 3";
      # Fixed the quoting issue by using a single multiline string
      ExecStart = pkgs.writeShellScript "setup-can0" ''
        #!/bin/sh
        # Robust CAN interface setup with retry
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
      ExecStartPre = "${pkgs.coreutils}/bin/sleep 3";
      # Fixed the quoting issue by using a single multiline string
      ExecStart = pkgs.writeShellScript "setup-can1" ''
        #!/bin/sh
        # Robust CAN interface setup with retry
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
