#!/bin/bash

# ===============================
# Network Deep Audit
# Advanced network security monitoring
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
NETWORK_BASELINE="$BASELINE_DIR/network_baseline.json"
AUDIT_OUTPUT="$HOME/.macguardian/audits/network_deep_$(date +%Y%m%d_%H%M%S).json"
THREAT_INTEL_DB="$HOME/.macguardian/threat_intel/iocs.json"

mkdir -p "$BASELINE_DIR" "$(dirname "$AUDIT_OUTPUT")"

# Initialize network baseline
init_network_baseline() {
    if [ ! -f "$NETWORK_BASELINE" ]; then
        log_auditor "network_deep_audit" "INFO" "Creating network baseline..."
        
        local connections="[]"
        local dns_servers="[]"
        local routing_table="[]"
        local arp_table="[]"
        
        # Get DNS servers
        if [ -f "/etc/resolv.conf" ]; then
            local dns_list="["
            local first=true
            grep "^nameserver" /etc/resolv.conf 2>/dev/null | awk '{print $2}' | while IFS= read -r dns; do
                if [ -n "$dns" ]; then
                    if [ "$first" = true ]; then
                        first=false
                    else
                        dns_list="$dns_list,"
                    fi
                    dns_list="$dns_list\"$dns\""
                fi
            done
            dns_list="$dns_list]"
            dns_servers="$dns_list"
        fi
        
        # Get routing table hash
        local route_hash=""
        if command -v netstat &> /dev/null; then
            route_hash=$(netstat -rn 2>/dev/null | shasum -a 256 | cut -d' ' -f1 || echo "")
        fi
        
        # Get ARP table hash
        local arp_hash=""
        if command -v arp &> /dev/null; then
            arp_hash=$(arp -a 2>/dev/null | shasum -a 256 | cut -d' ' -f1 || echo "")
        fi
        
        cat > "$NETWORK_BASELINE" <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "dns_servers": $dns_servers,
  "routing_table_hash": "$route_hash",
  "arp_table_hash": "$arp_hash"
}
EOF
        
        log_auditor "network_deep_audit" "INFO" "Network baseline created"
    fi
}

# Audit network configuration
audit_network_deep() {
    local issues=0
    
    # Load baseline
    if [ ! -f "$NETWORK_BASELINE" ]; then
        init_network_baseline
        return 0
    fi
    
    # Check DNS server changes
    if [ -f "/etc/resolv.conf" ]; then
        local current_dns="["
        local first=true
        grep "^nameserver" /etc/resolv.conf 2>/dev/null | awk '{print $2}' | while IFS= read -r dns; do
            if [ -n "$dns" ]; then
                if [ "$first" = true ]; then
                    first=false
                else
                    current_dns="$current_dns,"
                fi
                current_dns="$current_dns\"$dns\""
            fi
        done
        current_dns="$current_dns]"
        
        local baseline_dns=$(grep -o '"dns_servers":\[[^\]]*\]' "$NETWORK_BASELINE" 2>/dev/null || echo "[]")
        
        if [ "$current_dns" != "$baseline_dns" ]; then
            issues=$((issues + 1))
            
            # Emit Event Spec v1.0.0 event
            local context_json="{\"change_type\": \"dns_servers_changed\", \"baseline_dns\": $baseline_dns, \"current_dns\": $current_dns}"
            write_event "network_connection" "medium" "network_deep_audit" "$context_json"
            log_auditor "network_deep_audit" "WARNING" "DNS servers changed"
        fi
    fi
    
    # Check routing table changes
    if command -v netstat &> /dev/null; then
        local current_route_hash=$(netstat -rn 2>/dev/null | shasum -a 256 | cut -d' ' -f1 || echo "")
        local baseline_route_hash=$(grep -o '"routing_table_hash":"[^"]*"' "$NETWORK_BASELINE" 2>/dev/null | cut -d'"' -f4 || echo "")
        
        if [ -n "$baseline_route_hash" ] && [ "$current_route_hash" != "$baseline_route_hash" ]; then
            issues=$((issues + 1))
            
            # Emit Event Spec v1.0.0 event
            local context_json="{\"change_type\": \"routing_table_modified\", \"old_hash\": \"$baseline_route_hash\", \"new_hash\": \"$current_route_hash\"}"
            write_event "network_connection" "high" "network_deep_audit" "$context_json"
            log_auditor "network_deep_audit" "WARNING" "Routing table modified"
        fi
    fi
    
    # Check ARP table changes
    if command -v arp &> /dev/null; then
        local current_arp_hash=$(arp -a 2>/dev/null | shasum -a 256 | cut -d' ' -f1 || echo "")
        local baseline_arp_hash=$(grep -o '"arp_table_hash":"[^"]*"' "$NETWORK_BASELINE" 2>/dev/null | cut -d'"' -f4 || echo "")
        
        if [ -n "$baseline_arp_hash" ] && [ "$current_arp_hash" != "$baseline_arp_hash" ]; then
            issues=$((issues + 1))
            
            # Emit Event Spec v1.0.0 event
            local context_json="{\"change_type\": \"arp_table_modified\", \"old_hash\": \"$baseline_arp_hash\", \"new_hash\": \"$current_arp_hash\"}"
            write_event "network_connection" "medium" "network_deep_audit" "$context_json"
            log_auditor "network_deep_audit" "WARNING" "ARP table modified"
        fi
    fi
    
    # Check for listening ports
    local listening_ports=0
    if command -v lsof &> /dev/null; then
        listening_ports=$( (lsof -i -P -n 2>/dev/null | grep LISTEN | wc -l | tr -d ' ' || echo "0") | head -1)
    fi
    
    # Check for suspicious connections
    local suspicious_conns=0
    if [ -f "$THREAT_INTEL_DB" ] && command -v lsof &> /dev/null && command -v jq &> /dev/null; then
        lsof -i -P -n 2>/dev/null | grep ESTABLISHED | while IFS= read -r line; do
            local remote_ip=$(echo "$line" | awk '{print $9}' | cut -d: -f1)
            if [ -n "$remote_ip" ]; then
                local threat_match=$(jq -r ".[] | select(.type == \"ip\" and .value == \"$remote_ip\") | .value" "$THREAT_INTEL_DB" 2>/dev/null | head -1)
                if [ -n "$threat_match" ]; then
                    suspicious_conns=$((suspicious_conns + 1))
                    
                    # Emit Event Spec v1.0.0 event
                    local context_json="{\"change_type\": \"suspicious_connection\", \"remote_ip\": \"$remote_ip\", \"threat_source\": \"threat_intel_db\"}"
                    write_event "network_connection" "critical" "network_deep_audit" "$context_json"
                fi
            fi
        done
    fi
    
    # Output JSON
    cat > "$AUDIT_OUTPUT" <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "audit_type": "network_deep",
  "issues_found": $issues,
  "listening_ports": $listening_ports,
  "suspicious_connections": $suspicious_conns
}
EOF
    
    if [ $issues -eq 0 ]; then
        log_auditor "network_deep_audit" "INFO" "Network deep audit completed - no issues found"
    else
        log_auditor "network_deep_audit" "WARNING" "Network deep audit completed - $issues issue(s) found"
    fi
    
    return $issues
}

# Check privileges on load
if ! check_privileges "audit"; then
    log_auditor "network_deep_audit" "WARNING" "Some network audit checks may require sudo privileges"
fi

# Main execution
if [ "${1:-audit}" = "baseline" ]; then
    init_network_baseline
else
    audit_network_deep
fi

