{ ... }: {
  system.stateVersion = "24.11";
  nix.settings = {
    download-buffer-size = 33554432; # 32 MiB
  };
}
