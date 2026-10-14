#!/bin/bash

# ===============================
# User Account Security Auditor
# Comprehensive user account and privilege auditing
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

BASELINE_DIR="$HOME/.macguardian/baselines"
USER_BASELINE="$BASELINE_DIR/user_accounts.json"
AUDIT_OUTPUT="$HOME/.macguardian/audits/user_accounts_$(date +%Y%m%d_%H%M%S).json"
SUDOERS_FILE="/etc/sudoers"

mkdir -p "$BASELINE_DIR" "$(dirname "$AUDIT_OUTPUT")"

# Initialize baseline
init_user_baseline() {
    if [ ! -f "$USER_BASELINE" ]; then
        log_auditor "user_account_auditor" "INFO" "Creating user account baseline..."
        
        local users_json="["
        local first=true
        
        # Get all users
        dscl . -list /Users 2>/dev/null | while IFS= read -r username; do
            if [ -z "$username" ] || [ "$username" = "daemon" ] || [ "$username" = "nobody" ]; then
                continue
            fi
            
            local uid=$(dscl . -read /Users/"$username" UniqueID 2>/dev/null | awk '{print $2}' || echo "")
            local gid=$(dscl . -read /Users/"$username" PrimaryGroupID 2>/dev/null | awk '{print $2}' || echo "")
            local shell=$(dscl . -read /Users/"$username" UserShell 2>/dev/null | awk '{print $2}' || echo "")
            local home=$(dscl . -read /Users/"$username" NFSHomeDirectory 2>/dev/null | awk '{print $2}' || echo "")
            
            # Check if admin
            local is_admin="false"
            if dscl . -read /Groups/admin GroupMembership 2>/dev/null | grep -q "$username"; then
                is_admin="true"
            fi
            
            # Check if UID 0 (root)
            local is_root="false"
            if [ "$uid" = "0" ]; then
                is_root="true"
            fi
            
            if [ "$first" = true ]; then
                first=false
            else
                users_json="$users_json,"
            fi
            
            users_json="$users_json{\"username\":\"$username\",\"uid\":\"$uid\",\"gid\":\"$gid\",\"shell\":\"$shell\",\"home\":\"$home\",\"is_admin\":$is_admin,\"is_root\":$is_root}"
        done
        
        users_json="$users_json]"
        
        # Get sudoers hash
        local sudoers_hash=""
        if [ -f "$SUDOERS_FILE" ] && [ -r "$SUDOERS_FILE" ]; then
            sudoers_hash=$(shasum -a 256 "$SUDOERS_FILE" 2>/dev/null | cut -d' ' -f1 || echo "")
        fi
        
        cat > "$USER_BASELINE" <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "users": $users_json,
  "sudoers_hash": "$sudoers_hash"
}
EOF
        
        log_auditor "user_account_auditor" "INFO" "User account baseline created"
    fi
}

