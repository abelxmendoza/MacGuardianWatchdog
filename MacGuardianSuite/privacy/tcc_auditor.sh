#!/bin/bash

# ===============================
# TCC (Transparency, Consent, and Control) Privacy Auditor
# Audits macOS privacy permissions and TCC database
# Event Spec v1.0.0 compliant
# ===============================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUITE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source core modules
source "$SUITE_DIR/core/validators.sh" 2>/dev/null || true
source "$SUITE_DIR/core/logging.sh" 2>/dev/null || true
source "$SUITE_DIR/core/system_state.sh" 2>/dev/null || true
source "$SUITE_DIR/daemons/event_writer.sh" 2>/dev/null || true

TCC_DB="/Library/Application Support/com.apple.TCC/TCC.db"
USER_TCC_DB="$HOME/Library/Application Support/com.apple.TCC/TCC.db"
BASELINE_DIR="$HOME/.macguardian/baselines"
PRIVACY_BASELINE="$BASELINE_DIR/privacy_baseline.json"
AUDIT_OUTPUT="$HOME/.macguardian/audits/tcc_audit_$(date +%Y%m%d_%H%M%S).json"

mkdir -p "$BASELINE_DIR" "$(dirname "$AUDIT_OUTPUT")"

# Initialize privacy baseline
init_privacy_baseline() {
    if [ ! -f "$PRIVACY_BASELINE" ]; then
        log_auditor "tcc_auditor" "INFO" "Creating privacy baseline..."
        
        local permissions="{}"
        local permission_list="[]"
        
        # Query TCC database if sqlite3 is available
        if command -v sqlite3 &> /dev/null && [ -f "$USER_TCC_DB" ]; then
            # Get all permissions with details
            local perm_data=$(sqlite3 "$USER_TCC_DB" -json "SELECT client, service, allowed FROM access WHERE allowed=1;" 2>/dev/null || echo "[]")
            if [ -n "$perm_data" ] && [ "$perm_data" != "[]" ]; then
                permission_list="$perm_data"
            fi
            
            local perm_count=$(sqlite3 "$USER_TCC_DB" "SELECT COUNT(*) FROM access WHERE allowed=1;" 2>/dev/null || echo "0")
            permissions="{\"permission_count\": $perm_count, \"permissions\": $permission_list}"
        fi
        
        cat > "$PRIVACY_BASELINE" <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "permissions": $permissions
}
EOF
        
        log_auditor "tcc_auditor" "INFO" "Privacy baseline created"
    fi
}

