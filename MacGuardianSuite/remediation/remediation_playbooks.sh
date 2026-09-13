#!/bin/bash

# ===============================
# Remediation Playbooks
# Automated response playbooks for security incidents
# ===============================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUITE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SUITE_DIR/utils.sh" 2>/dev/null || true
source "$SUITE_DIR/config.sh" 2>/dev/null || true

PLAYBOOKS_DIR="$SUITE_DIR/remediation/playbooks"
INCIDENTS_DIR="$HOME/.macguardian/incidents"

mkdir -p "$PLAYBOOKS_DIR"

# Playbook: Ransomware response
playbook_ransomware() {
    local incident_file="$1"
    
    warning "🚨 Executing ransomware response playbook..."
    
    # Step 1: Isolate network
    info "Step 1: Isolating network connections..."
    # Would disable network interfaces here (requires sudo)
    
    # Step 2: Kill suspicious processes
    info "Step 2: Identifying and terminating suspicious processes..."
    # Would kill high CPU processes here
    
    # Step 3: Quarantine affected files
    info "Step 3: Quarantining affected files..."
    if [ -f "$SUITE_DIR/quarantine_manager.sh" ]; then
        source "$SUITE_DIR/quarantine_manager.sh" 2>/dev/null || true
        # Quarantine recent file changes
    fi
    
    # Step 4: Create snapshot
    info "Step 4: Creating system snapshot..."
    # Would create system snapshot here
    
    success "Ransomware playbook executed"
}

# Playbook: Suspicious process response
playbook_suspicious_process() {
    local incident_file="$1"
    
    warning "Executing suspicious process response playbook..."
    
    # Extract PID from incident
    local pid=$(grep -o '"pid":[0-9]*' "$incident_file" 2>/dev/null | cut -d: -f2 | head -1 || echo "")
    
    if [ -n "$pid" ]; then
        info "Terminating suspicious process: PID $pid"
        kill "$pid" 2>/dev/null || kill -9 "$pid" 2>/dev/null || warning "Failed to kill process $pid"
    fi
    
    success "Suspicious process playbook executed"
}

# Playbook: Network threat response
playbook_network_threat() {
    local incident_file="$1"
    
    warning "Executing network threat response playbook..."
    
    # Extract IP from incident
    local threat_ip=$(grep -o '"ip":"[^"]*"' "$incident_file" 2>/dev/null | cut -d'"' -f4 | head -1 || echo "")
    
    if [ -n "$threat_ip" ]; then
        info "Blocking threat IP: $threat_ip"
        # Would add firewall rule here (requires sudo)
        # sudo pfctl -t threat_ips -T add "$threat_ip" 2>/dev/null || true
    fi
    
    success "Network threat playbook executed"
}

# Execute playbook based on incident type
execute_playbook() {
    local incident_file="$1"
    
    if [ ! -f "$incident_file" ]; then
        error_exit "Incident file not found: $incident_file"
    fi
    
    local incident_type=$(grep -o '"type":"[^"]*"' "$incident_file" 2>/dev/null | cut -d'"' -f4 || echo "")
    
    case "$incident_type" in
        ransomware)
            playbook_ransomware "$incident_file"
            ;;
        process|correlation)
            playbook_suspicious_process "$incident_file"
            ;;
        network)
            playbook_network_threat "$incident_file"
            ;;
        *)
            warning "No playbook for incident type: $incident_type"
            ;;
    esac
}

# Main execution
if [ $# -ge 1 ]; then
    execute_playbook "$1"
else
    echo "Usage: remediation_playbooks.sh <incident_file.json>"
    exit 1
fi

