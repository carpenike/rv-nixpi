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
      set -l current_hostname (hostname)

      # Performance Metrics
      # Use awk to parse uptime output for the 1-minute load average (Reverted to awk)
      set -l load_avg (uptime | command awk -F 'load average: ' '{print $2}' | command awk -F, '{print $1}' | command string trim)
      set -l mem_info (free -h | command awk '/^Mem:/ {print $3" / "$2}') # Used / Total RAM
      set -l disk_usage (df -h / | command awk 'NR==2 {print $5}') # Root partition usage %

      # Define colors (vibrant for dark backgrounds)
      set -l color_host brcyan
      set -l color_kernel brgreen
      set -l color_system bryellow
      set -l color_load brmagenta
      set -l color_mem brblue
      set -l color_disk brred
      set -l color_reset normal

      # Define box characters
      set -l box_tl "╭"
      set -l box_tr "╮"
      set -l box_bl "╰"
      set -l box_br "╯"
      set -l box_h "─"
      set -l box_v "│"

      # Define dimensions (adjust width as needed)
      set -l width 85 # Increased width
      set -l inner_width (math $width - 4) # Width inside the box borders │  ...  │

      # Create horizontal line
      set -l h_line (string repeat -n (math $width - 2) $box_h)

      # --- Prepare content strings with colors ---
      set -l welcome_content "Welcome to "(set_color $color_host)$current_hostname(set_color $color_reset)
      set -l kernel_content "  Kernel: "(set_color $color_kernel)$kernel_version(set_color $color_reset)
      set -l system_content "  System: "(set_color $color_system)$system_label(set_color $color_reset)
      set -l load_content "  Load:   "(set_color $color_load)$load_avg(set_color $color_reset)
      set -l memory_content "  Memory: "(set_color $color_mem)$mem_info(set_color $color_reset)
      set -l disk_content "  Disk /: "(set_color $color_disk)$disk_usage(set_color $color_reset)

      # --- Prepare plain text versions for length calculation ---
      set -l welcome_plain "Welcome to $current_hostname"
      set -l kernel_plain "  Kernel: $kernel_version"
      set -l system_plain "  System: $system_label"
      set -l load_plain "  Load:   $load_avg"
      set -l memory_plain "  Memory: $mem_info"
      set -l disk_plain "  Disk /: $disk_usage"

      # --- Print Box ---
      # Top border
      printf "%s%s%s\n" $box_tl $h_line $box_tr

      # Welcome line
      set -l welcome_padding (string repeat -n (math $inner_width - (string length $welcome_plain)) " ")
      printf "%s %s%s %s\n" $box_v $welcome_content $welcome_padding $box_v

      # Kernel line
      set -l kernel_padding (string repeat -n (math $inner_width - (string length $kernel_plain)) " ")
      printf "%s %s%s %s\n" $box_v $kernel_content $kernel_padding $box_v

      # System line
      set -l system_padding (string repeat -n (math $inner_width - (string length $system_plain)) " ")
      printf "%s %s%s %s\n" $box_v $system_content $system_padding $box_v

      # Load line
      set -l load_padding (string repeat -n (math $inner_width - (string length $load_plain)) " ")
      printf "%s %s%s %s\n" $box_v $load_content $load_padding $box_v

      # Memory line
      set -l memory_padding (string repeat -n (math $inner_width - (string length $memory_plain)) " ")
      printf "%s %s%s %s\n" $box_v $memory_content $memory_padding $box_v

      # Disk line
      set -l disk_padding (string repeat -n (math $inner_width - (string length $disk_plain)) " ")
      printf "%s %s%s %s\n" $box_v $disk_content $disk_padding $box_v

      # Bottom border
      printf "%s%s%s\n" $box_bl $h_line $box_br
    end
  '';

  # Optional: Set fish as the default shell system-wide (you already set it per user)
  # users.defaultUserShell = pkgs.fish;
}
