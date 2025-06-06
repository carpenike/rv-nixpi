{ ... }:

{
  system.stateVersion = "24.11";

  time.timeZone = "America/New_York";

  nix.settings = {
    download-buffer-size = 33554432; # 32 MiB
  };

  # nixpkgs.config.allowUnfree = true;

  # services.rvc2api.debugTools.enable = true; # Removed: Option moved to flake.nix
}
