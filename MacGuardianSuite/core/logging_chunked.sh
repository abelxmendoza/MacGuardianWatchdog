#!/bin/bash
# ===============================
# Chunked Logging System
# Writes logs in batches to reduce disk I/O
# ===============================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUITE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SUITE_DIR/core/logging.sh" 2>/dev/null || true

# Chunk configuration
CHUNK_SIZE=100        # Lines per chunk
CHUNK_INTERVAL=1      # Seconds between flushes
LOG_BUFFER_DIR="$HOME/.macguardian/log_buffers"

# Initialize chunk buffers
init_chunk_buffers() {
    mkdir -p "$LOG_BUFFER_DIR"
}

# Get buffer file for a log type
get_buffer_file() {
    local log_type="$1"
    echo "$LOG_BUFFER_DIR/${log_type}.buffer"
}

# Add log entry to buffer
chunk_log() {
    local log_type="$1"
    local level="$2"
    shift 2
    local message="$*"
    
    local buffer_file=$(get_buffer_file "$log_type")
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # Append to buffer
    echo "[$timestamp] [$level] $message" >> "$buffer_file"
    
    # Check if buffer needs flushing
    local line_count=$(wc -l < "$buffer_file" 2>/dev/null || echo "0")
    if [ "$line_count" -ge "$CHUNK_SIZE" ]; then
        flush_chunk "$log_type"
    fi
}

# Flush chunk to actual log file
flush_chunk() {
    local log_type="$1"
    local buffer_file=$(get_buffer_file "$log_type")
    
    if [ ! -f "$buffer_file" ] || [ ! -s "$buffer_file" ]; then
        return
    fi
    
    # Determine target log file
    local log_file
    case "$log_type" in
        "watcher") log_file="$HOME/.macguardian/logs/watcher.log" ;;
        "auditor") log_file="$HOME/.macguardian/logs/auditor.log" ;;
        "detector") log_file="$HOME/.macguardian/logs/detector.log" ;;
        "core") log_file="$HOME/.macguardian/logs/core.log" ;;
        *) log_file="$HOME/.macguardian/logs/system.log" ;;
    esac
    
    # Ensure log directory exists
    mkdir -p "$(dirname "$log_file")"
    
    # Append buffer to log file
    cat "$buffer_file" >> "$log_file"
    
    # Clear buffer
    > "$buffer_file"
}

# Flush all buffers
flush_all_chunks() {
    for buffer_file in "$LOG_BUFFER_DIR"/*.buffer; do
        if [ -f "$buffer_file" ]; then
            local log_type=$(basename "$buffer_file" .buffer)
            flush_chunk "$log_type"
        fi
    done
}

# Background flush daemon
start_flush_daemon() {
    (
        while true; do
            sleep "$CHUNK_INTERVAL"
            flush_all_chunks
        done
    ) &
    echo $!
}

# Initialize on load
init_chunk_buffers

# Export functions
export -f chunk_log
export -f flush_chunk
export -f flush_all_chunks

