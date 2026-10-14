#!/bin/bash

# ===============================
# 🐺 Mac Watchdog v3.0
# BSD-safe, progress-friendly, stable hashing
# Optimized for macOS with better error handling
# ===============================

set -euo pipefail

# Default used by checksum progress reporting. This script sources utils.sh,
# but does not call its argument parser, so QUIET must be initialized here
# when nounset mode is enabled.
QUIET=false

# Global error handler with checkpoint support
trap 'error_handler $? $LINENO' ERR

error_handler() {
    local exit_code=$1
    local line_no=$2
    local error_msg="Watchdog error at line $line_no (exit code: $exit_code)"
    
    log_message "ERROR" "$error_msg"
    echo "${red}❌ Error: $error_msg${normal}" >&2
    
    # Save checkpoint on error so we can resume
    if [ -n "${CURRENT_STEP:-}" ]; then
        save_checkpoint "$CURRENT_STEP"
        echo "${yellow}💾 Checkpoint saved. Run with --resume to continue from here.${normal}" >&2
    fi
    
    # Don't exit if CONTINUE_ON_ERROR is set (for non-interactive mode)
    if [ "${CONTINUE_ON_ERROR:-false}" != "true" ]; then
        exit $exit_code
    fi
}

CONFIG_FILE="$HOME/.mac_watchdog_config"
BASELINE_FILE="$HOME/.mac_watchdog_baseline.txt"
CURRENT_CHECKSUMS="$HOME/.mac_watchdog_current.txt"
# Alerts go to the address the user set in ~/.macguardian/config.conf (if any).
ALERT_EMAIL="$(sed -n 's/^ALERT_EMAIL="\([^"]*\)".*/\1/p' "$HOME/.macguardian/config.conf" 2>/dev/null | tail -1)"
MONITOR_PATHS=("$HOME/Documents")
FULL_SCAN_PATH="/Applications"
HONEYPOT_DIR="$HOME/Documents/Passwords_DO_NOT_OPEN"
HONEYPOT_LOG="$HOME/.mac_watchdog_honeypot.log"
SYSLOG_COPY="$HOME/.mac_watchdog_syslog_last.txt"
SYSLOG_DIFF="$HOME/.mac_watchdog_syslog_diff.txt"
WATCHDOG_LOG="$HOME/.mac_watchdog_log.txt"

# Checkpoint system for resume functionality
CHECKPOINT_DIR="$HOME/.macguardian/checkpoints"
CHECKPOINT_FILE="${CHECKPOINT_DIR}/mac_watchdog_checkpoint.txt"
mkdir -p "$CHECKPOINT_DIR"

# Define steps in order (one per monitored path)
STEPS=()
for path in "${MONITOR_PATHS[@]}"; do
    STEPS+=("checksum_$(basename "$path")")
done
STEPS+=("compare_checksums" "check_honeypot" "check_syslog" "send_alerts")

# Parse arguments for --resume flag
RESUME=false
for arg in "$@"; do
    case "$arg" in
        --resume|-r)
            RESUME=true
            ;;
        --non-interactive|-y)
            export CONTINUE_ON_ERROR=true
            ;;
    esac
done

# Check if resuming from checkpoint
RESUME_FROM=""
if [ -f "$CHECKPOINT_FILE" ]; then
    # Auto-resume if --resume flag is set OR if running non-interactively (UI mode)
    if [ "$RESUME" = "true" ] || [ "${INTERACTIVE:-true}" != "true" ]; then
        RESUME_FROM=$(cat "$CHECKPOINT_FILE" 2>/dev/null || echo "")
        if [ -n "$RESUME_FROM" ]; then
            echo "${bold}🔄 Resuming from checkpoint: $RESUME_FROM${normal}"
            echo ""
            log_message "INFO" "Resuming from checkpoint: $RESUME_FROM"
        fi
    fi
fi

# Save checkpoint
save_checkpoint() {
    local step="$1"
    CURRENT_STEP="$step"
    echo "$step" > "$CHECKPOINT_FILE"
    log_message "INFO" "Checkpoint saved: $step"
}

# Clear checkpoint (when operation completes successfully)
clear_checkpoint() {
    if [ -f "$CHECKPOINT_FILE" ]; then
        rm -f "$CHECKPOINT_FILE"
        log_message "INFO" "Checkpoint cleared - operation completed successfully"
    fi
}

# Check if step should be skipped (already completed)
should_skip_step() {
    local step="$1"
    if [ -n "$RESUME_FROM" ]; then
        local found=false
        for s in "${STEPS[@]}"; do
            if [ "$s" = "$RESUME_FROM" ]; then
                found=true
            fi
            if [ "$found" = true ] && [ "$s" = "$step" ]; then
                return 1  # Don't skip - this is the step to resume from
            fi
        done
        # If we haven't reached resume point yet, skip
        for s in "${STEPS[@]}"; do
            if [ "$s" = "$RESUME_FROM" ]; then
                return 0  # Skip - already completed
            fi
            if [ "$s" = "$step" ]; then
                return 1  # Don't skip - this is before resume point
            fi
        done
    fi
    return 1  # Don't skip by default
}

# Color support with fallback
bold=$(tput bold 2>/dev/null || echo "")
normal=$(tput sgr0 2>/dev/null || echo "")
green=$(tput setaf 2 2>/dev/null || echo "")
red=$(tput setaf 1 2>/dev/null || echo "")
yellow=$(tput setaf 3 2>/dev/null || echo "")

# Logging function
log_message() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$WATCHDOG_LOG"
}

# Function to send alert (multiple methods)
send_alert() {
    local subject="$1"
    local body="$2"
    if [ -z "$ALERT_EMAIL" ]; then
        return 1  # no address configured; the alert is still logged
    fi
    local timestamp=$(date)
    
    # Try mail command first (macOS built-in)
    if command -v mail &> /dev/null; then
        echo "$body" | mail -s "$subject" "$ALERT_EMAIL" 2>/dev/null && return 0
    fi
    
    # Try sendmail as fallback
    if command -v sendmail &> /dev/null; then
        {
            echo "Subject: $subject"
            echo "To: $ALERT_EMAIL"
            echo ""
            echo "$body"
        } | sendmail "$ALERT_EMAIL" 2>/dev/null && return 0
    fi
    
    # Fallback: write to log file
    echo "ALERT: $subject" >> "$WATCHDOG_LOG"
    echo "$body" >> "$WATCHDOG_LOG"
    echo "${yellow}⚠️  Alert logged (email not configured). Check $WATCHDOG_LOG${normal}"
    return 1
}

# Source advanced algorithms
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/algorithms.sh" ]; then
    source "$SCRIPT_DIR/algorithms.sh"
    init_algorithms
fi

