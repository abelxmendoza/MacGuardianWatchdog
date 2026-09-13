#!/bin/zsh

# ===============================
# MacGuardian Real-Time Monitor (Enhanced)
# Main event loop daemon for 24/7 monitoring
# ===============================

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUITE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source core utilities
source "$SUITE_DIR/utils.sh" 2>/dev/null || true
source "$SUITE_DIR/config.sh" 2>/dev/null || true

# Configuration directories
EVENT_DIR="$HOME/.macguardian/events"
LOG_DIR="$HOME/.macguardian/logs"
BASELINE_DIR="$HOME/.macguardian/baselines"
REALTIME_LOG="$LOG_DIR/realtime.log"

mkdir -p "$EVENT_DIR" "$LOG_DIR" "$BASELINE_DIR"

# PID file
PID_FILE="$HOME/.macguardian/.monitor.pid"

# Logging function
function log_realtime() {
    local level="${2:-INFO}"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$level] $1" | tee -a "$REALTIME_LOG"
}

# Trap signals for graceful shutdown
trap 'log_realtime "Monitor daemon shutting down..." "INFO"; exit 0' TERM INT

# Check if already running
if [ -f "$PID_FILE" ]; then
    local old_pid=$(cat "$PID_FILE" 2>/dev/null || echo "")
    if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
        log_realtime "Monitor daemon already running (PID: $old_pid)" "WARNING"
        exit 1
    fi
fi

# Write PID file
echo $$ > "$PID_FILE"

# Source watcher modules
source "$SCRIPT_DIR/fsevents_watcher.sh" 2>/dev/null || {
    log_realtime "Failed to load fsevents_watcher.sh" "ERROR"
    exit 1
}

source "$SCRIPT_DIR/process_watcher.sh" 2>/dev/null || {
    log_realtime "Failed to load process_watcher.sh" "ERROR"
    exit 1
}

source "$SCRIPT_DIR/network_watcher.sh" 2>/dev/null || {
    log_realtime "Failed to load network_watcher.sh" "ERROR"
    exit 1
}

# Source IDS engine if available
if [ -f "$SUITE_DIR/detectors/ids_engine.sh" ]; then
    source "$SUITE_DIR/detectors/ids_engine.sh" 2>/dev/null || true
fi

# Source event writer
source "$SCRIPT_DIR/event_writer.sh" 2>/dev/null || {
    log_realtime "Failed to load event_writer.sh" "ERROR"
    exit 1
}

log_realtime "🚀 MacGuardian Monitor starting (PID: $$)" "INFO"
log_realtime "Event directory: $EVENT_DIR" "INFO"
log_realtime "Log directory: $LOG_DIR" "INFO"

# Write startup event
write_event "system" "info" "MacGuardian Monitor daemon started" "{\"pid\": $$, \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}"

# Main event loop
LOOP_COUNT=0
LAST_IDS_CHECK=0
IDS_CHECK_INTERVAL=30  # Run IDS correlation every 30 seconds

while true; do
    LOOP_COUNT=$((LOOP_COUNT + 1))
    CURRENT_TIME=$(date +%s)
    
    # Run monitoring checks (with error handling)
    set +e  # Don't exit on errors in monitoring functions
    
    # Real-time FSEvents file change detection
    detect_fs_changes 2>&1 | while IFS= read -r line; do
        if [ -n "$line" ]; then
            log_realtime "FSEvents: $line" "DEBUG"
        fi
    done
    
    # Real-time suspicious process detection
    detect_suspicious_processes 2>&1 | while IFS= read -r line; do
        if [ -n "$line" ]; then
            log_realtime "Process: $line" "DEBUG"
        fi
    done
    
    # Real-time network anomaly detection
    detect_network_anomalies 2>&1 | while IFS= read -r line; do
        if [ -n "$line" ]; then
            log_realtime "Network: $line" "DEBUG"
        fi
    done
    
    # Run IDS correlation engine periodically
    if [ $((CURRENT_TIME - LAST_IDS_CHECK)) -ge $IDS_CHECK_INTERVAL ]; then
        if type run_ids_correlation &> /dev/null; then
            run_ids_correlation 2>&1 | while IFS= read -r line; do
                if [ -n "$line" ]; then
                    log_realtime "IDS: $line" "INFO"
                fi
            done
            LAST_IDS_CHECK=$CURRENT_TIME
        fi
    fi
    
    set -e  # Re-enable exit on error
    
    # Log heartbeat every 100 loops (~5 minutes at 3 second intervals)
    if [ $((LOOP_COUNT % 100)) -eq 0 ]; then
        log_realtime "Monitor heartbeat - Loop $LOOP_COUNT" "INFO"
    fi
    
    # Sleep for CPU friendliness (adjust based on system load)
    sleep 2
done

# Cleanup on exit
rm -f "$PID_FILE"
log_realtime "Monitor daemon stopped" "INFO"
exit 0

