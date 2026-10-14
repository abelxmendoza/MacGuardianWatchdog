#!/bin/bash

# ===============================
# Mac Guardian Suite Utilities
# Shared utility functions
# ===============================

# Color support with fallback
bold=$(tput bold 2>/dev/null || echo "")
normal=$(tput sgr0 2>/dev/null || echo "")
green=$(tput setaf 2 2>/dev/null || echo "")
red=$(tput setaf 1 2>/dev/null || echo "")
yellow=$(tput setaf 3 2>/dev/null || echo "")
blue=$(tput setaf 4 2>/dev/null || echo "")
cyan=$(tput setaf 6 2>/dev/null || echo "")

# Source error tracker if available
if [ -f "$(dirname "${BASH_SOURCE[0]}")/error_tracker.sh" ]; then
    source "$(dirname "${BASH_SOURCE[0]}")/error_tracker.sh" 2>/dev/null || true
fi

# Source debug helper if available
if [ -f "$(dirname "${BASH_SOURCE[0]}")/debug_helper.sh" ]; then
    source "$(dirname "${BASH_SOURCE[0]}")/debug_helper.sh" 2>/dev/null || true
fi

# Source performance monitor if available
if [ -f "$(dirname "${BASH_SOURCE[0]}")/performance_monitor.sh" ]; then
    source "$(dirname "${BASH_SOURCE[0]}")/performance_monitor.sh" 2>/dev/null || true
fi

# Source error recovery if available
if [ -f "$(dirname "${BASH_SOURCE[0]}")/error_recovery.sh" ]; then
    source "$(dirname "${BASH_SOURCE[0]}")/error_recovery.sh" 2>/dev/null || true
fi

# Source UX enhancer if available
if [ -f "$(dirname "${BASH_SOURCE[0]}")/ux_enhancer.sh" ]; then
    source "$(dirname "${BASH_SOURCE[0]}")/ux_enhancer.sh" 2>/dev/null || true
fi

# Error handling function with logging and tracking
error_exit() {
    local error_msg="$1"
    local exit_code="${2:-1}"
    local error_type="${3:-general}"
    local severity="${4:-high}"
    local fixable="${5:-false}"
    local fix_command="${6:-}"
    
    echo "${red}❌ Error: $error_msg${normal}" >&2
    
    # Track error in database
    if type track_error &> /dev/null; then
        track_error "$error_msg" "${BASH_SOURCE[1]:-unknown}" "${BASH_LINENO[0]:-0}" "$error_type" "$severity" "$fixable" "$fix_command"
    fi
    
    # Log the error
    log_message "ERROR" "$error_msg"
    
    # Don't exit if we're in a subshell or if CONTINUE_ON_ERROR is set
    if [ "${CONTINUE_ON_ERROR:-false}" = "true" ]; then
        return $exit_code
    fi
    
    exit $exit_code
}

# Safe error handler that doesn't exit
safe_error() {
    local error_msg="$1"
    local error_type="${2:-general}"
    local severity="${3:-medium}"
    local fixable="${4:-false}"
    local fix_command="${5:-}"
    
    echo "${red}❌ Error: $error_msg${normal}" >&2
    
    # Track error in database
    if type track_error &> /dev/null; then
        track_error "$error_msg" "${BASH_SOURCE[1]:-unknown}" "${BASH_LINENO[0]:-0}" "$error_type" "$severity" "$fixable" "$fix_command"
    fi
    
    log_message "ERROR" "$error_msg"
    return 1
}

# Try to execute a command with error handling
try_execute() {
    local description="$1"
    shift
    local cmd="$*"
    
    if [ "${VERBOSE:-false}" = "true" ]; then
        info "Executing: $description"
    fi
    
    # Execute command and capture exit code
    set +e  # Temporarily disable exit on error
    eval "$cmd"
    local exit_code=$?
    set -e  # Re-enable exit on error
    
    if [ $exit_code -ne 0 ]; then
        # Determine if this error is fixable and provide fix command
        local fixable="false"
        local fix_command=""
        local error_type="execution"
        
        # Common fixable errors
        if echo "$description" | grep -qi "permission\|chmod"; then
            fixable="true"
            fix_command="chmod +x $(echo "$cmd" | awk '{print $NF}')"
        elif echo "$description" | grep -qi "not found\|command not found"; then
            fixable="true"
            local missing_cmd=$(echo "$cmd" | awk '{print $1}')
            fix_command="brew install $missing_cmd || pip3 install $missing_cmd"
        fi
        
        safe_error "Failed to execute: $description (exit code: $exit_code)" "$error_type" "medium" "$fixable" "$fix_command"
        return $exit_code
    fi
    
    return 0
}

