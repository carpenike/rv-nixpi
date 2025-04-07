# rv-nixpi
NixOS Configuration for my RV's Raspberry Pi 4

# Useful commands

## Updating ssh-age when host key changes
```bash
nix-shell -p ssh-to-age --run 'cat /etc/ssh/ssh_host_ed25519_key.pub | ssh-to-age'
```
