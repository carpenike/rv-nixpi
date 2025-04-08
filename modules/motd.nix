{ config, pkgs, lib, ... }:

{
  systemd.services.gen-age-motd = {
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" "sshd.service" ];
    description = "Generate SSH-to-Age MOTD notice";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "gen-age-motd" ''
        NOTICE_FILE="/etc/motd_age_notice"
        if [ ! -f "$NOTICE_FILE" ]; then
          PUBKEY_FILE="/etc/ssh/ssh_host_ed25519_key.pub"
          if [ -f "$PUBKEY_FILE" ]; then
            AGE_PUB="$(${pkgs.ssh-to-age}/bin/ssh-to-age < "$PUBKEY_FILE")"
            echo "🔑 SSH-to-Age public key:" > "$NOTICE_FILE"
            echo "$AGE_PUB" >> "$NOTICE_FILE"
            echo "" >> "$NOTICE_FILE"
            echo "📌 Add this key to .sops.yaml and re-encrypt your secrets." >> "$NOTICE_FILE"
          else
            echo "⚠️ SSH host key not found. Cannot generate age key." > "$NOTICE_FILE"
          fi
        fi
      '';
    };
  };

  environment.etc."motd".source = "/etc/motd_age_notice";
}
