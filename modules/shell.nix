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
      set -l hostname (hostname)
      set -l kernel_version (uname -r)

      # Define colors (vibrant for dark backgrounds)
      set -l color_host brcyan  # Bright Cyan for hostname
      set -l color_kernel brgreen # Bright Green for kernel
      set -l color_system bryellow # Bright Yellow for system label
      set -l color_reset normal

      # Print formatted greeting
      printf "Welcome to %s%s%s\n" (set_color $color_host) $hostname (set_color $color_reset)
      printf "  %-8s %s%s%s\n" "Kernel:" (set_color $color_kernel) $kernel_version (set_color $color_reset)
      printf "  %-8s %s%s%s\n" "System:" (set_color $color_system) $system_label (set_color $color_reset)
    end
  '';

  # Optional: Set fish as the default shell system-wide (you already set it per user)
  # users.defaultUserShell = pkgs.fish;
}
