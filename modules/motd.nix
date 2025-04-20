{ config, pkgs, lib, ... }:

let
  noticePath = "/etc/issue.d/10-age-key-notice.issue";
  tempNoticePath = "/run/10-age-key-notice.issue";
  markerPath = "/etc/.sops-age-key-synced";
in {
  systemd.services.gen-age-motd = {
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" "sshd.service" ];
    description = "Generate SSH-to-Age provisioning notice";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "gen-age-motd" ''
        # Check if we're already provisioned
        if [ -f "${markerPath}" ]; then
          echo "System already provisioned, exiting"
          # Remove the notice file if it exists
          rm -f "${tempNoticePath}"
          exit 0
        fi

        PUBKEY_FILE="/etc/ssh/ssh_host_ed25519_key.pub"
        if [ -f "$PUBKEY_FILE" ]; then
          AGE_PUB="$(${pkgs.ssh-to-age}/bin/ssh-to-age < "$PUBKEY_FILE")"
          # Get hostname - use hostname command with fallback to /etc/hostname
          HOSTNAME="$(hostname 2>/dev/null || cat /etc/hostname 2>/dev/null || echo "nixpi")"

          # Write to temporary file to avoid symlink loops
          cat > "${tempNoticePath}" <<EOF

🔧 Provisioning Notice for $HOSTNAME
======================================

🔑 SSH-to-Age public key:
$AGE_PUB

📌 Add this key to .sops.yaml and re-encrypt your secrets.
💡 This message will disappear once your key is detected in the remote repo.
EOF
          chmod 644 "${tempNoticePath}"
        else
          echo "⚠️ SSH host key not found. Cannot generate age key." > "${tempNoticePath}"
          chmod 644 "${tempNoticePath}"
        fi
      '';
    };
  };

  # Use temporary file to avoid symlink loops
  environment.etc."issue.d/10-age-key-notice.issue".source = tempNoticePath;

🔑 SSH-to-Age public key:
$AGE_PUB

📌 Add this key to .sops.yaml and re-encrypt your secrets.
💡 This message will disappear once your key is detected in the remote repo.
EOF
        else
          echo "⚠️ SSH host key not found. Cannot generate age key." > "${noticePath}"
        fi
      '';
    };
  };

  environment.etc."issue.d/10-age-key-notice.issue".source = noticePath;

  # Remove MOTD and mark system as synced once secrets are decrypted successfully
  system.activationScripts.remove-motd-notice = lib.mkIf (config.sops.secrets ? IOT_WIFI_PASSWORD) ''
    if [ -f "/etc/ssh/ssh_host_ed25519_key.pub" ]; then
      echo "🔐 SSH host key found and SOPS secrets successfully decrypted. Marking as provisioned."
      touch ${markerPath}
      # Make sure the notice file is removed
      if [ -f "${tempNoticePath}" ]; then
        echo "Removing notice file ${tempNoticePath}"
        rm -f "${tempNoticePath}"
      fi
    else
      echo "⚠️ SSH host key not found - not removing provisioning notice"
    fi
  '';

  # Show MOTD in Fish shell sessions too
  programs.fish.interactiveShellInit = ''
    if test -f ${tempNoticePath}
      cat ${tempNoticePath}
    end
  '';
}
