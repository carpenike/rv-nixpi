{ config, pkgs, lib, ... }:

{
  users.users.ryan = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    shell = pkgs.fish;
    hashedPasswordFile = config.sops.secrets.ryan_password.path;

    openssh.authorizedKeys.keys = [
      (builtins.readFile ../../config/ssh/ryan.pub)
    ];
  };
}