# Audit TCC permissions
audit_tcc_permissions() {
    local issues=0
    
    # Load baseline
    if [ ! -f "$PRIVACY_BASELINE" ]; then
        init_privacy_baseline
        return 0
    fi
    
    # Check for new permissions
    if command -v sqlite3 &> /dev/null && [ -f "$USER_TCC_DB" ]; then
        local current_count=$(sqlite3 "$USER_TCC_DB" "SELECT COUNT(*) FROM access WHERE allowed=1;" 2>/dev/null || echo "0")
        local baseline_count=$(grep -o '"permission_count":[0-9]*' "$PRIVACY_BASELINE" 2>/dev/null | cut -d: -f2 || echo "0")
        
        current_count="${current_count:-0}"
        baseline_count="${baseline_count:-0}"

        # Get current permissions with details
        local current_perms=$(sqlite3 "$USER_TCC_DB" -json "SELECT client, service, allowed FROM access WHERE allowed=1;" 2>/dev/null || echo "[]")
        
        # Check for new permissions (compare counts)
        if [ "$current_count" -gt "$baseline_count" ]; then
            issues=$((issues + 1))
            local new_count=$((current_count - baseline_count))
            
            # Emit Event Spec v1.0.0 event for new permissions
            local context_json="{\"permission_count\": $current_count, \"baseline_count\": $baseline_count, \"new_permissions\": $new_count, \"change_type\": \"granted\"}"
            write_event "tcc_permission_change" "medium" "tcc_auditor" "$context_json"
            
            log_auditor "tcc_auditor" "WARNING" "New privacy permissions granted: $baseline_count -> $current_count"
        fi
        
        # Check for specific permission types and emit events
        # Full Disk Access
        local full_disk=$(sqlite3 "$USER_TCC_DB" "SELECT COUNT(*) FROM access WHERE service='kTCCServiceSystemPolicyAllFiles' AND allowed=1;" 2>/dev/null || echo "0")
        if [ "$full_disk" -gt 0 ]; then
            # Get apps with Full Disk Access
            local fda_apps=$(sqlite3 "$USER_TCC_DB" -json "SELECT client, service FROM access WHERE service='kTCCServiceSystemPolicyAllFiles' AND allowed=1;" 2>/dev/null || echo "[]")
            local context_json="{\"permission\": \"kTCCServiceSystemPolicyAllFiles\", \"app_count\": $full_disk, \"apps\": $fda_apps, \"status\": \"allowed\"}"
            write_event "tcc_permission_change" "high" "tcc_auditor" "$context_json"
            log_auditor "tcc_auditor" "INFO" "Full Disk Access granted to $full_disk application(s)"
        fi
        
        # Screen Recording
        local screen_recording=$(sqlite3 "$USER_TCC_DB" "SELECT COUNT(*) FROM access WHERE service='kTCCServiceScreenCapture' AND allowed=1;" 2>/dev/null || echo "0")
        if [ "$screen_recording" -gt 0 ]; then
            local sr_apps=$(sqlite3 "$USER_TCC_DB" -json "SELECT client, service FROM access WHERE service='kTCCServiceScreenCapture' AND allowed=1;" 2>/dev/null || echo "[]")
            local context_json="{\"permission\": \"kTCCServiceScreenCapture\", \"app_count\": $screen_recording, \"apps\": $sr_apps, \"status\": \"allowed\"}"
            write_event "tcc_permission_change" "high" "tcc_auditor" "$context_json"
            log_auditor "tcc_auditor" "INFO" "Screen Recording granted to $screen_recording application(s)"
        fi
        
        # Microphone
        local microphone=$(sqlite3 "$USER_TCC_DB" "SELECT COUNT(*) FROM access WHERE service='kTCCServiceMicrophone' AND allowed=1;" 2>/dev/null || echo "0")
        if [ "$microphone" -gt 0 ]; then
            local mic_apps=$(sqlite3 "$USER_TCC_DB" -json "SELECT client, service FROM access WHERE service='kTCCServiceMicrophone' AND allowed=1;" 2>/dev/null || echo "[]")
            local context_json="{\"permission\": \"kTCCServiceMicrophone\", \"app_count\": $microphone, \"apps\": $mic_apps, \"status\": \"allowed\"}"
            write_event "tcc_permission_change" "medium" "tcc_auditor" "$context_json"
            log_auditor "tcc_auditor" "INFO" "Microphone access granted to $microphone application(s)"
        fi
        
        # Camera
        local camera=$(sqlite3 "$USER_TCC_DB" "SELECT COUNT(*) FROM access WHERE service='kTCCServiceCamera' AND allowed=1;" 2>/dev/null || echo "0")
        if [ "$camera" -gt 0 ]; then
            local cam_apps=$(sqlite3 "$USER_TCC_DB" -json "SELECT client, service FROM access WHERE service='kTCCServiceCamera' AND allowed=1;" 2>/dev/null || echo "[]")
            local context_json="{\"permission\": \"kTCCServiceCamera\", \"app_count\": $camera, \"apps\": $cam_apps, \"status\": \"allowed\"}"
            write_event "tcc_permission_change" "medium" "tcc_auditor" "$context_json"
            log_auditor "tcc_auditor" "INFO" "Camera access granted to $camera application(s)"
        fi
        
        # Input Monitoring
        local input_monitoring=$(sqlite3 "$USER_TCC_DB" "SELECT COUNT(*) FROM access WHERE service='kTCCServiceListenEvent' AND allowed=1;" 2>/dev/null || echo "0")
        if [ "$input_monitoring" -gt 0 ]; then
            local im_apps=$(sqlite3 "$USER_TCC_DB" -json "SELECT client, service FROM access WHERE service='kTCCServiceListenEvent' AND allowed=1;" 2>/dev/null || echo "[]")
            local context_json="{\"permission\": \"kTCCServiceListenEvent\", \"app_count\": $input_monitoring, \"apps\": $im_apps, \"status\": \"allowed\"}"
            write_event "tcc_permission_change" "high" "tcc_auditor" "$context_json"
            log_auditor "tcc_auditor" "INFO" "Input Monitoring granted to $input_monitoring application(s)"
        fi
        
        # Accessibility
        local accessibility=$(sqlite3 "$USER_TCC_DB" "SELECT COUNT(*) FROM access WHERE service='kTCCServiceAccessibility' AND allowed=1;" 2>/dev/null || echo "0")
        if [ "$accessibility" -gt 0 ]; then
            local acc_apps=$(sqlite3 "$USER_TCC_DB" -json "SELECT client, service FROM access WHERE service='kTCCServiceAccessibility' AND allowed=1;" 2>/dev/null || echo "[]")
            local context_json="{\"permission\": \"kTCCServiceAccessibility\", \"app_count\": $accessibility, \"apps\": $acc_apps, \"status\": \"allowed\"}"
            write_event "tcc_permission_change" "high" "tcc_auditor" "$context_json"
            log_auditor "tcc_auditor" "INFO" "Accessibility granted to $accessibility application(s)"
        fi
        
        # Compare individual permissions to detect changes
        # This is a simplified comparison - in production, would compare full permission sets
        if [ "$current_count" != "$baseline_count" ]; then
            # Emit summary event
            local context_json="{\"permission_count\": $current_count, \"baseline_count\": $baseline_count, \"full_disk_access\": $full_disk, \"screen_recording\": $screen_recording, \"microphone\": $microphone, \"camera\": $camera, \"input_monitoring\": $input_monitoring, \"accessibility\": $accessibility, \"change_type\": \"audit\"}"
            write_event "tcc_permission_change" "low" "tcc_auditor" "$context_json"
        fi
    else
        log_auditor "tcc_auditor" "WARNING" "sqlite3 not available or TCC database not found - cannot audit permissions"
    fi
    
    # Output JSON audit file (for backward compatibility)
    cat > "$AUDIT_OUTPUT" <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "audit_type": "tcc_privacy",
  "issues_found": $issues,
  "full_disk_access": ${full_disk:-0},
  "screen_recording": ${screen_recording:-0},
  "microphone": ${microphone:-0},
  "camera": ${camera:-0},
  "input_monitoring": ${input_monitoring:-0},
  "accessibility": ${accessibility:-0}
}
EOF
    
    if [ $issues -eq 0 ]; then
        log_auditor "tcc_auditor" "INFO" "TCC privacy audit completed - no issues found"
    else
        log_auditor "tcc_auditor" "WARNING" "TCC privacy audit completed - $issues issue(s) found"
    fi
    
    return $issues
}

# Main execution
if [ "${1:-audit}" = "baseline" ]; then
    init_privacy_baseline
else
    audit_tcc_permissions
fi

