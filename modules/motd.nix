{ config, pkgs, lib, ... }:

let
  noticePath = "/etc/issue.d/10-age-key-notice.issue";
in {
  systemd.services.gen-age-motd = {
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" "sshd.service" ];
    description = "Generate SSH-to-Age provisioning notice";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "gen-age-motd" ''
        if [ -f "${noticePath}" ]; then
          exit 0
        fi

        PUBKEY_FILE="/etc/ssh/ssh_host_ed25519_key.pub"
        if [ -f "$PUBKEY_FILE" ]; then
          AGE_PUB="$(${pkgs.ssh-to-age}/bin/ssh-to-age < "$PUBKEY_FILE")"

          cat <<EOF > "${noticePath}"

🔧 Provisioning Notice for \$(hostname)
======================================

🔑 SSH-to-Age public key:
$AGE_PUB

📌 Add this key to .sops.yaml and re-encrypt your secrets.
💡 This message will disappear once secrets decrypt successfully.
EOF
        else
          echo "⚠️ SSH host key not found. Cannot generate age key." > "${noticePath}"
        fi
      '';
    };
  };

  # This message gets shown at login (PAM MOTD), not hard override of /etc/motd
  environment.etc."issue.d/10-age-key-notice.issue".source = noticePath;

  # Optional: Auto-remove notice once secrets decrypt correctly
  system.activationScripts.remove-motd-notice = lib.mkIf (config.sops.secrets ? IOT_WIFI_PASSWORD) ''
    rm -f ${noticePath}
  '';

  # Show MOTD notice in Fish shell sessions too
  programs.fish.interactiveShellInit = ''
    if test -f ${noticePath}
      cat ${noticePath}
    end
  '';
}