# Audit user accounts
audit_user_accounts() {
    local issues=0
    local findings="[]"
    
    # Load baseline
    if [ ! -f "$USER_BASELINE" ]; then
        init_user_baseline
        return 0
    fi
    
    # Get current users
    local current_users="["
    local first=true
    
    dscl . -list /Users 2>/dev/null | while IFS= read -r username; do
        if [ -z "$username" ] || [ "$username" = "daemon" ] || [ "$username" = "nobody" ]; then
            continue
        fi
        
        local uid=$(dscl . -read /Users/"$username" UniqueID 2>/dev/null | awk '{print $2}' || echo "")
        local is_admin="false"
        if dscl . -read /Groups/admin GroupMembership 2>/dev/null | grep -q "$username"; then
            is_admin="true"
        fi
        
        if [ "$first" = true ]; then
            first=false
        else
            current_users="$current_users,"
        fi
        
        current_users="$current_users{\"username\":\"$username\",\"uid\":\"$uid\",\"is_admin\":$is_admin}"
    done
    
    current_users="$current_users]"
    
    # Check for new users (simplified comparison)
    local baseline_user_count=$( (grep -o '"username":"[^"]*"' "$USER_BASELINE" 2>/dev/null | wc -l | tr -d ' ' || echo "0") | head -1)
    local current_user_count=$( (echo "$current_users" | grep -o '"username"' | wc -l | tr -d ' ' || echo "0") | head -1)
    
    if [ "$current_user_count" -gt "$baseline_user_count" ]; then
        issues=$((issues + 1))
        
        # Emit Event Spec v1.0.0 event
        local new_users=$((current_user_count - baseline_user_count))
        local context_json="{\"change_type\": \"added\", \"new_user_count\": $new_users, \"total_users\": $current_user_count, \"baseline_count\": $baseline_user_count}"
        write_event "user_account_change" "high" "user_account_auditor" "$context_json"
        log_auditor "user_account_auditor" "WARNING" "New user account(s) detected: $current_user_count vs baseline $baseline_user_count"
    fi
    
    # Check for UID 0 accounts (root)
    local root_users=$( (echo "$current_users" | grep -o '"uid":"0"' | wc -l | tr -d ' ' || echo "0") | head -1)
    if [ "$root_users" -gt 0 ]; then
        issues=$((issues + 1))
        
        # Emit Event Spec v1.0.0 event
        local context_json="{\"change_type\": \"anomaly\", \"anomaly_type\": \"uid_0_detected\", \"uid_0_count\": $root_users}"
        write_event "user_account_change" "critical" "user_account_auditor" "$context_json"
        log_auditor "user_account_auditor" "CRITICAL" "UID 0 (root) account(s) detected"
    fi
    
    # Check sudoers file integrity
    if [ -f "$SUDOERS_FILE" ] && [ -r "$SUDOERS_FILE" ]; then
        local current_hash=$(shasum -a 256 "$SUDOERS_FILE" 2>/dev/null | cut -d' ' -f1 || echo "")
        local baseline_hash=$(grep -o '"sudoers_hash":"[^"]*"' "$USER_BASELINE" 2>/dev/null | cut -d'"' -f4 || echo "")
        
        if [ -n "$baseline_hash" ] && [ "$current_hash" != "$baseline_hash" ]; then
            issues=$((issues + 1))
            
            # Emit Event Spec v1.0.0 event
            local context_json="{\"change_type\": \"modified\", \"file\": \"$SUDOERS_FILE\", \"old_hash\": \"$baseline_hash\", \"new_hash\": \"$current_hash\"}"
            write_event "user_account_change" "critical" "user_account_auditor" "$context_json"
            log_auditor "user_account_auditor" "CRITICAL" "Sudoers file modified"
        fi
    fi
    
    # Check for admin account changes
    local baseline_admins=$( (grep -o '"is_admin":true' "$USER_BASELINE" 2>/dev/null | wc -l | tr -d ' ' || echo "0") | head -1)
    local current_admins=$( (echo "$current_users" | grep -o '"is_admin":true' | wc -l | tr -d ' ' || echo "0") | head -1)
    
    if [ "$current_admins" != "$baseline_admins" ]; then
        issues=$((issues + 1))
        
        # Determine change type
        local change_type="modified"
        if [ "$current_admins" -gt "$baseline_admins" ]; then
            change_type="admin_added"
        else
            change_type="admin_removed"
        fi
        
        # Emit Event Spec v1.0.0 event
        local context_json="{\"change_type\": \"$change_type\", \"baseline_admin_count\": $baseline_admins, \"current_admin_count\": $current_admins}"
        write_event "user_account_change" "high" "user_account_auditor" "$context_json"
        log_auditor "user_account_auditor" "WARNING" "Admin account count changed: $baseline_admins -> $current_admins"
    fi
    
    # Check last login times for anomalies
    if command -v last &> /dev/null; then
        local recent_logins=$( (last | head -20 | grep -v "^$" | wc -l | tr -d ' ' || echo "0") | head -1)
        if [ "$recent_logins" -gt 0 ]; then
            info "Recent login activity detected: $recent_logins entries"
        fi
    fi
    
    # Output JSON
    cat > "$AUDIT_OUTPUT" <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "audit_type": "user_accounts",
  "issues_found": $issues,
  "findings": $findings,
  "current_user_count": $current_user_count,
  "baseline_user_count": $baseline_user_count,
  "admin_accounts": $current_admins,
  "root_accounts": $root_users
}
EOF
    
    if [ $issues -eq 0 ]; then
        log_auditor "user_account_auditor" "INFO" "User account audit completed - no issues found"
    else
        log_auditor "user_account_auditor" "WARNING" "User account audit completed - $issues issue(s) found"
    fi
    
    return $issues
}

# Check privileges on load
if ! check_privileges "audit"; then
    log_auditor "user_account_auditor" "WARNING" "Some user account audit checks may require sudo privileges"
fi

# Main execution
if [ "${1:-audit}" = "baseline" ]; then
    init_user_baseline
else
    audit_user_accounts
fi

