#!/bin/bash
# ===============================
# Event Throughput Performance Test
# Tests Event Bus processing speed
# Expected: ≥5000 events/minute
# ===============================

set -euo pipefail

# Tests write and read ~/.macguardian; keep them away from the real one.
export HOME="$(mktemp -d)"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUITE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
OUTPUTS_DIR="$SUITE_DIR/outputs"

source "$SUITE_DIR/core/logging.sh" 2>/dev/null || true

LOG_FILE="$HOME/.macguardian/logs/performance_test.log"
mkdir -p "$(dirname "$LOG_FILE")"

# Test parameters
EVENT_COUNT=10000
BATCH_SIZE=100
EXPECTED_MIN_EVENTS_PER_MIN=5000

log_message "performance_test" "INFO" "Starting event throughput test..."
log_message "performance_test" "INFO" "Target: $EVENT_COUNT events, Expected: ≥$EXPECTED_MIN_EVENTS_PER_MIN events/minute"

# Check if event_bus.py is running
if ! pgrep -f "event_bus.py" > /dev/null; then
    log_message "performance_test" "ERROR" "Event Bus is not running. Start it with: python3 $OUTPUTS_DIR/event_bus.py"
    exit 1
fi

# Generate test events
generate_test_event() {
    local event_id=$(uuidgen 2>/dev/null || echo "test-$(date +%s%N)")
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")
    local event_type="$1"
    local severity="$2"
    
    cat <<EOF
{
  "event_id": "$event_id",
  "timestamp": "$timestamp",
  "module": "performance_test",
  "event_type": "$event_type",
  "severity": "$severity",
  "details": {
    "test": true,
    "batch_id": "$(date +%s)"
  }
}
EOF
}

# Send events via Unix Domain Socket
send_event_via_uds() {
    local event_json="$1"
    local sock_path="/tmp/macguardian.sock"
    
    if [ -S "$sock_path" ]; then
        echo "$event_json" | nc -U "$sock_path" 2>/dev/null || true
    else
        log_message "performance_test" "WARNING" "Unix Domain Socket not found: $sock_path"
        return 1
    fi
}

# Run throughput test
start_time=$(date +%s.%N)
events_sent=0
events_failed=0

log_message "performance_test" "INFO" "Sending $EVENT_COUNT events in batches of $BATCH_SIZE..."

for ((i=1; i<=EVENT_COUNT; i++)); do
    # Generate different event types for realism
    case $((i % 4)) in
        0) event_type="file_change" severity="medium" ;;
        1) event_type="process_spawn" severity="low" ;;
        2) event_type="network_connection" severity="high" ;;
        3) event_type="ids_alert" severity="critical" ;;
    esac
    
    event_json=$(generate_test_event "$event_type" "$severity")
    
    if send_event_via_uds "$event_json"; then
        events_sent=$((events_sent + 1))
    else
        events_failed=$((events_failed + 1))
    fi
    
    # Progress indicator
    if [ $((i % BATCH_SIZE)) -eq 0 ]; then
        echo -n "."
    fi
done

end_time=$(date +%s.%N)
duration=$(echo "$end_time - $start_time" | bc)
events_per_second=$(echo "scale=2; $events_sent / $duration" | bc)
events_per_minute=$(echo "scale=0; $events_per_second * 60" | bc)

echo ""
log_message "performance_test" "INFO" "Test completed"
log_message "performance_test" "INFO" "Events sent: $events_sent"
log_message "performance_test" "INFO" "Events failed: $events_failed"
log_message "performance_test" "INFO" "Duration: ${duration}s"
log_message "performance_test" "INFO" "Throughput: $events_per_second events/second"
log_message "performance_test" "INFO" "Throughput: $events_per_minute events/minute"

# Validate results
if [ "$events_per_minute" -ge "$EXPECTED_MIN_EVENTS_PER_MIN" ]; then
    log_message "performance_test" "SUCCESS" "✅ Performance target met: $events_per_minute ≥ $EXPECTED_MIN_EVENTS_PER_MIN events/minute"
    exit 0
else
    log_message "performance_test" "WARNING" "⚠️  Performance below target: $events_per_minute < $EXPECTED_MIN_EVENTS_PER_MIN events/minute"
    exit 1
fi