# Optimized checksum creation with incremental hashing
create_checksums() {
    local target_dir="$1"
    local output_file="$2"
    local use_incremental="${3:-false}"
    local baseline_file="${4:-}"
    
    if [ ! -d "$target_dir" ]; then
        echo "${yellow}⚠️  Directory not found: $target_dir${normal}"
        return 1
    fi
    
    echo "Indexing: $target_dir"
    
    # Count files first to give progress indication
    local file_count=$(find "$target_dir" -type f 2>/dev/null | wc -l | tr -d ' ')
    echo "  📊 Found $file_count files to process..."
    
    # Use incremental hashing if baseline exists
    if [ "$use_incremental" = "true" ] && [ -f "$baseline_file" ] && [ -f "$SCRIPT_DIR/algorithms.sh" ]; then
        # Show progress every 30 seconds if possible
        echo "  ⏳ Processing files (this may take several minutes for large directories)..."
        local stats=$(incremental_hash "$target_dir" "$baseline_file" "$output_file" "$HONEYPOT_DIR")
        local changed=$(echo "$stats" | cut -d'|' -f1)
        local new=$(echo "$stats" | cut -d'|' -f2)
        local unchanged=$(echo "$stats" | cut -d'|' -f3)
        local total=$((changed + new + unchanged))
        
        echo "  ✅ Indexed $total files (Changed: $changed, New: $new, Unchanged: $unchanged)"
        
        # Save cache
        if [ -f "$SCRIPT_DIR/algorithms.sh" ]; then
            cleanup_algorithms
        fi
        
        return 0
    fi
    
    # Standard hashing with optimizations
    local count=0
    local exclude_patterns=(
        "*/.*"           # Hidden files/dirs
        "*/node_modules/*"
        "*/Library/Caches/*"
        "*/tmp/*"
        "*/temp/*"
        "$HONEYPOT_DIR/*" # Checked separately via modification time below
    )
    
    # Use smart_find if available, with parallel processing and sorting
    if [ -f "$SCRIPT_DIR/algorithms.sh" ]; then
        source "$SCRIPT_DIR/algorithms.sh"
        
        # Process files in parallel batches and sort results
        local temp_unsorted="$output_file.unsorted"
        > "$temp_unsorted"
        
        # Process files in parallel
        local file_list=$(mktemp)
        smart_find "$target_dir" "${exclude_patterns[@]}" > "$file_list" 2>/dev/null || \
        find "$target_dir" -type f -print0 2>/dev/null > "$file_list"
        
        # Process in parallel batches
        local batch_size=100
        local processed=0
        
        while IFS= read -r -d '' file; do
            if [ -f "$file" ] && [ -r "$file" ]; then
                (
                    local cached_info=$(get_file_info "$file")
                    local hash=$(echo "$cached_info" | cut -d'|' -f3)
                    if [ -n "$hash" ]; then
                        echo "$hash|$file"
                    fi
                ) >> "$temp_unsorted" &
                
                processed=$((processed + 1))
                
                # Wait for batch to complete
                if [ $((processed % batch_size)) -eq 0 ]; then
                    wait
                    if [ "$QUIET" != true ]; then
                        echo "  • Processed $processed files..."
                    fi
                fi
            fi
        done < "$file_list"
        
        wait
        
        # Sort results by hash for efficient comparison
        if [ -f "$SCRIPT_DIR/sort_engine.sh" ]; then
            source "$SCRIPT_DIR/sort_engine.sh"
            parallel_sort_large "$temp_unsorted" "$output_file" 1
        else
            sort "$temp_unsorted" > "$output_file"
        fi
        
        # Convert to standard format (hash  filepath)
        sed 's/|/  /' "$output_file" > "${output_file}.tmp" && mv "${output_file}.tmp" "$output_file"
        
        count=$(wc -l < "$output_file" | tr -d ' ')
        rm -f "$temp_unsorted" "$file_list"
    else
        # Fallback to standard find
        while IFS= read -r -d '' file; do
            if [ -f "$file" ] && [ -r "$file" ]; then
                if shasum -a 256 "$file" >> "$output_file" 2>/dev/null; then
                    count=$((count + 1))
                    if [ $((count % 50)) -eq 0 ]; then
                        echo "  • Processed $count files..."
                    fi
                fi
            fi
        done < <(find "$target_dir" -type f -print0 2>/dev/null)
    fi
    
    echo "  ✅ Indexed $count files from $target_dir"
    
    # Save cache
    if [ -f "$SCRIPT_DIR/algorithms.sh" ]; then
        cleanup_algorithms
    fi
    
    return 0
}

