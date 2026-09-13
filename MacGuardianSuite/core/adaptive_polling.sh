#!/bin/bash
# ===============================
# Adaptive Polling System
# Reduces CPU load by adjusting intervals based on activity
# ===============================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUITE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SUITE_DIR/core/logging.sh" 2>/dev/null || true

# Polling intervals (in seconds)
MIN_INTERVAL=1      # High activity
MAX_INTERVAL=20     # Low activity
DEFAULT_INTERVAL=5  # Normal activity

# Activity thresholds
HIGH_ACTIVITY_THRESHOLD=50   # Events per minute
LOW_ACTIVITY_THRESHOLD=5     # Events per minute

# Cooldown window
COOLDOWN_WINDOW=3            # seconds
COOLDOWN_THRESHOLD=200       # events in window
COOLDOWN_RATE=1              # events per second when throttled

# State tracking
ACTIVITY_LOG="$HOME/.macguardian/activity.log"
LAST_INTERVAL="$DEFAULT_INTERVAL"
THROTTLE_UNTIL=0

# Get current activity level (events per minute)
get_activity_level() {
    local now=$(date +%s)
    local one_minute_ago=$((now - 60))
    
    if [ ! -f "$ACTIVITY_LOG" ]; then
        echo "0"
        return
    fi
    
    # Count events in last minute
    local count=$(awk -v cutoff="$one_minute_ago" '$1 > cutoff {count++} END {print count+0}' "$ACTIVITY_LOG" 2>/dev/null || echo "0")
    echo "$count"
}

# Record activity event
record_activity() {
    local timestamp=$(date +%s)
    echo "$timestamp" >> "$ACTIVITY_LOG"
    
    # Trim log to last 5 minutes
    local five_minutes_ago=$((timestamp - 300))
    awk -v cutoff="$five_minutes_ago" '$1 > cutoff' "$ACTIVITY_LOG" > "$ACTIVITY_LOG.tmp" 2>/dev/null || true
    mv "$ACTIVITY_LOG.tmp" "$ACTIVITY_LOG" 2>/dev/null || true
}

# Calculate adaptive interval
calculate_interval() {
    local activity=$(get_activity_level)
    local current_time=$(date +%s)
    
    # Check if throttled
    if [ "$current_time" -lt "$THROTTLE_UNTIL" ]; then
        echo "$COOLDOWN_RATE"
        return
    fi
    
    # Check for cooldown trigger
    local recent_events=$(awk -v cutoff=$((current_time - COOLDOWN_WINDOW)) '$1 > cutoff {count++} END {print count+0}' "$ACTIVITY_LOG" 2>/dev/null || echo "0")
    
    if [ "$recent_events" -ge "$COOLDOWN_THRESHOLD" ]; then
        THROTTLE_UNTIL=$((current_time + COOLDOWN_WINDOW))
        echo "$COOLDOWN_RATE"
        return
    fi
    
    # Adaptive interval based on activity
    if [ "$activity" -ge "$HIGH_ACTIVITY_THRESHOLD" ]; then
        echo "$MIN_INTERVAL"
    elif [ "$activity" -le "$LOW_ACTIVITY_THRESHOLD" ]; then
        echo "$MAX_INTERVAL"
    else
        # Linear interpolation
        local ratio=$((activity - LOW_ACTIVITY_THRESHOLD))
        local range=$((HIGH_ACTIVITY_THRESHOLD - LOW_ACTIVITY_THRESHOLD))
        local interval=$((MIN_INTERVAL + (MAX_INTERVAL - MIN_INTERVAL) * (range - ratio) / range))
        echo "$interval"
    fi
}

# Get next polling interval
get_interval() {
    local interval=$(calculate_interval)
    LAST_INTERVAL="$interval"
    echo "$interval"
}

# Initialize activity log
init_activity_log() {
    mkdir -p "$(dirname "$ACTIVITY_LOG")"
    touch "$ACTIVITY_LOG"
}

# Main function
main() {
    local command="${1:-interval}"
    
    case "$command" in
        "interval")
            init_activity_log
            get_interval
            ;;
        "record")
            record_activity
            ;;
        "activity")
            get_activity_level
            ;;
        *)
            echo "Usage: adaptive_polling.sh [interval|record|activity]"
            exit 1
            ;;
    esac
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi

