{ config, pkgs, lib, ... }:

{
  users.users.ryan = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    shell = pkgs.fish;
    hashedPasswordFile = config.sops.secrets.ryan_password.path;
    openssh.authorizedKeys.keyFiles = [
      config.sops.secrets.ryan_ssh_public_key.path
    ];
  };
}
