{ config, pkgs, lib, ... }: {
  # CAN-related kernel modules
  boot.kernelModules = [
    "spi-bcm2835"  # Load SPI driver first
    "mcp251x"      # Then the CAN driver
    "can"
    "can_raw"
    "can_dev"
  ];

  # Raspberry Pi specific configuration
  hardware.raspberry-pi."4".fkms-3d.enable = true;
  
  # Enable SPI via dtparams in boot config (specific to Raspberry Pi)
  hardware.deviceTree.enable = true;
  
  # Force enable SPI in kernel parameters
  boot.kernelParams = [ "spi=on" ];

  # Create a more explicit device tree overlay for SPI and CAN controllers
  hardware.deviceTree.overlays = [
    {
      name = "enable-spi-mcp2515";
      dtsText = ''
        /dts-v1/;
        /plugin/;

        / {
          compatible = "brcm,bcm2835";
          
          fragment@0 {
            target = <&spi0>;
            __overlay__ {
              status = "okay";
              
              spidev@0 {
                compatible = "spidev";
                reg = <0>;
                #address-cells = <1>;
                #size-cells = <0>;
                spi-max-frequency = <1000000>;
                status = "okay";
              };
              
              spidev@1 {
                compatible = "spidev";
                reg = <1>;
                #address-cells = <1>;
                #size-cells = <0>;
                spi-max-frequency = <1000000>;
                status = "okay";
              };
            };
          };
          
          fragment@1 {
            target = <&spi0>;
            __overlay__ {
              #address-cells = <1>;
              #size-cells = <0>;
              
              mcp2515@0 {
                compatible = "microchip,mcp2515";
                reg = <0>;
                spi-max-frequency = <10000000>;
                interrupt-parent = <&gpio>;
                interrupts = <25 8>; /* active-low */
                oscillator-frequency = <16000000>;
                status = "okay";
              };
              
              mcp2515@1 {
                compatible = "microchip,mcp2515";
                reg = <1>;
                spi-max-frequency = <10000000>;
                interrupt-parent = <&gpio>;
                interrupts = <24 8>; /* active-low */
                oscillator-frequency = <16000000>;
                status = "okay";
              };
            };
          };
        };
      '';
    }
  ];

  # This setting might help by creating a /boot/config.txt on Raspberry Pi
  hardware.raspberry-pi.apply-overlays-dtmerge.enable = true;
  hardware.raspberry-pi.config = ''
    dtparam=spi=on
  '';

  # SystemD services to bring up CAN interfaces
  systemd.services."can0" = {
    description = "CAN0 Interface";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-modules-load.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStartPre = "${pkgs.coreutils}/bin/sleep 2";  # Add delay to ensure device appears
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
      ExecStartPre = "${pkgs.coreutils}/bin/sleep 2";  # Add delay to ensure device appears
      ExecStart = "${pkgs.iproute2}/bin/ip link set can1 up type can bitrate 500000";
      ExecStop = "${pkgs.iproute2}/bin/ip link set can1 down";
    };
  };
}