# First-time setup
if [ ! -f "$CONFIG_FILE" ]; then
    echo "${bold}🔐 First-time setup for Mac Watchdog...${normal}"
    echo "Creating baseline checksums..."
    
    # Initialize baseline file
    > "$BASELINE_FILE"
    
    # Index monitored paths
    for path in "${MONITOR_PATHS[@]}"; do
        create_checksums "$path" "$BASELINE_FILE"
    done
    
    # Ask about /Applications scan
    read -p "${bold}❓ Scan /Applications too? (y/n): ${normal}" FULL_SCAN_REPLY
    if [[ "$FULL_SCAN_REPLY" =~ ^[Yy]$ ]]; then
        create_checksums "$FULL_SCAN_PATH" "$BASELINE_FILE"
    fi
    
    # Verify baseline was created
    if [ ! -s "$BASELINE_FILE" ]; then
        echo "${red}❌ No baseline created. Try again with accessible directories.${normal}"
        log_message "ERROR" "Baseline creation failed"
        exit 1
    fi
    
    # Create honeypot directory
    mkdir -p "$HONEYPOT_DIR"
    echo "# Fake credentials file - DO NOT OPEN" > "$HONEYPOT_DIR/credentials.txt"
    echo "# This is a honeypot file to detect unauthorized access" >> "$HONEYPOT_DIR/credentials.txt"
    echo "username: admin" >> "$HONEYPOT_DIR/credentials.txt"
    echo "password: changeme123" >> "$HONEYPOT_DIR/credentials.txt"
    chmod 600 "$HONEYPOT_DIR/credentials.txt" 2>/dev/null || true
    
    # Initialize honeypot log
    touch "$HONEYPOT_LOG"
    stat -f %m "$HONEYPOT_DIR/credentials.txt" > "$HONEYPOT_LOG" 2>/dev/null || echo "0" > "$HONEYPOT_LOG"
    
    # Create initial syslog snapshot
    if command -v log &> /dev/null; then
        log show --last 1d --predicate 'process == "kernel"' 2>/dev/null | head -1000 > "$SYSLOG_COPY" || true
    fi
    
    # Save configuration
    {
        echo "BASELINE_FILE=\"$BASELINE_FILE\""
        echo "ALERT_EMAIL=\"$ALERT_EMAIL\""
        echo "MONITOR_PATHS=(\"$HOME/Documents\")"
        echo "HONEYPOT_DIR=\"$HONEYPOT_DIR\""
        echo "SYSLOG_COPY=\"$SYSLOG_COPY\""
        if [[ "$FULL_SCAN_REPLY" =~ ^[Yy]$ ]]; then
            echo "FULL_SCAN_PATH=\"$FULL_SCAN_PATH\""
        fi
    } > "$CONFIG_FILE"
    
    echo "${bold}${green}✅ Baseline created with $(wc -l < "$BASELINE_FILE") files. Future runs will compare against this.${normal}"
    log_message "INFO" "Baseline created successfully"
    exit 0
fi

# Load configuration
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "${red}❌ Configuration file not found. Please run setup again.${normal}"
    exit 1
fi

# Verify baseline exists
if [ ! -f "$BASELINE_FILE" ] || [ ! -s "$BASELINE_FILE" ]; then
    echo "${red}❌ Baseline file missing or empty. Please run setup again.${normal}"
    log_message "ERROR" "Baseline file missing"
    exit 1
fi

# Run integrity check (with parallel processing)
echo "${bold}🔍 Mac Watchdog - Running integrity check...${normal}"
echo ""

# Source utils for parallel processing
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/utils.sh" ]; then
    source "$SCRIPT_DIR/utils.sh"
    if [ "${ENABLE_PARALLEL:-true}" = true ]; then
        init_parallel
        info "Processing ${#MONITOR_PATHS[@]} path(s) in parallel"
    fi
fi

> "$CURRENT_CHECKSUMS"

# Set longer timeout for checksum operations (they can take time on large directories)
# For very large directories (like Documents with many files), increase this
export PARALLEL_JOB_TIMEOUT=900  # 15 minutes for checksum operations

