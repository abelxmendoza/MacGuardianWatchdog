#!/bin/bash

# ===============================
# Network Watcher
# Real-time network anomaly detection
# Event Spec v1.0.0 compliant
# ===============================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUITE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source core modules
source "$SUITE_DIR/core/validators.sh" 2>/dev/null || true
source "$SUITE_DIR/core/logging.sh" 2>/dev/null || true
source "$SUITE_DIR/core/system_state.sh" 2>/dev/null || true
source "$SCRIPT_DIR/event_writer.sh" 2>/dev/null || true

# Threat intelligence database
THREAT_INTEL_DB="$HOME/.macguardian/threat_intel/iocs.json"

# Suspicious ports
SUSPICIOUS_PORTS=(4444 5555 6666 7777 8888 9999 1337 31337)

# Baseline for network connections
NETWORK_CHECK_INTERVAL=60  # Check every 60 seconds
LAST_NETWORK_CHECK="$HOME/.macguardian/.network_last_check"

function detect_network_anomalies() {
    local current_time=$(date +%s)
    local last_check=$(cat "$LAST_NETWORK_CHECK" 2>/dev/null || echo "0")
    
    # Only check every NETWORK_CHECK_INTERVAL seconds
    if [ $((current_time - last_check)) -lt $NETWORK_CHECK_INTERVAL ]; then
        return 0
    fi
    
    echo "$current_time" > "$LAST_NETWORK_CHECK"
    
    if ! command -v lsof &> /dev/null; then
        return 1
    fi
    
    # Get all established connections
    local connections=$(lsof -i -P -n 2>/dev/null | grep ESTABLISHED || true)
    
    if [ -z "$connections" ]; then
        return 0
    fi
    
    # Check each connection
    echo "$connections" | while IFS= read -r line; do
        if [ -z "$line" ]; then
            continue
        fi
        
        # Extract port and remote address
        local port=$(echo "$line" | grep -oE ':[0-9]+' | head -1 | tr -d ':' || echo "")
        local remote=$(echo "$line" | awk '{print $9}' | cut -d: -f1 || echo "")
        local process=$(echo "$line" | awk '{print $1}' || echo "")
        
        # Check suspicious ports
        for sus_port in "${SUSPICIOUS_PORTS[@]}"; do
            if [ "$port" = "$sus_port" ]; then
                # Extract PID if available
                local pid=$(echo "$line" | awk '{print $2}' 2>/dev/null || echo "")
                local context_json="{\"local_port\": $port, \"remote_ip\": \"$remote\", \"process_name\": \"$process\""
                if [ -n "$pid" ] && validate_int "$pid" 1 999999; then
                    context_json="$context_json, \"pid\": $pid"
                fi
                context_json="$context_json, \"protocol\": \"tcp\", \"connection_state\": \"ESTABLISHED\", \"suspicious_pattern\": \"known_suspicious_port\"}"
                write_event "network_connection" "high" "network_watcher" "$context_json"
                log_watcher "network_watcher" "WARNING" "Suspicious port connection: $process -> $remote:$port"
            fi
        done
        
        # Check threat intelligence database
        if [ -f "$THREAT_INTEL_DB" ] && [ -n "$remote" ]; then
            # Simple grep-based threat intel check (no jq dependency)
            if grep -q "\"$remote\"" "$THREAT_INTEL_DB" 2>/dev/null; then
                local pid=$(echo "$line" | awk '{print $2}' 2>/dev/null || echo "")
                local context_json="{\"remote_ip\": \"$remote\", \"remote_port\": $port, \"process_name\": \"$process\", \"protocol\": \"tcp\", \"connection_state\": \"ESTABLISHED\", \"threat_intel_match\": true"
                if [ -n "$pid" ] && validate_int "$pid" 1 999999; then
                    context_json="$context_json, \"pid\": $pid"
                fi
                context_json="$context_json}"
                write_event "network_connection" "critical" "network_watcher" "$context_json"
                log_watcher "network_watcher" "CRITICAL" "Threat intel match: $process -> $remote:$port"
            fi
        fi
        
        # Check for connections to private/internal IPs from suspicious processes
        if echo "$remote" | grep -qE '^(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.)' && echo "$process" | grep -qiE "(curl|nc|python|sh|bash)"; then
            local pid=$(echo "$line" | awk '{print $2}' 2>/dev/null || echo "")
            local context_json="{\"remote_ip\": \"$remote\", \"remote_port\": $port, \"process_name\": \"$process\", \"protocol\": \"tcp\", \"connection_state\": \"ESTABLISHED\", \"suspicious_pattern\": \"internal_network_from_script\""
            if [ -n "$pid" ] && validate_int "$pid" 1 999999; then
                context_json="$context_json, \"pid\": $pid"
            fi
            context_json="$context_json}"
            write_event "network_connection" "medium" "network_watcher" "$context_json"
            log_watcher "network_watcher" "INFO" "Suspicious internal connection: $process -> $remote:$port"
        fi
    done
    
    # Check for listening ports (potential backdoors)
    local listening=$(lsof -i -P -n 2>/dev/null | grep LISTEN || true)
    if [ -n "$listening" ]; then
        echo "$listening" | while IFS= read -r line; do
            local listen_port=$(echo "$line" | grep -oE ':[0-9]+' | head -1 | tr -d ':' || echo "")
            # lsof writes spaces in command names as "\x20"
            local listen_process=$(echo "$line" | awk '{print $1}' | sed 's/\\x20/ /g' || echo "")
            
            # Alert on unexpected listening ports
            if [ -n "$listen_port" ] && [ "$listen_port" -gt 1024 ] && [ "$listen_port" -lt 65535 ]; then
                # Skip known safe processes
                if echo "$listen_process" | grep -qiE "(Safari|Chrome|Firefox|Slack|Discord|Spotify|Music|Mail)"; then
                    continue
                fi
                
                # Report each process/port pair once, not on every 2-second
                # loop - otherwise one dev server floods the timeline.
                local seen_file="$HOME/.macguardian/.listening_ports_seen"
                local seen_key="$listen_process:$listen_port"
                if grep -qxF "$seen_key" "$seen_file" 2>/dev/null; then
                    continue
                fi
                echo "$seen_key" >> "$seen_file"

                local context_json="{\"local_port\": $listen_port, \"process_name\": \"$listen_process\", \"protocol\": \"tcp\", \"connection_state\": \"LISTEN\", \"suspicious_pattern\": \"unexpected_listening_port\"}"
                write_event "network_connection" "medium" "network_watcher" "$context_json"
                log_watcher "network_watcher" "INFO" "Unexpected listening port: $listen_process on $listen_port"
            fi
        done
    fi
}

# Check system compatibility on load
check_system_compatibility 2>/dev/null || true

export -f detect_network_anomalies

