{ config, pkgs, lib, ... }:

{
  hardware.enableRedistributableFirmware = true;

  # Enable device tree processing for DTBs matching the standard Pi 4.
  hardware.deviceTree = {
    enable = true;
    filter = "*-rpi-4-*.dtb";

  };

  # Disable manual deviceTree overlays (now handled by boot.firmware.raspberryPi)
  hardware.deviceTree = lib.mkForce { enable = false; overlays = []; };

  # Create an SPI group for permissions.
  users.groups.spi = {};

  # Set up udev rules for spidev devices
  services.udev.extraRules = ''
    SUBSYSTEM=="spidev", KERNEL=="spidev0.*", GROUP="spi", MODE="0660"
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
      ExecStart = pkgs.writeShellScript "setup-can0" ''
        #!/bin/sh
        ${pkgs.iproute2}/bin/ip link set can0 down
        sleep 1
        for i in {1..5}; do
          if ${pkgs.iproute2}/bin/ip link set can0 up type can bitrate 500000 restart-ms 100; then
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
      ExecStart = pkgs.writeShellScript "setup-can1" ''
        #!/bin/sh
        ${pkgs.iproute2}/bin/ip link set can1 down
        sleep 1
        for i in {1..5}; do
          if ${pkgs.iproute2}/bin/ip link set can1 up type can bitrate 500000 restart-ms 100; then
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
    python3Packages.spidev
  ];
}
