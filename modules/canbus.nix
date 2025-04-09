{ config, pkgs, lib, ... }: {
  # Removed the enableAllFirmware line since it conflicts with enableRedistributableFirmware
  # hardware.enableAllFirmware is not needed since you have allowUnfree=true
  
  # Raspberry Pi 4 specific configuration for 3D acceleration
  hardware.raspberry-pi."4".fkms-3d.enable = true;
  
  # Device tree configuration
  hardware.deviceTree = {
    enable = true;
    # Removed the filter line that was causing conflicts
    # filter = "bcm2711-rpi-4-*.dtb";
    
    # Use this simple overlay to ensure SPI is enabled
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
    ];
  };

  # CAN-related kernel modules (will be merged with those in boot.nix)
  boot.kernelModules = [
    "mcp251x"
    "can"
    "can_raw"
    "can_dev"
    "spi_bcm2835"
  ];

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
