{ config, pkgs, lib, ... }: {
  boot = {
    kernelModules = [ "mcp251x" "can" "can_raw" "can_dev" "spi_bcm2835" ];
    extraModulePackages = [ ];
  };

  hardware.deviceTree.overlays = [
    {
      name = "mcp2515-can0";
      dtsText = ''
        /dts-v1/;
        /plugin/;

        / {
          compatible = "brcm,bcm2835";

          fragment@0 {
            target = <&spi0>;
            __overlay__ {
              can0: mcp2515@0 {
                compatible = "microchip,mcp2515";
                reg = <0>; // CE0
                spi-max-frequency = <10000000>;
                interrupt-parent = <&gpio>;
                interrupts = <25 0x2>; // GPIO25, falling edge
                status = "okay";
              };
            };
          };

          fragment@1 {
            target = <&gpio>;
            __overlay__ {
              pinctrl-names = "default";
              pinctrl-0 = <&can0_pins>;
            };
          };

          __overrides__ {
            spi0 = "/soc/spi@7e204000";
            gpio = "/soc/gpio@7e200000";
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
            target = <&spi0>;
            __overlay__ {
              can1: mcp2515@1 {
                compatible = "microchip,mcp2515";
                reg = <1>; // CE1
                spi-max-frequency = <10000000>;
                interrupt-parent = <&gpio>;
                interrupts = <24 0x2>; // GPIO24, falling edge
                status = "okay";
              };
            };
          };

          fragment@1 {
            target = <&gpio>;
            __overlay__ {
              pinctrl-names = "default";
              pinctrl-0 = <&can1_pins>;
            };
          };

          __overrides__ {
            spi0 = "/soc/spi@7e204000";
            gpio = "/soc/gpio@7e200000";
          };
        };
      '';
    }
  ];
}
