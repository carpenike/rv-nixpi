{ config, pkgs, lib, ... }:
let
  userSecrets = config.sops.secrets or {};
in {
  users.users = {
    ryan = {
      isNormalUser = true;
      # Reference the hashed password from the secrets file.
      password = userSecrets.ryan_password;
      extraGroups = [ "wheel" ];
      openssh.authorizedKeys.keys = [
        userSecrets.ryan_ssh_public_key
      ];
      shell = pkgs.fish;
    };
  };
}
