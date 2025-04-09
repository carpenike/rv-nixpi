{ config, pkgs, ... }:
#{ config, pkgs, rvcApp, ... }:

{
  environment.systemPackages = with pkgs; [
    # rvcApp.package
    pkgs.can-utils
    pkgs.fish
    pkgs.vim
    pkgs.git
    pkgs.fbterm
    pkgs.kmscon
    pkgs.kbd
  ];
}
