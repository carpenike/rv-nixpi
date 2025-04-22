{ config, pkgs, ... }:
#{ config, pkgs, rvcApp, ... }:

{
  environment.systemPackages = with pkgs; [
    # rvcApp.package
    pkgs.fish
    pkgs.vim
    pkgs.git
    pkgs.fbterm
    pkgs.kmscon
    pkgs.kbd
    pkgs.wget
    pkgs.tmux

    (pkgs.writeShellScriptBin "update-nix" ''
      #!/usr/bin/env bash
      set -euo pipefail

      echo "📦 Updating system from remote flake..."

      sudo nixos-rebuild switch \
        --flake github:carpenike/rv-nixpi#nixpi \
        --option accept-flake-config true \
        --refresh \
        --show-trace
    '')
  ];
}
