#!/bin/bash

# ===============================
# SSH Security Auditor
# Comprehensive SSH configuration and key auditing
# Event Spec v1.0.0 compliant
# ===============================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUITE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source core modules
source "$SUITE_DIR/core/validators.sh" 2>/dev/null || true
source "$SUITE_DIR/core/logging.sh" 2>/dev/null || true
source "$SUITE_DIR/core/system_state.sh" 2>/dev/null || true
source "$SUITE_DIR/core/privilege_check.sh" 2>/dev/null || true
source "$SUITE_DIR/daemons/event_writer.sh" 2>/dev/null || true

# Configuration
SSH_DIR="$HOME/.ssh"
SSH_CONFIG="$SSH_DIR/config"
AUTHORIZED_KEYS="$SSH_DIR/authorized_keys"
KNOWN_HOSTS="$SSH_DIR/known_hosts"
SSHD_CONFIG="/etc/ssh/sshd_config"

BASELINE_DIR="$HOME/.macguardian/baselines"
SSH_BASELINE="$BASELINE_DIR/ssh_fingerprints.json"
AUDIT_OUTPUT="$HOME/.macguardian/audits/ssh_audit_$(date +%Y%m%d_%H%M%S).json"

mkdir -p "$BASELINE_DIR" "$(dirname "$AUDIT_OUTPUT")"

