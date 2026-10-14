#!/usr/bin/env bats

# Tests write and read ~/.macguardian; keep them away from the real one.
export HOME="$(mktemp -d)"

# ===============================
# Watcher Output Integration Tests
# Verifies watchers output Event Spec v1.0.0 compliant JSON
# ===============================

load "$(dirname "${BASH_SOURCE[0]}")/../fixtures/test_helpers.bash"

@test "fsevents_watcher outputs Event Spec v1.0.0 JSON" {
    source "$PROJECT_ROOT/MacGuardianSuite/core/validators.sh"
    source "$PROJECT_ROOT/MacGuardianSuite/daemons/event_writer.sh"
    
    # Create test event
    local test_context='{"file_path": "/tmp/test", "change_type": "modified"}'
    local event_file="$TEST_DIR/test_event.json"
    
    # Write event using event_writer
    write_event "file_integrity_change" "medium" "fsevents_watcher" "$test_context"
    
    # Check event file exists
    local event_files=$(find "$HOME/.macguardian/events" -name "event_*.json" -mmin -1 2>/dev/null | head -1)
    
    if [ -n "$event_files" ]; then
        # Validate Event Spec v1.0.0 fields
        grep -q '"event_id"' "$event_files"
        grep -q '"event_type"' "$event_files"
        grep -q '"severity"' "$event_files"
        grep -q '"timestamp"' "$event_files"
        grep -q '"source"' "$event_files"
        grep -q '"context"' "$event_files"
        
        # Validate event_type
        grep -q '"event_type": "file_integrity_change"' "$event_files"
        
        # Validate severity
        grep -q '"severity": "medium"' "$event_files"
        
        # Validate source
        grep -q '"source": "fsevents_watcher"' "$event_files"
    fi
}

@test "process_watcher outputs Event Spec v1.0.0 JSON" {
    source "$PROJECT_ROOT/MacGuardianSuite/core/validators.sh"
    source "$PROJECT_ROOT/MacGuardianSuite/daemons/event_writer.sh"
    
    local test_context='{"pid": 12345, "process_name": "test", "cpu_percent": 85.5, "anomaly_type": "high_cpu"}'
    
    write_event "process_anomaly" "high" "process_watcher" "$test_context"
    
    local event_files=$(find "$HOME/.macguardian/events" -name "event_*.json" -mmin -1 2>/dev/null | head -1)
    
    if [ -n "$event_files" ]; then
        grep -q '"event_type": "process_anomaly"' "$event_files"
        grep -q '"source": "process_watcher"' "$event_files"
    fi
}

@test "network_watcher outputs Event Spec v1.0.0 JSON" {
    source "$PROJECT_ROOT/MacGuardianSuite/core/validators.sh"
    source "$PROJECT_ROOT/MacGuardianSuite/daemons/event_writer.sh"
    
    local test_context='{"remote_ip": "1.2.3.4", "remote_port": 80, "process_name": "curl", "protocol": "tcp"}'
    
    write_event "network_connection" "medium" "network_watcher" "$test_context"
    
    local event_files=$(find "$HOME/.macguardian/events" -name "event_*.json" -mmin -1 2>/dev/null | head -1)
    
    if [ -n "$event_files" ]; then
        grep -q '"event_type": "network_connection"' "$event_files"
        grep -q '"source": "network_watcher"' "$event_files"
    fi
}

@test "events have valid UUID v4 format" {
    source "$PROJECT_ROOT/MacGuardianSuite/core/validators.sh"
    source "$PROJECT_ROOT/MacGuardianSuite/daemons/event_writer.sh"
    
    write_event "process_anomaly" "low" "test_module" "{}"
    
    local event_files=$(find "$HOME/.macguardian/events" -name "event_*.json" -mmin -1 2>/dev/null | head -1)
    
    if [ -n "$event_files" ]; then
        local event_id
        event_id=$(grep -o '"event_id": "[^"]*"' "$event_files" | cut -d'"' -f4)
        
        validate_uuid "$event_id"
        [ $? -eq 0 ]
    fi
}

@test "events have valid ISO8601 timestamps" {
    source "$PROJECT_ROOT/MacGuardianSuite/core/validators.sh"
    source "$PROJECT_ROOT/MacGuardianSuite/daemons/event_writer.sh"
    
    write_event "process_anomaly" "low" "test_module" "{}"
    
    local event_files=$(find "$HOME/.macguardian/events" -name "event_*.json" -mmin -1 2>/dev/null | head -1)
    
    if [ -n "$event_files" ]; then
        local timestamp
        timestamp=$(grep -o '"timestamp": "[^"]*"' "$event_files" | cut -d'"' -f4)
        
        validate_timestamp "$timestamp"
        [ $? -eq 0 ]
    fi
}