# Process paths in parallel if enabled (with incremental hashing)
if [ "${ENABLE_PARALLEL:-true}" = true ] && [ -f "$SCRIPT_DIR/utils.sh" ]; then
    echo "ℹ️  Processing ${#MONITOR_PATHS[@]} path(s) in parallel"
    echo "⏱️  Timeout set to 15 minutes (checksum operations can take time on large directories)"
    echo "💡 Tip: For very large directories, consider running during off-hours or excluding subdirectories"
    if [ -n "$RESUME_FROM" ]; then
        echo "🔄 Resuming from checkpoint - completed paths will be skipped"
    fi
    echo ""
    
    for path in "${MONITOR_PATHS[@]}"; do
        step_name="checksum_$(basename "$path")"
        
        # Skip if already completed (checkpoint system)
        if should_skip_step "$step_name"; then
            echo "⏩ Skipping $path (already completed in previous run)"
            log_message "INFO" "Skipping $step_name - already completed"
            continue
        fi
        
        if [ ! -d "$path" ]; then
            echo "${yellow}⚠️  Path not found: $path${normal}"
            log_message "WARN" "Path not found: $path"
            continue
        fi
        
        echo "📁 Starting checksum for: $path"
        log_message "INFO" "Starting checksum for: $path"
        
        # Save checkpoint before starting
        save_checkpoint "$step_name"
        
        # Use incremental hashing for efficiency
        if run_parallel "$step_name" "create_checksums \"$path\" \"$CURRENT_CHECKSUMS\" \"true\" \"$BASELINE_FILE\"" > /dev/null; then
            wait_all_jobs
            wait_status=$?
            if [ $wait_status -eq 0 ]; then
                echo "✅ Completed checksum for: $path"
                log_message "SUCCESS" "Completed checksum for: $path"
                save_checkpoint "$step_name"  # Update checkpoint
            else
                echo "${red}❌ Checksum failed for: $path (exit code: $wait_status)${normal}"
                log_message "ERROR" "Checksum failed for: $path (exit code: $wait_status)"
                echo "${yellow}💾 Checkpoint saved. Run with --resume to retry from here.${normal}"
                echo "${yellow}💡 Debug: Check $WATCHDOG_LOG for details${normal}"
                if [ "${CONTINUE_ON_ERROR:-false}" != "true" ]; then
                    exit 1
                fi
            fi
        else
            echo "${red}❌ Failed to start checksum for: $path${normal}"
            log_message "ERROR" "Failed to start checksum for: $path"
            echo "${yellow}💡 Debug: Check if directory is accessible and has files${normal}"
            if [ "${CONTINUE_ON_ERROR:-false}" != "true" ]; then
                exit 1
            fi
        fi
    done
else
    # Sequential fallback with incremental hashing
    for path in "${MONITOR_PATHS[@]}"; do
        step_name="checksum_$(basename "$path")"
        
        # Skip if already completed (checkpoint system)
        if should_skip_step "$step_name"; then
            echo "⏩ Skipping $path (already completed in previous run)"
            log_message "INFO" "Skipping $step_name - already completed"
            continue
        fi
        
        if [ ! -d "$path" ]; then
            echo "${yellow}⚠️  Path not found: $path${normal}"
            log_message "WARN" "Path not found: $path"
            continue
        fi
        
        echo "📁 Starting checksum for: $path"
        log_message "INFO" "Starting checksum for: $path"
        
        # Save checkpoint before starting
        save_checkpoint "$step_name"
        
        # Run checksum with error handling
        if create_checksums "$path" "$CURRENT_CHECKSUMS" "true" "$BASELINE_FILE"; then
            echo "✅ Completed checksum for: $path"
            log_message "SUCCESS" "Completed checksum for: $path"
            save_checkpoint "$step_name"  # Update checkpoint
        else
            checksum_status=$?
            echo "${red}❌ Checksum failed for: $path (exit code: $checksum_status)${normal}"
            log_message "ERROR" "Checksum failed for: $path (exit code: $checksum_status)"
            echo "${yellow}💾 Checkpoint saved. Run with --resume to retry from here.${normal}"
            echo "${yellow}💡 Debug: Check $WATCHDOG_LOG for details${normal}"
            if [ "${CONTINUE_ON_ERROR:-false}" != "true" ]; then
                exit 1
            fi
        fi
    done
fi