# Warning function
warning() {
    echo "${yellow}⚠️  $1${normal}" >&2
}

# Success function
success() {
    echo "${green}✅ $1${normal}"
}

# Info function
info() {
    echo "${blue}ℹ️  $1${normal}"
}

# Check for sudo access when needed
check_sudo() {
    if ! sudo -n true 2>/dev/null; then
        warning "This operation requires administrator privileges."
        sudo -v || error_exit "Sudo access required but not available"
    fi
}

# Send macOS notification with throttling to prevent spam
# Priority levels: "critical" (bypasses throttling) or "normal" (throttled)
send_notification() {
    local title="$1"
    local message="$2"
    local sound="${3:-true}"
    local priority="${4:-normal}"  # Default to "normal", can be "critical"
    
    # Check if notifications are disabled
    if [ "${ENABLE_NOTIFICATIONS:-true}" != "true" ]; then
        return 0
    fi
    
    # Notification throttling: prevent spam by limiting notifications
    # CRITICAL notifications ALWAYS bypass throttling for real security threats
    local NOTIFICATION_COOLDOWN="${NOTIFICATION_COOLDOWN:-300}"  # 5 minutes default
    local NOTIFICATION_LOG="${NOTIFICATION_LOG:-$HOME/.macguardian/notification_log.txt}"
    local last_notification_time=0
    local current_time=$(date +%s)
    local bypass_throttle=false
    
    # Critical security alerts bypass throttling
    if [ "$priority" = "critical" ]; then
        bypass_throttle=true
        if [ "${VERBOSE:-false}" = "true" ]; then
            info "Critical security alert - bypassing notification throttling"
        fi
    fi
    
    # Create notification log directory if it doesn't exist
    mkdir -p "$(dirname "$NOTIFICATION_LOG")" 2>/dev/null || true
    
    # Check last notification time (only for non-critical notifications)
    if [ "$bypass_throttle" != "true" ] && [ -f "$NOTIFICATION_LOG" ]; then
        last_notification_time=$(head -1 "$NOTIFICATION_LOG" 2>/dev/null | awk '{print $1}' || echo "0")
        local time_since_last=$((current_time - last_notification_time))
        
        # If notification was sent recently, skip it (unless it's a critical alert)
        if [ $time_since_last -lt $NOTIFICATION_COOLDOWN ]; then
            local remaining=$((NOTIFICATION_COOLDOWN - time_since_last))
            if [ "${VERBOSE:-false}" = "true" ]; then
                info "Notification throttled (cooldown: ${remaining}s remaining)"
            fi
            # Log the throttled notification for debugging
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] THROTTLED: $title - $message" >> "$NOTIFICATION_LOG" 2>/dev/null || true
            return 0
        fi
    fi
    
    # Send notification with error handling
    if command -v osascript &> /dev/null; then
        local sound_cmd=""
        if [ "$sound" = "true" ]; then
            sound_cmd='sound name "Glass"'
        fi
        
        # Escape special characters in message for osascript
        # Remove emojis and special chars that might break notifications
        local clean_message=$(echo "$message" | sed "s/\"/\\\\\"/g" | sed "s/⚠️/warning/g" | sed "s/🚨/ALERT/g" | sed "s/✅/OK/g" | sed "s/🔒/LOCK/g" | sed "s/🔍/SEARCH/g" | sed "s/📋/INFO/g")
        local clean_title=$(echo "$title" | sed "s/\"/\\\\\"/g" | sed "s/⚠️/warning/g" | sed "s/🚨/ALERT/g")
        
        # Try to send notification, catch any errors
        if osascript -e "display notification \"$clean_message\" with title \"$clean_title\" $sound_cmd" 2>/dev/null; then
            # Log successful notification with timestamp and priority
            local priority_tag=""
            if [ "$priority" = "critical" ]; then
                priority_tag=" [CRITICAL]"
            fi
            echo "$current_time [$(date '+%Y-%m-%d %H:%M:%S')] SENT$priority_tag: $title - $message" >> "$NOTIFICATION_LOG" 2>/dev/null || true
            return 0
        else
            # Log failed notification attempt
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] FAILED: $title - $message" >> "$NOTIFICATION_LOG" 2>/dev/null || true
            return 1
        fi
    else
        # osascript not available, log it
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] SKIPPED (osascript not available): $title - $message" >> "$NOTIFICATION_LOG" 2>/dev/null || true
        return 1
    fi
}

