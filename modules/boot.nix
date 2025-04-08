{ config, pkgs, lib, ... }:

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

  # Inject firmware config (config.txt) during image build
  system.extraSystemBuilderCmds = ''
    mkdir -p $out/firmware
    cat <<EOF > $out/firmware/config.txt
[pi3]
kernel=u-boot-rpi3.bin

[pi02]
kernel=u-boot-rpi3.bin

[pi4]
kernel=u-boot-rpi4.bin
enable_gic=1
armstub=armstub8-gic.bin

disable_overscan=1
arm_boost=1

[cm4]
otg_mode=1

[all]
arm_64bit=1
enable_uart=1
avoid_warnings=1
dtoverlay=dwc2
EOF
  '';
}
