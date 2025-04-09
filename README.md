# rv-nixpi
NixOS Configuration for my RV's Raspberry Pi 4

# Useful commands

## Create age.key env variable
```bash
set -gx AGE_BOOTSTRAP_KEY (tail -n +3 secrets/age.key | string join '\n')
```

## Updating ssh-age when host key changes
```bash
nix-shell -p ssh-to-age --run 'cat /etc/ssh/ssh_host_ed25519_key.pub | ssh-to-age'
```

## Update Config on Running System
```bash
sudo nixos-rebuild switch --flake github:carpenike/rv-nixpi#nixpi --option accept-flake-config true --refresh
```

## Create New Image
```bash
nix build --extra-experimental-features nix-command --extra-experimental-features flakes .#packages.aarch64-linux.sdcard --impure
```

## Write Image to SDCard
```bash
sudo zstd -d --stdout result/sd-image/nixos-sd-image-24.11.20250406.a880f49-aarch64-linux.img.zst | sudo dd of=/dev/sdb bs=4M status=progress oflag=sync
```
