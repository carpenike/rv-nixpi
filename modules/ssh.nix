{ config, pkgs, lib, ... }:
{
  services.openssh = {
    enable = true;
    hostKeys = [
      {
        path = config.sops.secrets.ssh_host_ed25519_key.path;
        type = "ed25519";
      }
    ];
  };

  environment.etc = {
    "ssh/ssh_host_ed25519_key" = {
      text = builtins.readFile config.sops.secrets.ssh_host_ed25519_key.path;
      mode = "0400";
    };
    "ssh/ssh_host_ed25519_key.pub" = {
      text = builtins.readFile config.sops.secrets.ssh_host_ed25519_key_pub.path;
      mode = "0644";
    };
  };
}
