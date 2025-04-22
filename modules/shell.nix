{ config, pkgs, lib, ... }:

{
  environment.systemPackages = with pkgs; [
    fish
  ];

  programs.fish.enable = true;

  # Custom greeting message
  programs.fish.interactiveShellInit = ''
    function fish_greeting
      set -l system_path (readlink /run/current-system)
      set -l system_label (basename $system_path)
      echo "Welcome to $(hostname). Kernel: $(uname -r). System: $system_label"
    end
  '';

  # Optional: Set fish as the default shell system-wide (you already set it per user)
  # users.defaultUserShell = pkgs.fish;
}
