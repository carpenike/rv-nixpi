{ config, pkgs, lib, ... }:
{
  services.openssh = {
    enable = true;
    hostKeys = [
      {
        path = "/etc/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
    ];
  };

  environment.etc = {
    "ssh/ssh_host_ed25519_key" = {
      text = config.sops.secrets.ssh_host_ed25519_key.contents;
      mode = "0400";
    };
    "ssh/ssh_host_ed25519_key.pub" = {
      text = config.sops.secrets.ssh_host_ed25519_key_pub.contents;
      mode = "0644";
    };
  };
}