# Compare checksums using optimized diff algorithm
if ! should_skip_step "compare_checksums"; then
    save_checkpoint "compare_checksums"
    
    echo "🔍 Comparing checksums..."
    log_message "INFO" "Starting checksum comparison"
    
    DIFF_RESULT=""
    if [ ! -f "$CURRENT_CHECKSUMS" ] || [ ! -s "$CURRENT_CHECKSUMS" ]; then
        echo "${red}❌ Error: Current checksums file is missing or empty${normal}"
        log_message "ERROR" "Current checksums file missing or empty"
        echo "${yellow}💡 Debug: Checksum operations may have failed. Check $WATCHDOG_LOG${normal}"
        if [ "${CONTINUE_ON_ERROR:-false}" != "true" ]; then
            exit 1
        fi
    elif [ ! -f "$BASELINE_FILE" ] || [ ! -s "$BASELINE_FILE" ]; then
        echo "${red}❌ Error: Baseline file is missing or empty${normal}"
        log_message "ERROR" "Baseline file missing or empty"
        echo "${yellow}💡 Debug: Run setup first to create baseline${normal}"
        if [ "${CONTINUE_ON_ERROR:-false}" != "true" ]; then
            exit 1
        fi
    else
        if [ -f "$SCRIPT_DIR/algorithms.sh" ]; then
            # Use fast_diff for O(1) hash lookups
            DIFF_RESULT=$(fast_diff "$BASELINE_FILE" "$CURRENT_CHECKSUMS" 2>/dev/null || true)
        else
            # Fallback to standard diff
            DIFF_RESULT=$(diff -u "$BASELINE_FILE" "$CURRENT_CHECKSUMS" 2>/dev/null || true)
        fi
        
        if [ -z "$DIFF_RESULT" ]; then
            echo "✅ No changes detected - files match baseline"
            log_message "SUCCESS" "No integrity violations detected"
        else
            diff_lines=$(echo "$DIFF_RESULT" | wc -l | tr -d ' ')
            echo "${yellow}⚠️  Detected $diff_lines line(s) of differences${normal}"
            log_message "WARN" "Integrity violations detected: $diff_lines differences"
        fi
        
        save_checkpoint "compare_checksums"
    fi
fi

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
HONEYPOT_ACCESSED=false

# Check honeypot access
if ! should_skip_step "check_honeypot"; then
    save_checkpoint "check_honeypot"
    
    echo "🍯 Checking honeypot file..."
    log_message "INFO" "Checking honeypot file access"
    
    if [ -f "$HONEYPOT_DIR/credentials.txt" ]; then
        if [ -f "$HONEYPOT_LOG" ]; then
            LAST_RUN_TIME=$(cat "$HONEYPOT_LOG" 2>/dev/null || echo "0")
            CURRENT_ACCESS_TIME=$(stat -f %m "$HONEYPOT_DIR/credentials.txt" 2>/dev/null || echo "0")
            
            if [ "$CURRENT_ACCESS_TIME" -gt "$LAST_RUN_TIME" ] 2>/dev/null; then
                HONEYPOT_ACCESSED=true
                echo "$CURRENT_ACCESS_TIME" > "$HONEYPOT_LOG"
                echo "  ${red}🚨 HONEYPOT FILE ACCESSED!${normal}"
                log_message "CRITICAL" "Honeypot file accessed"
            else
                echo "  ✅ Honeypot file not accessed"
            fi
        else
            echo "$(stat -f %m "$HONEYPOT_DIR/credentials.txt" 2>/dev/null || echo "0")" > "$HONEYPOT_LOG"
            echo "  📝 Initialized honeypot log"
        fi
    else
        echo "  ⚠️  Honeypot file not found (may need setup)"
        log_message "WARN" "Honeypot file not found"
    fi
    
    save_checkpoint "check_honeypot"
fi

# Check system log changes (simplified)
if ! should_skip_step "check_syslog"; then
    save_checkpoint "check_syslog"
    
    echo "📋 Checking system logs..."
    log_message "INFO" "Checking system log changes"
    
    LOG_CHANGES=""
    
    if command -v log &> /dev/null; then
        if [ -f "$SYSLOG_COPY" ]; then
            new_syslog="$SYSLOG_COPY.new"
            log show --last 1d --predicate 'process == "kernel"' 2>/dev/null | head -1000 > "$new_syslog" || true
            
            if [ -s "$new_syslog" ]; then
                LOG_CHANGES=$(diff -u "$SYSLOG_COPY" "$new_syslog" 2>/dev/null | head -50 || echo "")
                mv "$new_syslog" "$SYSLOG_COPY" 2>/dev/null || true
                
                if [ -n "$LOG_CHANGES" ]; then
                    log_lines=$(echo "$LOG_CHANGES" | wc -l | tr -d ' ')
                    echo "  ⚠️  Detected $log_lines line(s) of log changes"
                    log_message "INFO" "System log changes detected: $log_lines lines"
                else
                    echo "  ✅ No significant log changes detected"
                fi
            fi
        else
            # Create initial snapshot
            echo "  📝 Creating initial syslog snapshot..."
            log show --last 1d --predicate 'process == "kernel"' 2>/dev/null | head -1000 > "$SYSLOG_COPY" || true
            log_message "INFO" "Created initial syslog snapshot"
        fi
    else
        echo "  ⚠️  'log' command not available - skipping syslog check"
        log_message "WARN" "log command not available"
    fi
    
    save_checkpoint "check_syslog"