# Log message with timestamp and error handling
log_message() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "unknown")
    local log_file="${LOG_DIR:-$HOME/.macguardian/logs}/macguardian.log"
    
    # Create log directory if it doesn't exist (with error handling)
    mkdir -p "$(dirname "$log_file")" 2>/dev/null || {
        # Fallback to home directory if we can't create the log directory
        log_file="$HOME/macguardian.log"
    }
    
    # Try to write to log file, but don't fail if we can't
    echo "[$timestamp] [$level] $message" >> "$log_file" 2>/dev/null || {
        # If logging fails, at least try to write to a fallback location
        echo "[$timestamp] [$level] $message" >> "$HOME/.macguardian_fallback.log" 2>/dev/null || true
    }
}

# Generate HTML report header
report_header() {
    local title="$1"
    local output_file="$2"
    
    cat > "$output_file" <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>$title</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; margin: 20px; background: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background: white; padding: 30px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        h1 { color: #333; border-bottom: 3px solid #007AFF; padding-bottom: 10px; }
        h2 { color: #555; margin-top: 30px; }
        .success { color: #28a745; }
        .warning { color: #ffc107; }
        .error { color: #dc3545; }
        .info { color: #17a2b8; }
        table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        th, td { padding: 12px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background-color: #007AFF; color: white; }
        tr:hover { background-color: #f5f5f5; }
        .timestamp { color: #666; font-size: 0.9em; }
        .badge { display: inline-block; padding: 4px 8px; border-radius: 4px; font-size: 0.85em; font-weight: bold; }
        .badge-success { background: #28a745; color: white; }
        .badge-warning { background: #ffc107; color: #333; }
        .badge-error { background: #dc3545; color: white; }
    </style>
</head>
<body>
    <div class="container">
        <h1>$title</h1>
        <p class="timestamp">Generated: $(date '+%Y-%m-%d %H:%M:%S')</p>
EOF
}

# Generate HTML report footer
report_footer() {
    local output_file="$1"
    
    cat >> "$output_file" <<EOF
    </div>
</body>
</html>
EOF
}

# Add section to HTML report
report_section() {
    local title="$1"
    local content="$2"
    local output_file="$3"
    
    cat >> "$output_file" <<EOF
        <h2>$title</h2>
        $content
EOF
}

# Check disk space
check_disk_space() {
    local threshold="${1:-80}"  # Default 80% threshold
    local disk_usage=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
    
    if [ "$disk_usage" -gt "$threshold" ]; then
        warning "Disk usage is at ${disk_usage}% (threshold: ${threshold}%)"
        return 1
    else
        success "Disk usage is at ${disk_usage}%"
        return 0
    fi
}

# Check for suspicious processes (optimized with fast_process_search)
check_suspicious_processes() {
    local suspicious_count=0
    local suspicious_procs=()
    
    # Use advanced algorithms if available
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -f "$SCRIPT_DIR/algorithms.sh" ]; then
        source "$SCRIPT_DIR/algorithms.sh"
        
        # Use multi-pattern matching for efficiency
        local patterns=("miner" "crypto" "bitcoin" "malware" "virus" "trojan" "backdoor")
        local all_procs=$(ps aux 2>/dev/null || true)
        
        for pattern in "${patterns[@]}"; do
            local matches=$(fast_process_search "$pattern")
            if [ -n "$matches" ]; then
                while IFS= read -r line; do
                    if [ -n "$line" ]; then
                        suspicious_procs+=("$line")
                        suspicious_count=$((suspicious_count + 1))
                    fi
                done <<< "$matches"
            fi
        done
    else
        # Fallback to standard method
        while IFS= read -r line; do
            if [ -n "$line" ]; then
                suspicious_procs+=("$line")
                suspicious_count=$((suspicious_count + 1))
            fi
        done < <(ps aux | grep -iE "(miner|crypto|bitcoin|malware|virus|trojan)" | grep -v grep || true)
    fi
    
    if [ $suspicious_count -gt 0 ]; then
        warning "Found $suspicious_count potentially suspicious process(es)"
        printf '%s\n' "${suspicious_procs[@]}"
        return 1
    else
        success "No suspicious processes detected"
        return 0
    fi
}

# Check network connections (optimized)
# NOTE: This does NOT wiretap or inspect packet content
# It only checks connection metadata (IPs, ports, process names)
check_network_connections() {
    # Check privacy mode
    if [ -f "$(dirname "${BASH_SOURCE[0]}")/privacy_mode.sh" ]; then
        source "$(dirname "${BASH_SOURCE[0]}")/privacy_mode.sh" 2>/dev/null || true
        load_privacy_settings 2>/dev/null || true
        if [ "${MONITOR_NETWORK:-true}" = "false" ]; then
            info "Network monitoring disabled (privacy mode)"
            return 0
        fi
    fi
    
    local suspicious_conns=0
    
    # Check for unusual outbound connections
    # NOTE: lsof only shows connection metadata, NOT packet content
    # This is NOT wiretapping - just like netstat or Activity Monitor
    if command -v lsof &> /dev/null; then
        # Cache lsof output to avoid multiple calls
        local lsof_output=$(lsof -i -P -n 2>/dev/null)
        local conn_count=$( (echo "$lsof_output" | grep -c ESTABLISHED || echo "0") | head -1)
        info "Active network connections: $conn_count (metadata only, no content inspection)"
        
        # Use optimized pattern matching
        SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        if [ -f "$SCRIPT_DIR/algorithms.sh" ]; then
            source "$SCRIPT_DIR/algorithms.sh"
            local patterns=(":4444" ":5555" ":6666" ":7777" ":8888" ":9999" ":1337" ":31337")
            local established=$(echo "$lsof_output" | grep ESTABLISHED || true)
            
            if [ -n "$established" ]; then
                for pattern in "${patterns[@]}"; do
                    if echo "$established" | grep -q "$pattern"; then
                        local matches=$(echo "$established" | grep "$pattern")
                        warning "Suspicious network connections detected on port $pattern"
                        echo "$matches"
                        suspicious_conns=$((suspicious_conns + 1))
                    fi
                done
            fi
        else
            # Fallback to standard method
            local suspicious=$(echo "$lsof_output" | grep -E ':(4444|5555|6666|7777|8888|9999|1337|31337)' | grep ESTABLISHED || true)
            if [ -n "$suspicious" ]; then
                warning "Suspicious network connections detected"
                echo "$suspicious"
                suspicious_conns=1
            fi
        fi
    fi
    
    if [ $suspicious_conns -gt 0 ]; then
        return 1
    fi
    
    return 0
}

# Check file permissions
check_file_permissions() {
    local dir="$1"
    local issues=0
    
    if [ ! -d "$dir" ]; then
        return 0
    fi
    
    # Find world-writable files
    while IFS= read -r -d '' file; do
        if [ -f "$file" ]; then
            local perms=$(stat -f "%OLp" "$file" 2>/dev/null || echo "000")
            if [ "${perms:2:1}" = "w" ]; then
                warning "World-writable file: $file"
                issues=$((issues + 1))
            fi
        fi
    done < <(find "$dir" -type f -perm -002 -print0 2>/dev/null)
    
    if [ $issues -eq 0 ]; then
        success "No permission issues found in $dir"
        return 0
    else
        warning "Found $issues permission issue(s)"
        return 1
    fi
}

# Parse command line arguments
parse_args() {
    INTERACTIVE=true
    VERBOSE=false
    QUIET=false
    SKIP_UPDATES=false
    SKIP_SCAN=false
    GENERATE_REPORT=false
    PARALLEL_JOBS=""
    RESUME=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -y|--yes|--non-interactive)
                INTERACTIVE=false
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -q|--quiet)
                QUIET=true
                VERBOSE=false
                shift
                ;;
            --skip-updates)
                SKIP_UPDATES=true
                shift
                ;;
            --skip-scan)
                SKIP_SCAN=true
                shift
                ;;
            --report)
                GENERATE_REPORT=true
                shift
                ;;
            --parallel)
                PARALLEL_JOBS="$2"
                shift 2
                ;;
            --resume)
                RESUME=true
                shift
                ;;
            *)
                echo "Unknown option: $1" >&2
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
    
    # Initialize parallel processing if enabled
    if [ -n "$PARALLEL_JOBS" ] || [ "${ENABLE_PARALLEL:-true}" = true ]; then
        init_parallel
    fi
}

# Show help message
show_help() {
    cat <<EOF
${bold}Mac Guardian Suite${normal}

Usage: $0 [OPTIONS]

Options:
    -h, --help              Show this help message
    -y, --yes, --non-interactive
                            Run without prompts (use defaults)
    -v, --verbose           Show detailed output
    -q, --quiet             Suppress non-essential output
    --skip-updates          Skip system and Homebrew updates
    --skip-scan             Skip antivirus and rootkit scans
    --report                Generate HTML report
    --parallel N            Run with N parallel jobs (default: auto-detect)

Examples:
    $0                      # Interactive mode
    $0 -y                   # Non-interactive mode
    $0 -v --report          # Verbose with report generation
    $0 --skip-scan          # Skip time-consuming scans
    $0 --parallel 4         # Use 4 parallel jobs

For more information, visit: https://github.com/your-repo
EOF
}

# ===============================
# Parallel Processing Functions
# ===============================

# Get optimal number of parallel jobs (CPU cores)
get_parallel_jobs() {
    local default="${PARALLEL_JOBS:-}"
    if [ -n "$default" ]; then
        echo "$default"
        return
    fi
    
    # Auto-detect CPU cores
    if command -v sysctl &> /dev/null; then
        local cores=$(sysctl -n hw.ncpu 2>/dev/null || echo "2")
        echo "$cores"
    else
        echo "2"  # Fallback to 2
    fi
}

# Job pool manager for parallel execution
declare -a JOB_PIDS=()
declare -a JOB_NAMES=()
MAX_PARALLEL_JOBS=$(get_parallel_jobs)
ACTIVE_JOBS=0

# Wait for a job slot to become available
wait_for_job_slot() {
    while [ $ACTIVE_JOBS -ge $MAX_PARALLEL_JOBS ]; do
        # Check for completed jobs
        local new_pids=()
        local new_names=()
        local i=0
        
        while [ $i -lt ${#JOB_PIDS[@]} ]; do
            local pid="${JOB_PIDS[$i]}"
            local name="${JOB_NAMES[$i]}"
            
            if kill -0 "$pid" 2>/dev/null; then
                # Job still running
                new_pids+=("$pid")
                new_names+=("$name")
            else
                # Job completed
                wait "$pid" 2>/dev/null
                ACTIVE_JOBS=$((ACTIVE_JOBS - 1))
            fi
            i=$((i + 1))
        done
        
        JOB_PIDS=("${new_pids[@]}")
        JOB_NAMES=("${new_names[@]}")
        
        if [ $ACTIVE_JOBS -ge $MAX_PARALLEL_JOBS ]; then
            sleep 0.1  # Brief pause before checking again
        fi
    done
}

# Run a function in parallel
run_parallel() {
    local job_name="$1"
    shift
    local job_command="$*"
    
    wait_for_job_slot
    
    # Run job in background
    (
        eval "$job_command"
    ) &
    
    local pid=$!
    JOB_PIDS+=("$pid")
    JOB_NAMES+=("$job_name")
    ACTIVE_JOBS=$((ACTIVE_JOBS + 1))
    
    if [ "${VERBOSE:-false}" = "true" ]; then
        info "Started parallel job: $job_name (PID: $pid)"
    fi
    
    echo "$pid"
}

# Wait for all parallel jobs to complete
wait_all_jobs() {
    local total_jobs=${#JOB_PIDS[@]}
    local completed=0
    # Allow longer timeout for Blue Team operations (they do heavy filesystem scans)
    local max_wait="${PARALLEL_JOB_TIMEOUT:-60}"  # Default 60s, can be overridden
    local force_kill_after=$((max_wait + 30))  # Force kill after timeout + 30s
    
    if [ "${QUIET:-false}" != "true" ] && [ $total_jobs -gt 0 ]; then
        echo ""
        echo "${bold}⏳ Waiting for $total_jobs parallel job(s) to complete...${normal}"
    fi
    
    if [ $total_jobs -eq 0 ]; then
        return 0
    fi
    
    local start_time=$(date +%s)
    
    # Wait for all PIDs with proper timeout and cleanup
    for i in "${!JOB_PIDS[@]}"; do
        local pid="${JOB_PIDS[$i]}"
        local name="${JOB_NAMES[$i]}"
        
        if [ -z "$pid" ] || [ "$pid" = "0" ]; then
            continue
        fi
        
        # Check if process is still running
        if kill -0 "$pid" 2>/dev/null; then
            local pid_start=$(date +%s)
            local pid_waited=0
            
            # Wait with timeout (check every 1 second, show progress every 10 seconds)
            local last_progress=0
            while kill -0 "$pid" 2>/dev/null && [ $pid_waited -lt $max_wait ]; do
                sleep 1
                pid_waited=$((pid_waited + 1))
                
                # Show progress every 10 seconds, with more detail every 60 seconds
                if [ $((pid_waited % 10)) -eq 0 ] && [ "${QUIET:-false}" != true ]; then
                    local minutes=$((pid_waited / 60))
                    local seconds=$((pid_waited % 60))
                    local max_minutes=$((max_wait / 60))
                    if [ $minutes -gt 0 ]; then
                        echo "  ⏳ $name still running... (${minutes}m ${seconds}s / ${max_minutes}m)"
                    else
                        echo "  ⏳ $name still running... (${pid_waited}s / ${max_wait}s)"
                    fi
                fi
                
                # Check total elapsed time
                local current_time=$(date +%s)
                local elapsed=$((current_time - start_time))
                if [ $elapsed -ge $force_kill_after ]; then
                    if [ "${QUIET:-false}" != true ]; then
                        warning "Force killing stuck job: $name (PID: $pid) after ${elapsed}s"
                    fi
                    kill -9 "$pid" 2>/dev/null || true
                    break
                fi
            done
            
            # Final check and kill if still running
            if kill -0 "$pid" 2>/dev/null; then
                if [ "${QUIET:-false}" != true ]; then
                    warning "Job $name (PID: $pid) exceeded ${max_wait}s timeout, force killing..."
                fi
                kill -9 "$pid" 2>/dev/null || true
                # Wait a moment for kill to take effect
                sleep 0.5
            fi
            
            # Wait to collect exit status (non-blocking)
            wait "$pid" 2>/dev/null || true
        else
            # PID already finished, just wait to collect status (non-blocking)
            wait "$pid" 2>/dev/null || true
        fi
        
        completed=$((completed + 1))
    done
    
    # Clear job arrays to prevent zombie processes
    JOB_PIDS=()
    JOB_NAMES=()
    ACTIVE_JOBS=0
    
    if [ "${QUIET:-false}" != true ] && [ $total_jobs -gt 0 ]; then
        echo ""
        success "All $total_jobs parallel job(s) completed"
    fi
}

# Run multiple commands in parallel with results
run_parallel_batch() {
    local jobs_file="$1"
    local results_file="$2"
    
    > "$results_file"
    
    while IFS= read -r line; do
        if [ -z "$line" ]; then continue; fi
        
        local job_name=$(echo "$line" | cut -d'|' -f1)
        local job_cmd=$(echo "$line" | cut -d'|' -f2-)
        
        run_parallel "$job_name" "$job_cmd" >> "$results_file" 2>&1 &
    done < "$jobs_file"
    
    wait_all_jobs
}

# Parallel file processing
process_files_parallel() {
    local target_dir="$1"
    local process_func="$2"
    local output_file="${3:-/dev/null}"
    local max_jobs="${4:-$MAX_PARALLEL_JOBS}"
    
    local temp_dir=$(mktemp -d)
    local file_list="$temp_dir/files.txt"
    local job_count=0
    
    # Collect files
    find "$target_dir" -type f 2>/dev/null > "$file_list" || return 1
    
    local total_files=$(wc -l < "$file_list" | tr -d ' ')
    local processed=0
    
    if [ "${QUIET:-false}" != true ]; then
        echo "Processing $total_files files with $max_jobs parallel jobs..."
    fi
    
    # Process files in parallel
    while IFS= read -r file; do
        if [ -z "$file" ]; then continue; fi
        
        wait_for_job_slot
        
        (
            eval "$process_func \"$file\""
        ) >> "$output_file" 2>&1 &
        
        local pid=$!
        JOB_PIDS+=("$pid")
        JOB_NAMES+=("file:$(basename "$file")")
        ACTIVE_JOBS=$((ACTIVE_JOBS + 1))
        job_count=$((job_count + 1))
        
        # Update progress periodically
        if [ $((job_count % 10)) -eq 0 ] && [ "${QUIET:-false}" != true ]; then
            printf "\r${cyan}Queued: $job_count/$total_files files${normal}"
        fi
    done < "$file_list"
    
    # Wait for all to complete
    wait_all_jobs
    
    # Cleanup
    rm -rf "$temp_dir"
    
    if [ "${QUIET:-false}" != true ]; then
        echo ""
        success "Processed $total_files files in parallel"
    fi
}

# Initialize parallel processing
init_parallel() {
    MAX_PARALLEL_JOBS=$(get_parallel_jobs)
    ACTIVE_JOBS=0
    JOB_PIDS=()
    JOB_NAMES=()
    
    if [ "${VERBOSE:-false}" = "true" ]; then
        info "Parallel processing enabled: $MAX_PARALLEL_JOBS concurrent jobs"
    fi
}

