{ config, pkgs, lib, ... }: {
  # Raspberry Pi 4 specific configuration for 3D acceleration
  hardware.raspberry-pi."4".fkms-3d.enable = true;
  
  # Device tree configuration
  hardware.deviceTree = {
    enable = true;
    
    # Use proper overlays with overlay package
    overlays = [
      {
        name = "spi-on";
        dtsText = ''
          /dts-v1/;
          /plugin/;
          
          / {
            compatible = "brcm,bcm2835";
            
            fragment@0 {
              target = <&spi>;
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
            compatible = "brcm,bcm2835";
            
            fragment@0 {
              target = <&spi>;
              __overlay__ {
                status = "okay";
                
                mcp2515@0 {
                  compatible = "microchip,mcp2515";
                  reg = <0>;
                  spi-max-frequency = <10000000>;
                  interrupt-parent = <&gpio>;
                  interrupts = <25 8>; /* active-low */
                  oscillator-frequency = <16000000>;
                  status = "okay";
                };
              };
            };
            
            fragment@1 {
              target-path = "/";
              __overlay__ {
                can0_osc: can0_osc {
                  compatible = "fixed-clock";
                  #clock-cells = <0>;
                  clock-frequency = <16000000>;
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
              target = <&spi>;
              __overlay__ {
                status = "okay";
                
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
            
            fragment@1 {
              target-path = "/";
              __overlay__ {
                can1_osc: can1_osc {
                  compatible = "fixed-clock";
                  #clock-cells = <0>;
                  clock-frequency = <16000000>;
                };
              };
            };
          };
        '';
      }
    ];
  };

  # CAN-related kernel modules
  boot.kernelModules = [
    "mcp251x"
    "can"
    "can_raw"
    "can_dev"
    "spi_bcm2835"
  ];

  # And now we also need to update boot.nix to remove the dtoverlay parameters
  # that aren't being recognized correctly

  # SystemD services to bring up CAN interfaces
  systemd.services."can0" = {
    description = "CAN0 Interface";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-modules-load.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.iproute2}/bin/ip link set can0 up type can bitrate 500000";
      ExecStop = "${pkgs.iproute2}/bin/ip link set can0 down";
    };
  };

  systemd.services."can1" = {
    description = "CAN1 Interface";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-modules-load.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.iproute2}/bin/ip link set can1 up type can bitrate 500000";
      ExecStop = "${pkgs.iproute2}/bin/ip link set can1 down";
    };
  };
}
