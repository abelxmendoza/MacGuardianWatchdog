#!/bin/bash

# ===============================
# Log Aggregator
# Aggregates logs from multiple sources
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

LOG_DIR="$HOME/.macguardian/logs"
AGGREGATED_LOG="$LOG_DIR/aggregated_$(date +%Y%m%d_%H%M%S).json"
UNIFIED_LOG_PYTHON="$SUITE_DIR/collectors/unified_logging.py"

mkdir -p "$LOG_DIR"

# Aggregate logs
aggregate_logs() {
    local output_file="${1:-$AGGREGATED_LOG}"
    local hours="${2:-24}"  # Default to last 24 hours
    
    # Use Python collector if available
    if [ -f "$UNIFIED_LOG_PYTHON" ] && command -v python3 &> /dev/null; then
        python3 "$UNIFIED_LOG_PYTHON" --hours "$hours" --output "$output_file" 2>/dev/null || {
            log_auditor "log_aggregator" "WARNING" "Python log aggregator failed, using fallback"
            aggregate_logs_fallback "$output_file" "$hours"
        }
    else
        aggregate_logs_fallback "$output_file" "$hours"
    fi
    
    # Parse logs for security events
    parse_security_events "$output_file" "$hours"
    
    log_auditor "log_aggregator" "INFO" "Logs aggregated: $output_file"
}

# Parse security events from logs
parse_security_events() {
    local log_file="$1"
    local hours="$2"
    
    # Check for failed SSH login attempts
    if command -v log &> /dev/null; then
        local failed_ssh=$( (log show --last "${hours}h" --predicate 'process == "sshd" AND eventMessage CONTAINS "Failed"' 2>/dev/null | grep -i "failed" | wc -l | tr -d ' ' || echo "0") | head -1)
        if [ "$failed_ssh" -gt 0 ]; then
            local context_json="{\"event_type\": \"ssh_login_failure\", \"count\": $failed_ssh, \"time_window_hours\": $hours}"
            write_event "ids_alert" "medium" "log_aggregator" "$context_json"
        fi
        
        # Check for sudo privilege escalations
        local sudo_events=$( (log show --last "${hours}h" --predicate 'process == "sudo"' 2>/dev/null | grep -i "sudo" | wc -l | tr -d ' ' || echo "0") | head -1)
        if [ "$sudo_events" -gt 10 ]; then
            local context_json="{\"event_type\": \"sudo_escalation\", \"count\": $sudo_events, \"time_window_hours\": $hours}"
            write_event "ids_alert" "medium" "log_aggregator" "$context_json"
        fi
        
        # Check for kernel panics
        local panics=$( (log show --last "${hours}h" --predicate 'process == "kernel" AND eventMessage CONTAINS "panic"' 2>/dev/null | grep -i "panic" | wc -l | tr -d ' ' || echo "0") | head -1)
        if [ "$panics" -gt 0 ]; then
            local context_json="{\"event_type\": \"kernel_panic\", \"count\": $panics, \"time_window_hours\": $hours}"
            write_event "ids_alert" "high" "log_aggregator" "$context_json"
        fi
    fi
}

# Fallback aggregation
aggregate_logs_fallback() {
    local output_file="$1"
    local hours="$2"
    
    local start_time=$(date -v-${hours}H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -d "$hours hours ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "")
    
    echo "[]" > "$output_file"
    
    # Aggregate from unified logging if available
    if command -v log &> /dev/null; then
        log show --last "${hours}h" --predicate 'process == "kernel" OR process == "sshd" OR process == "sudo"' 2>/dev/null | head -1000 > "$LOG_DIR/unified_$(date +%Y%m%d_%H%M%S).txt" || true
    fi
    
    # Aggregate from application logs
    if [ -d "$LOG_DIR" ]; then
        find "$LOG_DIR" -name "*.log" -type f -mtime -$((hours / 24 + 1)) -exec cat {} \; 2>/dev/null | head -5000 >> "$LOG_DIR/combined_$(date +%Y%m%d_%H%M%S).txt" || true
    fi
}

# Main execution
aggregate_logs "${1:-$AGGREGATED_LOG}" "${2:-24}"

