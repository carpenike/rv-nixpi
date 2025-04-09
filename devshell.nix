{ pkgs }:

pkgs.mkShell {
  name = "rv-nixpi-devshell";

  packages = with pkgs; [
    nix
    git
    sops
    ssh-to-age
    zstd
    coreutils
    util-linux
    bmap-tools
  ];

  shellHook = ''
    export FLAKE=$(git rev-parse --show-toplevel)

    echo "🔧 Devshell ready!"
    echo "  ➤ To build SD image:    build-image"
    echo "  ➤ To write image to SD: write-image /dev/sdX"
    echo ""

    build-image() {
      nix build --extra-experimental-features nix-command --extra-experimental-features flakes \
        "$FLAKE#packages.aarch64-linux.sdcard" --impure
    }

    write-image() {
      if [ -z "$1" ]; then
        echo "❌ Usage: write-image /dev/sdX"
        return 1
      fi
      IMG=$(ls -t result/sd-image/*.img.zst | head -n1)
      echo "📦 Writing image $IMG to $1..."
      sudo zstd -d --stdout "$IMG" | sudo dd of="$1" bs=4M status=progress oflag=sync
    }
  '';
}