fi

# Send alerts if needed
if ! should_skip_step "send_alerts"; then
    save_checkpoint "send_alerts"
    
    echo "📧 Preparing alerts..."
    log_message "INFO" "Preparing alert messages"
    
    # Build alert message
    ALERT_MSG="Mac Watchdog Integrity Check Report\n"
    ALERT_MSG+="Timestamp: $TIMESTAMP\n\n"
    ALERT_NEEDED=false
    
    if [ -n "$DIFF_RESULT" ]; then
        ALERT_MSG+="🚨 FILE INTEGRITY VIOLATIONS DETECTED 🚨\n\n"
        ALERT_MSG+="Files have been added, modified, or deleted:\n"
        ALERT_MSG+="$(echo "$DIFF_RESULT" | head -100)\n\n"
        if [ $(echo "$DIFF_RESULT" | wc -l) -gt 100 ]; then
            ALERT_MSG+="... (truncated, see full diff in log)\n\n"
        fi
        ALERT_NEEDED=true
        echo "${red}⚠️  File integrity violations detected!${normal}"
        log_message "ALERT" "File integrity violations detected"
    fi
    
    if [ "$HONEYPOT_ACCESSED" = true ]; then
        ALERT_MSG+="🚨🚨🚨 HONEYPOT FILE ACCESSED 🚨🚨🚨\n\n"
        ALERT_MSG+="The honeypot file was accessed at: $TIMESTAMP\n"
        ALERT_MSG+="Location: $HONEYPOT_DIR/credentials.txt\n"
        ALERT_MSG+="This may indicate unauthorized access!\n\n"
        ALERT_NEEDED=true
        echo "${red}🚨 HONEYPOT ACCESSED - Potential security breach!${normal}"
        log_message "CRITICAL" "Honeypot file accessed"
    fi
    
    if [ -n "$LOG_CHANGES" ]; then
        ALERT_MSG+="System log changes detected:\n"
        ALERT_MSG+="$(echo "$LOG_CHANGES" | head -30)\n\n"
        # Only alert on significant log changes (not every run)
        if echo "$LOG_CHANGES" | grep -qE "(error|warning|fail|denied|unauthorized)" 2>/dev/null; then
            ALERT_NEEDED=true
            log_message "WARNING" "Significant system log changes detected"
        fi
    fi
    
    # Send alert if needed
    if [ "$ALERT_NEEDED" = true ]; then
        ALERT_MSG+="\n---\nMac Watchdog Alert\nTimestamp: $TIMESTAMP\n"
        if send_alert "🚨 Mac Watchdog Alert - $TIMESTAMP" "$ALERT_MSG"; then
            echo "${green}✅ Alert sent to $ALERT_EMAIL${normal}"
            log_message "SUCCESS" "Alert sent successfully"
        else
            echo "${yellow}⚠️  Alert logged (email may not be configured)${normal}"
            log_message "WARN" "Alert logged but email not sent"
        fi
    else
        echo "${green}✅ No suspicious activity detected.${normal}"
        log_message "INFO" "Scan completed - no issues found"
    fi
    
    save_checkpoint "send_alerts"
fi

# Clear checkpoint on successful completion
clear_checkpoint
echo ""
echo "${bold}${green}✅ Mac Watchdog integrity check completed successfully${normal}"
log_message "SUCCESS" "Watchdog check completed successfully"