# Initialize baseline if it doesn't exist
init_ssh_baseline() {
    if [ ! -f "$SSH_BASELINE" ]; then
        log_auditor "ssh_auditor" "INFO" "Creating SSH baseline..."
        
        local baseline_data="{"
        
        # Authorized keys fingerprints
        if [ -f "$AUTHORIZED_KEYS" ]; then
            local keys_fingerprints=""
            while IFS= read -r line; do
                if [[ "$line" =~ ^[^#] ]] && [ -n "$line" ]; then
                    # Extract key type and fingerprint
                    local key_type=$(echo "$line" | awk '{print $1}')
                    local key_content=$(echo "$line" | awk '{print $2}')
                    if [ -n "$key_content" ]; then
                        # Generate fingerprint (simplified)
                        local fingerprint=$(echo "$key_content" | shasum -a 256 | cut -d' ' -f1)
                        if [ -n "$keys_fingerprints" ]; then
                            keys_fingerprints="$keys_fingerprints,"
                        fi
                        keys_fingerprints="$keys_fingerprints{\"type\":\"$key_type\",\"fingerprint\":\"$fingerprint\",\"line\":\"$line\"}"
                    fi
                fi
            done < "$AUTHORIZED_KEYS"
            
            baseline_data="$baseline_data\"authorized_keys\":[$keys_fingerprints],"
        fi
        
        # SSH config file hash
        if [ -f "$SSH_CONFIG" ]; then
            local config_hash=$(shasum -a 256 "$SSH_CONFIG" 2>/dev/null | cut -d' ' -f1 || echo "")
            baseline_data="$baseline_data\"config_hash\":\"$config_hash\","
        fi
        
        # Known hosts hash
        if [ -f "$KNOWN_HOSTS" ]; then
            local known_hosts_hash=$(shasum -a 256 "$KNOWN_HOSTS" 2>/dev/null | cut -d' ' -f1 || echo "")
            baseline_data="$baseline_data\"known_hosts_hash\":\"$known_hosts_hash\","
        fi
        
        # SSHD config hash (if accessible)
        if [ -f "$SSHD_CONFIG" ] && [ -r "$SSHD_CONFIG" ]; then
            local sshd_hash=$(shasum -a 256 "$SSHD_CONFIG" 2>/dev/null | cut -d' ' -f1 || echo "")
            baseline_data="$baseline_data\"sshd_config_hash\":\"$sshd_hash\","
        fi
        
        baseline_data="${baseline_data%,}\"}"
        baseline_data="${baseline_data%,}"
        baseline_data="${baseline_data%,}"
        baseline_data="${baseline_data%,}"
        
        echo "$baseline_data" > "$SSH_BASELINE"
        log_auditor "ssh_auditor" "INFO" "SSH baseline created"
    fi
}

# Audit SSH configuration
audit_ssh() {
    local issues=0
    local findings="[]"
    
    # Load baseline
    if [ ! -f "$SSH_BASELINE" ]; then
        init_ssh_baseline
    fi
    
    # Check authorized_keys changes
    if [ -f "$AUTHORIZED_KEYS" ]; then
        local current_keys=""
        while IFS= read -r line; do
            if [[ "$line" =~ ^[^#] ]] && [ -n "$line" ]; then
                local key_type=$(echo "$line" | awk '{print $1}')
                local key_content=$(echo "$line" | awk '{print $2}')
                if [ -n "$key_content" ]; then
                    local fingerprint=$(echo "$key_content" | shasum -a 256 | cut -d' ' -f1)
                    if [ -n "$current_keys" ]; then
                        current_keys="$current_keys,"
                    fi
                    current_keys="$current_keys{\"type\":\"$key_type\",\"fingerprint\":\"$fingerprint\"}"
                fi
            fi
        done < "$AUTHORIZED_KEYS"
        
        # Compare with baseline (simplified - would need jq for proper comparison)
        if [ -n "$current_keys" ]; then
            # Check if baseline has different keys
            local baseline_keys=$(grep -o '"fingerprint":"[^"]*"' "$SSH_BASELINE" 2>/dev/null || echo "")
            if [ -n "$baseline_keys" ]; then
                # Simple check: count keys
                local baseline_count=$(echo "$baseline_keys" | wc -l | tr -d ' ')
                local current_count=$(echo "$current_keys" | grep -o '"fingerprint"' | wc -l | tr -d ' ')
                
                if [ "$current_count" != "$baseline_count" ]; then
                    issues=$((issues + 1))
                    
                    # Determine change type
                    local change_type="added"
                    if [ "$current_count" -lt "$baseline_count" ]; then
                        change_type="removed"
                    fi
                    
                    # Emit Event Spec v1.0.0 event
                    local context_json="{\"file\": \"$AUTHORIZED_KEYS\", \"change_type\": \"$change_type\", \"baseline_count\": $baseline_count, \"current_count\": $current_count, \"key_type\": \"authorized_keys\"}"
                    write_event "ssh_key_change" "high" "ssh_auditor" "$context_json"
                    log_auditor "ssh_auditor" "WARNING" "Authorized keys count changed: $baseline_count -> $current_count"
                fi
            fi
        fi
    fi
    
    # Check SSH config file integrity
    if [ -f "$SSH_CONFIG" ]; then
        local current_hash=$(shasum -a 256 "$SSH_CONFIG" 2>/dev/null | cut -d' ' -f1 || echo "")
        local baseline_hash=$(grep -o '"config_hash":"[^"]*"' "$SSH_BASELINE" 2>/dev/null | cut -d'"' -f4 || echo "")
        
        if [ -n "$baseline_hash" ] && [ "$current_hash" != "$baseline_hash" ]; then
            issues=$((issues + 1))
            
            # Emit Event Spec v1.0.0 event
            local context_json="{\"file\": \"$SSH_CONFIG\", \"change_type\": \"modified\", \"old_hash\": \"$baseline_hash\", \"new_hash\": \"$current_hash\"}"
            write_event "ssh_key_change" "high" "ssh_auditor" "$context_json"
            log_auditor "ssh_auditor" "WARNING" "SSH config file modified"
        fi
    fi
    
    # Check known_hosts changes
    if [ -f "$KNOWN_HOSTS" ]; then
        local current_hash=$(shasum -a 256 "$KNOWN_HOSTS" 2>/dev/null | cut -d' ' -f1 || echo "")
        local baseline_hash=$(grep -o '"known_hosts_hash":"[^"]*"' "$SSH_BASELINE" 2>/dev/null | cut -d'"' -f4 || echo "")
        
        if [ -n "$baseline_hash" ] && [ "$current_hash" != "$baseline_hash" ]; then
            issues=$((issues + 1))
            
            # Emit Event Spec v1.0.0 event
            local context_json="{\"file\": \"$KNOWN_HOSTS\", \"change_type\": \"modified\", \"old_hash\": \"$baseline_hash\", \"new_hash\": \"$current_hash\"}"
            write_event "ssh_key_change" "medium" "ssh_auditor" "$context_json"
            log_auditor "ssh_auditor" "WARNING" "Known hosts file modified"
        fi
    fi
    
    # Check for failed SSH login attempts
    if command -v log &> /dev/null; then
        local failed_logins=$( (log show --predicate 'process == "sshd"' --last 1h 2>/dev/null | grep -i "failed\|invalid\|authentication failure" | wc -l | tr -d ' ' || echo "0") | head -1)
        if [ "$failed_logins" -gt 0 ]; then
            issues=$((issues + 1))
            
            # Emit Event Spec v1.0.0 event
            local context_json="{\"failed_login_count\": $failed_logins, \"time_window\": \"1h\", \"alert_type\": \"failed_authentication\"}"
            write_event "ssh_key_change" "high" "ssh_auditor" "$context_json"
            log_auditor "ssh_auditor" "WARNING" "Detected $failed_logins failed SSH login attempt(s) in last hour"
        fi
    fi
    
    # Output JSON
    cat > "$AUDIT_OUTPUT" <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "audit_type": "ssh",
  "issues_found": $issues,
  "findings": $findings,
  "authorized_keys_file": "$AUTHORIZED_KEYS",
  "config_file": "$SSH_CONFIG",
  "known_hosts_file": "$KNOWN_HOSTS"
}
EOF
    
    if [ $issues -eq 0 ]; then
        log_auditor "ssh_auditor" "INFO" "SSH audit completed - no issues found"
    else
        log_auditor "ssh_auditor" "WARNING" "SSH audit completed - $issues issue(s) found"
    fi
    
    return $issues
}

# Check privileges on load
if ! check_privileges "audit"; then
    log_auditor "ssh_auditor" "WARNING" "Some SSH audit checks may require sudo privileges"
fi

# Main execution
if [ "${1:-audit}" = "baseline" ]; then
    init_ssh_baseline
else
    audit_ssh
fi

