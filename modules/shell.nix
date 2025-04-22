{ config, pkgs, lib, ... }:

{
  environment.systemPackages = with pkgs; [
    fish
  ];

  programs.fish.enable = true;

  # Custom greeting message
  programs.fish.interactiveShellInit = ''
    function fish_greeting
      # System Info
      set -l system_path (readlink /run/current-system)
      set -l system_label (basename $system_path)
      set -l kernel_version (uname -r)

      # Performance Metrics
      set -l load_avg (uptime | command string split -r -m1 'load average: ' | command string split ',' --)[1] # 1-minute load average
      set -l mem_info (free -h | command awk '/^Mem:/ {print $3" / "$2}') # Used / Total RAM
      set -l disk_usage (df -h / | command awk 'NR==2 {print $5}') # Root partition usage %

      # Define colors (vibrant for dark backgrounds)
      set -l color_host brcyan
      set -l color_kernel brgreen
      set -l color_system bryellow
      set -l color_load brmagenta # Bright Magenta for load
      set -l color_mem brblue    # Bright Blue for memory
      set -l color_disk brred     # Bright Red for disk
      set -l color_reset normal

      # Print formatted greeting
      printf "Welcome to %s%s%s\n" (set_color $color_host) (hostname) (set_color $color_reset)
      printf "  %-8s %s%s%s\n" "Kernel:" (set_color $color_kernel) $kernel_version (set_color $color_reset)
      printf "  %-8s %s%s%s\n" "System:" (set_color $color_system) $system_label (set_color $color_reset)
      printf "  %-8s %s%s%s\n" "Load:" (set_color $color_load) $load_avg (set_color $color_reset)
      printf "  %-8s %s%s%s\n" "Memory:" (set_color $color_mem) $mem_info (set_color $color_reset)
      printf "  %-8s %s%s%s\n" "Disk /:" (set_color $color_disk) $disk_usage (set_color $color_reset)
    end
  '';

  # Optional: Set fish as the default shell system-wide (you already set it per user)
  # users.defaultUserShell = pkgs.fish;
}
