{ config, pkgs, lib, ... }: {
  # Required kernel modules
  boot = {
    kernelModules = [
      "mcp251x"
      "can"
      "can_raw"
      "can_dev"
      "spi_bcm2835"
    ];
  };

  # Enable SPI interface on Pi
  hardware.spi.enable = true;

  hardware.deviceTree = {
    enable = true;

    overlays = [
      {
        name = "mcp2515-can0";
        dtsText = ''
          /dts-v1/;
          /plugin/;

          / {
            compatible = "brcm,bcm2835";

            fragment@0 {
              target-path = "/soc/spi@7e204000";
              __overlay__ {
                can0: mcp2515@0 {
                  compatible = "microchip,mcp2515";
                  reg = <0>; // CE0
                  spi-max-frequency = <10000000>;
                  interrupt-parent = <&gpio>;
                  interrupts = <25 0x2>; // falling edge
                  status = "okay";
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
            compatible = "brcm,bcm2835";

            fragment@0 {
              target-path = "/soc/spi@7e204000";
              __overlay__ {
                can1: mcp2515@1 {
                  compatible = "microchip,mcp2515";
                  reg = <1>; // CE1
                  spi-max-frequency = <10000000>;
                  interrupt-parent = <&gpio>;
                  interrupts = <24 0x2>; // falling edge
                  status = "okay";
                };
              };
            };
          };
        '';
      }
    ];
  };

  # Optional: bring up can interfaces at boot with bitrate
  systemd.services."can0" = {
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.iproute2}/bin/ip link set can0 up type can bitrate 500000";
      ExecStop = "${pkgs.iproute2}/bin/ip link set can0 down";
      Restart = "on-failure";
    };
  };

  systemd.services."can1" = {
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.iproute2}/bin/ip link set can1 up type can bitrate 500000";
      ExecStop = "${pkgs.iproute2}/bin/ip link set can1 down";
      Restart = "on-failure";
    };
  };
}
