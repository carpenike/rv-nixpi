{ config, pkgs, lib, ... }:

{
  hardware.enableRedistributableFirmware = true;

  # Enable static merging of device tree overlays
  hardware.raspberry-pi."4".apply-overlays-dtmerge.enable = true;
  hardware.raspberry-pi."4".apply-overlays-dtmerge.overlays.rpi4-cpu-revision.enable = false;


  # Create a device tree overlay for SPI and CAN controllers
  hardware.deviceTree.overlays = [
    {
      name = "enable-spi-mcp2515";
      dtsText = ''
        /dts-v1/;
        /plugin/;

        / {
          // Removed the "compatible" property from here

          fragment@0 {
            target = <&spi0>;
            __overlay__ {
              status = "okay";
            };
          };

          fragment@1 {
            target = <&spi0>;
            __overlay__ {
              #address-cells = <2>;
              #size-cells = <1>;

              mcp2515@0 {
                compatible = "microchip,mcp2515";
                reg = <0 0 0>;
                spi-max-frequency = <10000000>;
                interrupt-parent = <&gpio>;
                interrupts = <25 8>;
                oscillator-frequency = <16000000>;
                status = "okay";
              };

              mcp2515@1 {
                compatible = "microchip,mcp2515";
                reg = <0 1 0>;
                spi-max-frequency = <10000000>;
                interrupt-parent = <&gpio>;
                interrupts = <24 8>;
                oscillator-frequency = <16000000>;
                status = "okay";
              };
            };
          };
        };
      '';
    }
  ];

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
