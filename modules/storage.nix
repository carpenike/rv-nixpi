{ config, pkgs, ... }:
{
  fileSystems."/tmp" = {
    device = "tmpfs";
    fsType = "tmpfs";
    options = [ "nosuid" "nodev" "mode=1777" ];
  };

  fileSystems."/var/tmp" = {
    device = "tmpfs";
    fsType = "tmpfs";
    options = [ "nosuid" "nodev" "mode=1777" ];
  };

  # The tmpfs entries for /var/log and /var/cache will be replaced by SSD mounts below.

  # Configuration for the mSATA SSD
  # IMPORTANT:
  # 1. Replace "/dev/disk/by-id/your-msata-ssd-id-part1" below with the actual
  #    persistent device path for your mSATA SSD partition.
  #    (e.g., find it with `ls -la /dev/disk/by-id/` after identifying your disk).
  # 2. This configuration assumes you have formatted the SSD partition as BTRFS
  #    and created subvolumes named "@var_log" and "@var_cache" on it, as described
  #    in the instructions prior to this code block.
  #
  # If you choose to use a different filesystem (e.g., ext4):
  # - You would typically need separate partitions for /var/log and /var/cache
  #   if you want to mount them directly as shown.
  # - Alternatively, mount a single ext4 partition to a generic path (e.g., /mnt/ssd_data)
  #   and then use bind mounts or symlinks for /var/log and /var/cache. This would
  #   require additional NixOS configuration beyond this file (e.g., systemd units
  #   or a module like `impermanence`).

  fileSystems."/var/log" = {
    device = "/dev/disk/by-id/ata-TS256GMSA230S_J268760585-part1"; # <-- Updated SSD ID
    fsType = "btrfs";
    options = [ "defaults" "nofail" "subvol=@var_log" "compress=zstd" ];
    # 'nofail' allows the system to boot even if the SSD is not found.
    # 'compress=zstd' is generally recommended for BTRFS for good compression.
  };

  fileSystems."/var/cache" = {
    device = "/dev/disk/by-id/ata-TS256GMSA230S_J268760585-part1"; # <-- Updated SSD ID (same partition as /var/log)
    fsType = "btrfs";
    options = [ "defaults" "nofail" "subvol=@var_cache" "compress=zstd" ];
  };

  # If your application uses a specific directory for ephemeral data,
  # you could also mount that as tmpfs:
  #
  # fileSystems."/var/lib/myapp/cache" = {
  #   device = "tmpfs";
  #   fsType = "tmpfs";
  #   options = [ "nosuid" "nodev" "mode=0755" ];
  # };
}
