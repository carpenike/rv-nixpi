{ config, pkgs, lib, ... }:

{
  users.users.ryan = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    shell = pkgs.fish;
    passwordFile = config.sops.secrets.ryan_password.path;
    openssh.authorizedKeys.keys = [
      (builtins.readFile config.sops.secrets.ryan_ssh_public_key.path)
    ];
  };
}
