{ config, pkgs, lib, ... }:

{
  networking = {
    networkmanager.enable = false;
    wireless.iwd.enable = true;
    hostName = "nixpi";

    # Use systemd-networkd for network management
    useNetworkd = true;
    # Disable conflicting dhcpcd
    useDHCP = false;

    wireless.iwd.settings = {
      General = {
        EnableNetworkConfiguration = true;
      };
      DriverQuirks = {
        DefaultInterface = "wlan0";
        DisableHt = false;
        DisableVht = false;
        DisableHe = true;
      };
    };
  };

  systemd.tmpfiles.rules = [
    # Initial placement for first boot (used only if file doesn't already exist)
    "C /var/lib/iwd/iot.psk 0600 root root - ${config.sops.secrets.IOT_WIFI_PASSWORD.path}"
    "C /var/lib/iwd/rvproblems-2ghz.psk 0600 root root - ${config.sops.secrets.RVPROBLEMS_WIFI_PASSWORD.path}"
  ];

  # Smart update of secrets and iwd restart on change
  system.activationScripts.updateIwdSecrets.text = ''
    echo "🔧 Checking for updated IWD secrets..."

    update_psk() {
      src="$1"
      dest="$2"

      if ! ${pkgs.diffutils}/bin/cmp -s "$src" "$dest"; then
        echo "🔐 Updating $dest from $src..."
        cp "$src" "$dest"
        chmod 600 "$dest"
        chown root:root "$dest"
        return 0
      else
        echo "✅ $dest is up to date."
        return 1
      fi
    }

    updated=0
    if update_psk "${config.sops.secrets.IOT_WIFI_PASSWORD.path}" "/var/lib/iwd/iot.psk"; then
      updated=1
    fi

    if update_psk "${config.sops.secrets.RVPROBLEMS_WIFI_PASSWORD.path}" "/var/lib/iwd/rvproblems-2ghz.psk"; then
      updated=1
    fi

    if [ "$updated" -eq 1 ]; then
      echo "🔁 Restarting iwd due to updated secrets..."
      ${pkgs.systemd}/bin/systemctl restart iwd
    else
      echo "📡 No IWD secret changes detected. Skipping restart."
    fi
  '';

  systemd.services.iwd.serviceConfig = {
    Restart = "on-failure";
    RestartSec = 2;
  };
}
