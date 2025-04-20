#!/usr/bin/env bash
# Check SOPS key status (bootstrap or SSH-derived)

BOOTSTRAP_KEY_PATH="/etc/sops/age.key"
SSH_HOST_KEY_PATH="/etc/ssh/ssh_host_ed25519_key"
MARKER_PATH="/etc/.sops-age-key-synced"
LOG_FILE="/boot/sops-key-status.log"

# Function to log to both stdout and file
log() {
    echo "$@"
    echo "$@" >> "$LOG_FILE"
}

# Start with a clean log file
echo "SOPS Key Status Check - $(date)" > "$LOG_FILE"
echo "=========================================" >> "$LOG_FILE"

log "=========================================="
log "🔑 SOPS Key Status Check - $(date)"
log "=========================================="
log "Hostname: $(hostname)"
log "System uptime: $(uptime)"

# Check if we've already transitioned (marker file exists)
if [ -f "$MARKER_PATH" ]; then
    log "📋 System transition marker found at $MARKER_PATH"
    log "   This marker is created by the MOTD system when secrets are successfully decrypted"
    log "   during system activation."
    
    # Even with marker, verify the actual state of the secrets
    if [ -e "/run/secrets/IOT_WIFI_SSID" ] && [ -e "/run/secrets/IOT_WIFI_PASSWORD" ]; then
        log "   ✅ Secrets are accessible - transition appears successful"
    else
        log "   ❌ WARNING: Marker exists but secrets are NOT accessible"
        log "   This suggests the system state is inconsistent"
        
        # Check if SSH host key exists despite secrets not being accessible
        if [ -f "$SSH_HOST_KEY_PATH" ]; then
            log "   ℹ️ SSH host key exists at $SSH_HOST_KEY_PATH"
            log "   The system may need to re-run the activation scripts"
        else
            log "   ❌ SSH host key is also missing"
            log "   A fresh system boot may be required"
        fi
    fi
    
    # Continue execution to collect more diagnostic information
fi

# Check for bootstrap key
if [ -f "$BOOTSTRAP_KEY_PATH" ]; then
    log "✅ Bootstrap age key found at $BOOTSTRAP_KEY_PATH"
    log "   Size: $(stat -c %s $BOOTSTRAP_KEY_PATH) bytes"
    log "   Status: TEMPORARY - Will be replaced by SSH-derived key"
    
    # Additional details to help with troubleshooting
    log "   File permissions: $(ls -la $BOOTSTRAP_KEY_PATH)"
    
    # Check if the file has correct format (without revealing the key)
    if grep -q "AGE-SECRET-KEY-" "$BOOTSTRAP_KEY_PATH"; then
        log "   Key format: Valid (starts with AGE-SECRET-KEY-)"
    else
        log "   ⚠️ WARNING: Key format does not appear to be valid"
        log "   Key should start with AGE-SECRET-KEY-"
    fi
elif [ -f "$SSH_HOST_KEY_PATH" ]; then
    log "ℹ️ Bootstrap key not found, but SSH host key exists"
    log "   Host key: $SSH_HOST_KEY_PATH"
    log "   System is transitioning to SSH-derived key"
    log "   Follow MOTD instructions to complete setup"
    
    # Show SSH host key details
    log "   SSH key details: $(ls -la $SSH_HOST_KEY_PATH)"
    
    # Check if public key exists and try to convert it
    if [ -f "${SSH_HOST_KEY_PATH}.pub" ]; then
        log "   Public key exists: ${SSH_HOST_KEY_PATH}.pub"
        if command -v ssh-to-age > /dev/null; then
            log "   Converted AGE public key: $(ssh-to-age < ${SSH_HOST_KEY_PATH}.pub)"
        else
            log "   ssh-to-age tool not available, cannot show converted key"
        fi
    else
        log "   ⚠️ Public key not found: ${SSH_HOST_KEY_PATH}.pub"
    fi
else
    log "❌ ERROR: No encryption keys found!"
    log "   Missing bootstrap key: $BOOTSTRAP_KEY_PATH"
    log "   Missing SSH host key: $SSH_HOST_KEY_PATH"
    log "   Secrets will not be accessible"
    
    # Additional troubleshooting info
    log "   Directory check: $(ls -la /etc/sops/ 2>/dev/null || echo '/etc/sops/ directory not found')"
    log "   SSH directory check: $(ls -la /etc/ssh/ 2>/dev/null || echo '/etc/ssh/ directory not found')"
    exit 1
fi

# Check if secrets are accessible
log ""
log "Checking secrets status:"
if [ -e "/run/secrets/IOT_WIFI_SSID" ]; then
    log "   ✅ IOT_WIFI_SSID secret is accessible"
else
    log "   ❌ IOT_WIFI_SSID secret is NOT accessible"
fi

if [ -e "/run/secrets/IOT_WIFI_PASSWORD" ]; then
    log "   ✅ IOT_WIFI_PASSWORD secret is accessible"
else
    log "   ❌ IOT_WIFI_PASSWORD secret is NOT accessible"
fi

# System information
log ""
log "System information:"
log "   Distribution: $(cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d \")"
log "   Kernel: $(uname -r)"
log "   Filesystem status: $(df -h /boot /)"

# Check SOPS configuration in NixOS
log ""
log "SOPS Configuration:"
if [ -f "/etc/nixos/configuration.nix" ]; then
    log "   NixOS configuration: $(grep -A5 sops /etc/nixos/configuration.nix 2>/dev/null || echo "No SOPS config found in main config")"
fi

log "   SOPS files check:"
log "   - sops-nix installed: $(command -v sops >/dev/null && echo "Yes" || echo "No")"
log "   - yaml file: $(ls -la /etc/secrets.sops.yaml 2>/dev/null || ls -la /run/secrets.sops.yaml 2>/dev/null || echo "Not found")"
log "   - secrets dir: $(ls -la /run/secrets/ 2>/dev/null || echo "/run/secrets/ not found")"
log "   - marker file: $(ls -la $MARKER_PATH 2>/dev/null || echo "No marker file")"
log "   - bootstrap key: $(ls -la $BOOTSTRAP_KEY_PATH 2>/dev/null || echo "No bootstrap key file")"

log "=========================================="

# Set permissive permissions so the file is easily readable when mounting the SD card
chmod 644 "$LOG_FILE"

# Print the location of the log file for reference
echo "Log file written to $LOG_FILE"
