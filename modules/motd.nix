{ config, pkgs, lib, ... }:

let
  noticePath = "/etc/issue.d/10-age-key-notice.issue";
  markerPath = "/etc/.sops-age-key-synced";
in {
  systemd.services.gen-age-motd = {
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" "sshd.service" ];
    description = "Generate SSH-to-Age provisioning notice";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "gen-age-motd" ''
        if [ -f "${markerPath}" ]; then
          exit 0
        fi

        PUBKEY_FILE="/etc/ssh/ssh_host_ed25519_key.pub"
        if [ -f "$PUBKEY_FILE" ]; then
          AGE_PUB="$(${pkgs.ssh-to-age}/bin/ssh-to-age < "$PUBKEY_FILE")"
          HOSTNAME="$(hostname)"

          cat > "${noticePath}" <<EOF

🔧 Provisioning Notice for $HOSTNAME
======================================

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
    echo "🔐 SOPS secrets successfully decrypted. Marking as provisioned."
    touch ${markerPath}
    rm -f ${noticePath}
  '';

  # Show MOTD in Fish shell sessions too
  programs.fish.interactiveShellInit = ''
    if test -f ${noticePath}
      cat ${noticePath}
    end
  '';
}
