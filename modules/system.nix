{ ... }:

{
  # Build version: 2025-04-17-1  # Update this to force a rebuild
  system.stateVersion = "24.11";

  time.timeZone = "America/New_York";

  nix.settings = {
    download-buffer-size = 33554432; # 32 MiB
  };

  nixpkgs.config.allowUnfree = true;
}
