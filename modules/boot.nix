{ config, pkgs, ... }:
{
  boot = {
    loader.generic-extlinux-compatible.enable = true;

    kernelModules = [ "dwc2" "g_serial" ];
    initrd.kernelModules = [ "dwc2" ];

    extraModprobeConfig = ''
      options g_serial use_acm=1
    '';

    kernelParams = [
      "modules-load=dwc2,g_serial"
      "console=ttyGS0,115200"
    ];
  };

  # 👇 Move this outside of `boot`
  system.extraSystemBuilderCmds = ''
    mkdir -p $out/firmware
    echo "[pi4]" > $out/firmware/config.txt
    echo "kernel=u-boot-rpi4.bin" >> $out/firmware/config.txt
    echo "enable_gic=1" >> $out/firmware/config.txt
    echo "armstub=armstub8-gic.bin" >> $out/firmware/config.txt
    echo "" >> $out/firmware/config.txt
    echo "[all]" >> $out/firmware/config.txt
    echo "arm_64bit=1" >> $out/firmware/config.txt
    echo "enable_uart=1" >> $out/firmware/config.txt
    echo "dtoverlay=dwc2" >> $out/firmware/config.txt
  '';
}
