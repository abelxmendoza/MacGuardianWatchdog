#!/bin/bash

# ===============================
# Event Writer (Event Spec v1.0.0 Compliant)
# Writes standardized JSON events
# ===============================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUITE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source core modules
source "$SUITE_DIR/core/validators.sh" 2>/dev/null || true
source "$SUITE_DIR/core/logging.sh" 2>/dev/null || true

EVENT_DIR="$HOME/.macguardian/events"
mkdir -p "$EVENT_DIR"

# ===============================
# Write Event (Event Spec v1.0.0)
# ===============================

write_event() {
    local event_type="$1"
    local severity="$2"
    local source_module="$3"
    local context_json="${4:-}"
    if [ -z "$context_json" ]; then
        context_json="{}"
    fi
    
    # Validate inputs
    if ! validate_event_type "$event_type"; then
        log_error "Invalid event_type: $event_type"
        return 1
    fi
    
    if ! validate_severity "$severity"; then
        log_error "Invalid severity: $severity"
        return 1
    fi
    
    # Generate event_id (UUID v4)
    local event_id
    if command -v uuidgen &> /dev/null; then
        event_id=$(uuidgen)
    else
        # Fallback: generate UUID-like string
        event_id=$(od -x /dev/urandom | head -1 | awk '{OFS="-"; print $2$3,$4,$5,$6,$7$8$9}' | tr '[:upper:]' '[:lower:]')
    fi
    
    # Validate UUID format
    if ! validate_uuid "$event_id"; then
        # Generate simpler UUID if validation fails
        event_id="$(date +%s)-$(shasum -a 256 <<< "$event_type$severity$source_module" | cut -c1-32)"
    fi
    
    # Generate timestamp (ISO8601 UTC)
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    if ! validate_timestamp "$timestamp"; then
        timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    fi
    
    # Ensure context is valid JSON
    if [[ -z "$context_json" ]] || [[ "$context_json" = "{}" ]]; then
        context_json="{}"
    elif [[ ! "$context_json" =~ ^\{.*\}$ ]]; then
        # If not JSON object, wrap it
        local escaped_context=$(echo "$context_json" | sed 's/"/\\"/g')
        context_json="{\"raw_message\": \"$escaped_context\"}"
    fi
    
    # Create event file
    local file="$EVENT_DIR/event_${event_id}.json"
    
    # Write Event Spec v1.0.0 compliant JSON
    cat > "$file" <<EOF
{
  "event_id": "$event_id",
  "event_type": "$event_type",
  "severity": "$severity",
  "timestamp": "$timestamp",
  "source": "$source_module",
  "context": $context_json
}
EOF
    
    # Set secure permissions
    chmod 600 "$file" 2>/dev/null || true
    
    # Log to JSONL timeline
    log_json_event "$(cat "$file")"
    
    return 0
}

# ===============================
# Legacy Support (backward compatibility)
# ===============================

write_event_legacy() {
    local type="$1"
    local severity="$2"
    local message="$3"
    local details="${4:-{}}"
    
    # Map legacy types to Event Spec v1.0.0 types
    local mapped_type="$type"
    case "$type" in
        filesystem|fs)
            mapped_type="file_integrity_change"
            ;;
        process)
            mapped_type="process_anomaly"
            ;;
        network)
            mapped_type="network_connection"
            ;;
        ids|correlation)
            mapped_type="ids_alert"
            ;;
        ssh)
            mapped_type="ssh_key_change"
            ;;
        cron)
            mapped_type="cron_modification"
            ;;
        privacy|tcc_privacy)
            mapped_type="tcc_permission_change"
            ;;
        user_accounts)
            mapped_type="user_account_change"
            ;;
        ransomware)
            mapped_type="ransomware_activity"
            ;;
        *)
            mapped_type="process_anomaly"  # Default fallback
            ;;
    esac
    
    # Create context with message
    local context_json="{\"message\": \"$message\""
    if [[ "$details" != "{}" ]] && [[ "$details" =~ ^\{ ]]; then
        # Merge details into context
        context_json="${context_json}, $(echo "$details" | sed 's/^{//' | sed 's/}$//')"
    fi
    context_json="${context_json}}"
    
    # Determine source module from type
    local source_module="${type}_watcher"
    if [[ "$type" =~ ^(ssh|cron|user_accounts|privacy|tcc_privacy) ]]; then
        source_module="${type}_auditor"
    elif [[ "$type" =~ ^(ids|ransomware|signature|correlation) ]]; then
        source_module="${type}_detector"
    fi
    
    write_event "$mapped_type" "$severity" "$source_module" "$context_json"
}

export -f write_event
export -f write_event_legacy
