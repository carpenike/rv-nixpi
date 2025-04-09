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

    # Add custom commands directory to PATH
    export DEV_BIN_DIR="$PWD/.devshell/bin"
    mkdir -p "$DEV_BIN_DIR"

    # build-image command
    cat > "$DEV_BIN_DIR/build-image" <<EOF
#!/usr/bin/env bash
nix build --extra-experimental-features nix-command --extra-experimental-features flakes "\$FLAKE#packages.aarch64-linux.sdcard" --impure
EOF

    # write-image command
    cat > "$DEV_BIN_DIR/write-image" <<'EOF'
#!/usr/bin/env bash
if [ -z "$1" ]; then
  echo "❌ Usage: write-image /dev/sdX"
  exit 1
fi
IMG=$(ls -t result/sd-image/*.img.zst | head -n1)
echo "📦 Writing image $IMG to $1..."
sudo zstd -d --stdout "$IMG" | sudo dd of="$1" bs=4M status=progress oflag=sync
EOF

    chmod +x "$DEV_BIN_DIR"/*

    export PATH="$DEV_BIN_DIR:$PATH"

    if [[ -f "secrets/age.key" ]]; then
      export AGE_BOOTSTRAP_KEY="$(< secrets/age.key)"
      echo "🔑 AGE_BOOTSTRAP_KEY loaded from secrets/age.key"
    fi

    echo "🔧 Devshell ready!"
    echo "  ➤ To build SD image:    build-image"
    echo "  ➤ To write image to SD: write-image /dev/sdX"
    echo ""
  '';
}
