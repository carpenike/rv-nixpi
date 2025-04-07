{ config, pkgs, lib, ... }:
{
  services.openssh = {
    generateHostKeys = false;
    hostKeys = [ "/etc/ssh/ssh_host_ed25519_key" ];
  };

  environment.etc = {
    "ssh/ssh_host_ed25519_key" = {
      text = config.sops.secrets.ssh_host_ed25519_key;
      mode = "0400";
    };
    "ssh/ssh_host_ed25519_key.pub" = {
      text = config.sops.secrets.ssh_host_ed25519_key_pub;
      mode = "0644";
    };
  };
}
