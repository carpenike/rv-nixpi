{ config, pkgs, lib, ... }:

{
  environment.systemPackages = with pkgs; [
    fish
  ];

  programs.fish = {
    enable = true;

    interactiveShellInit = ''
      if test -f /etc/motd_age_notice
        cat /etc/motd_age_notice
      end
    '';
  };

  # Optional: Set fish as the default shell system-wide (you already set it per user)
  # users.defaultUserShell = pkgs.fish;
}
