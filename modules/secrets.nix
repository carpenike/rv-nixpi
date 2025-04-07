{
  pkgs,
  config,
  ...
}:
{
  config = {
    environment.systemPackages = [
      pkgs.sops
      pkgs.age
    ];

    sops = {
      defaultSopsFile = ../secrets/secrets.sops.yaml;
      age.sshKeyPaths = [
        "/etc/ssh/ssh_host_ed25519_key"
      ];

      secrets = {
        ryan_password = {};
        ryan_ssh_public_key = {};
        ssh_host_ed25519_key = {};
        ssh_host_ed25519_key_pub = {};
        iot = {};
        rvproblems-2ghz = {};
      };
    };
  };
}
