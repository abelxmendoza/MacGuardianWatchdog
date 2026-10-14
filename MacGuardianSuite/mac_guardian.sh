#!/bin/bash

# -----------------------------
# Mac Guardian Script 🧹🔒
# Cleans, updates, and secures your Mac
# Built for both beginners and pros
# Optimized for macOS
# -----------------------------

set -euo pipefail

# GUI apps and launchd jobs do not inherit an interactive shell's Homebrew
# path, so make both Apple Silicon and Intel installations discoverable.
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

# Global error handler
trap 'error_handler $? $LINENO' ERR

error_handler() {
    local exit_code=$1
    local line_no=$2
    # Only log if it's a real error (not from a function that returns non-zero intentionally)
    if [ $exit_code -ne 0 ] && [ "${CONTINUE_ON_ERROR:-false}" != "true" ]; then
        local error_msg="Script error at line $line_no (exit code: $exit_code)"
        log_message "ERROR" "$error_msg"
        # Track error in database
        if type track_error &> /dev/null; then
            track_error "$error_msg" "mac_guardian.sh" "$line_no" "script_error" "high" "false" ""
        fi
    fi
}

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source utilities and config
source "$SCRIPT_DIR/utils.sh"
source "$SCRIPT_DIR/config.sh"

# Parse command line arguments
parse_args "$@"

# Checkpoint system for resume functionality
CHECKPOINT_DIR="${CONFIG_DIR}/checkpoints"
CHECKPOINT_FILE="${CHECKPOINT_DIR}/mac_guardian_checkpoint.txt"
mkdir -p "$CHECKPOINT_DIR"

# Define steps in order
STEPS=(
    "homebrew_update"
    "security_checks"
    "clamav_scan"
    "rkhunter_scan"
    "firewall_check"
    "filevault_check"
    "sip_check"
    "gatekeeper_check"
    "time_machine_check"
)

# Check if resuming from checkpoint
RESUME_FROM=""
if [ -f "$CHECKPOINT_FILE" ]; then
    # Auto-resume if --resume flag is set OR if running non-interactively (UI mode)
    if [ "${RESUME:-false}" = "true" ] || [ "$INTERACTIVE" != "true" ]; then
        RESUME_FROM=$(cat "$CHECKPOINT_FILE" 2>/dev/null || echo "")
        if [ -n "$RESUME_FROM" ]; then
            if [ "$QUIET" != true ]; then
                echo "${bold}🔄 Resuming from checkpoint: $RESUME_FROM${normal}"
                echo ""
            fi
        fi
    fi
fi

# Save checkpoint
save_checkpoint() {
    local step="$1"
    echo "$step" > "$CHECKPOINT_FILE"
    log_message "INFO" "Checkpoint saved: $step"
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

# Enhanced sudo check that skips gracefully in non-interactive mode
check_sudo_graceful() {
    # First try non-interactive sudo (works if passwordless sudo is configured)
    if sudo -n true 2>/dev/null; then
        return 0
    fi
    
    # If non-interactive sudo doesn't work, check if we're in interactive mode
    if [ "$INTERACTIVE" = true ]; then
        warning "This operation requires administrator privileges."
        sudo -v || error_exit "Sudo access required but not available"
        return 0
    else
        # In non-interactive mode, try one more time with a helpful message
        warning "This operation requires administrator privileges."
        info "Attempting with passwordless sudo (if configured)..."
        if sudo -n true 2>/dev/null; then
            return 0
        else
            warning "Skipping this step (sudo access required)."
            info "💡 To enable rootkit scan:"
            info "   1. Run from Terminal: sudo ./MacGuardianSuite/mac_guardian.sh"
            info "   2. Or configure passwordless sudo for rkhunter"
            return 1
        fi
    fi
}

# Enable continue on error for non-interactive mode
if [ "$INTERACTIVE" != true ]; then
    export CONTINUE_ON_ERROR=true
fi

# Enable fast scan by default (unless explicitly disabled)
if [ "${FAST_SCAN_DEFAULT:-true}" = true ] && [ "${FAST_SCAN:-}" != false ]; then
    FAST_SCAN=true
fi

# Initialize report if requested
REPORT_FILE=""
if [ "$GENERATE_REPORT" = true ]; then
    REPORT_FILE="${REPORT_DIR:-$CONFIG_DIR/reports}/guardian_report_$(date +%Y%m%d_%H%M%S).html"
    mkdir -p "$(dirname "$REPORT_FILE")"
    report_header "Mac Guardian Security Report" "$REPORT_FILE"
    REPORT_CONTENT=""
fi

# Track issues for summary
ISSUES_FOUND=0
WARNINGS_FOUND=0

# Friendly intro
if [ "$QUIET" != true ]; then
    echo "${bold}👋 Welcome to Mac Guardian — Your System's Cleanup & Security Assistant${normal}"
    echo "Let's get your Mac up to date, clean, and safe. This may take a few minutes."
    echo ""
fi

log_message "INFO" "Mac Guardian started"

# Homebrew check
if ! command -v brew &> /dev/null; then
    error_exit "Homebrew not found. Please install Homebrew first from https://brew.sh"
fi

# Homebrew updates
if [ "$SKIP_UPDATES" != true ] && ! should_skip_step "homebrew_update"; then
    if [ "$QUIET" != true ]; then
        show_step 1 9 "Updating Homebrew (Mac's app manager)"
    fi
    
    # Performance tracking
    if type perf_start &> /dev/null; then
        perf_start "homebrew_update"
    fi
    
    # Use error recovery for better reliability
    if type execute_with_retry &> /dev/null; then
        if execute_with_retry "Homebrew update" 3 "bash \"$SCRIPT_DIR/package_updates.sh\" update --yes 2>&1 | tee -a \"${LOG_DIR:-$CONFIG_DIR/logs}/brew_update.log\""; then
            success "Homebrew is up to date."
            log_message "SUCCESS" "Homebrew updated"
        else
            warning "Homebrew update encountered issues, continuing..."
            WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
            log_message "WARNING" "Homebrew update failed"
        fi
    else
        if bash "$SCRIPT_DIR/package_updates.sh" update --yes 2>&1 | tee -a "${LOG_DIR:-$CONFIG_DIR/logs}/brew_update.log"; then
            success "Homebrew is up to date."
            log_message "SUCCESS" "Homebrew updated"
        else
            warning "Homebrew update encountered issues, continuing..."
            WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
            log_message "WARNING" "Homebrew update failed"
        fi
    fi
    
    if type perf_end &> /dev/null; then
        duration=$(perf_end "homebrew_update")
        if [ -n "$duration" ] && [ "${duration%.*}" -gt 10000 ] 2>/dev/null; then
            info "Homebrew update took ${duration}ms"
        fi
    fi

    if [ "$QUIET" != true ]; then
echo ""
        echo "${bold}⬆️  Upgrading installed tools...${normal}"
    fi
    
    if type perf_start &> /dev/null; then
        perf_start "homebrew_upgrade"
    fi
    
    if type execute_with_retry &> /dev/null; then
        if execute_with_retry "Homebrew upgrade" 2 "bash \"$SCRIPT_DIR/package_updates.sh\" upgrade --yes 2>&1 | tee -a \"${LOG_DIR:-$CONFIG_DIR/logs}/brew_upgrade.log\""; then
            success "All Homebrew tools and apps upgraded."
            log_message "SUCCESS" "Homebrew formulae, casks and available App Store apps upgraded"
        else
            warning "Some packages may have failed to upgrade."
            WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
        fi
    else
        if bash "$SCRIPT_DIR/package_updates.sh" upgrade --yes 2>&1 | tee -a "${LOG_DIR:-$CONFIG_DIR/logs}/brew_upgrade.log"; then
            success "All Homebrew tools and apps upgraded."
            log_message "SUCCESS" "Homebrew formulae, casks and available App Store apps upgraded"
        else
            warning "Some packages may have failed to upgrade."
            WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
        fi
    fi
    
    if type perf_end &> /dev/null; then
        duration=$(perf_end "homebrew_upgrade")
        if [ -n "$duration" ] && [ "${duration%.*}" -gt 30000 ] 2>/dev/null; then
            info "Homebrew upgrade took ${duration}ms"
        fi
    fi

    save_checkpoint "homebrew_update"
else
    if [ "$QUIET" != true ]; then
        if should_skip_step "homebrew_update"; then
            info "Skipping Homebrew updates (already completed in previous run)"
        else
            info "Skipping Homebrew updates (--skip-updates flag)"
        fi
    fi
fi

# macOS system update (interactive unless --yes flag)
if [ "$SKIP_UPDATES" != true ]; then
    if [ "$QUIET" != true ]; then
echo ""
    fi
    
    if [ "$INTERACTIVE" = true ]; then
        read -p "${bold}📦 Do you want to check for macOS system updates? (y/n): ${normal}" systemUpdate
    else
        systemUpdate="n"  # Default to no in non-interactive mode
    fi
    
    if [[ "$systemUpdate" =~ ^[Yy]$ ]]; then
        if [ "$QUIET" != true ]; then
            echo "${bold}🔍 Looking for system updates...${normal}"
        fi

        if softwareupdate -l 2>&1; then
            if [ "$INTERACTIVE" = true ]; then
                read -p "${bold}⚙️  Install all available updates now? (this might restart your Mac) (y/n): ${normal}" installNow
            else
                installNow="n"  # Default to no in non-interactive mode
            fi
            
            if [[ "$installNow" =~ ^[Yy]$ ]]; then
                check_sudo
                if sudo softwareupdate -i -a 2>&1; then
                    success "System updates installed successfully."
                    send_notification "Mac Guardian" "System updates installed successfully" "${NOTIFICATION_SOUND:-true}"
                    log_message "SUCCESS" "System updates installed"
                else
                    warning "Some updates may have failed or require a restart."
                    WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
                fi
            else
                if [ "$QUIET" != true ]; then
                    echo "⏩ Skipped installing updates."
                fi
            fi
        else
            warning "Could not check for updates. You may need to check System Settings manually."
            WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
        fi
    else
        if [ "$QUIET" != true ]; then
            echo "⏩ Skipped checking for macOS updates."
        fi
    fi
fi

# Additional Security Checks (Run in Parallel)
if ! should_skip_step "security_checks"; then
    if [ "$QUIET" != true ]; then
        echo ""
        show_step 2 9 "Running Security Checks (Parallel Mode)"
        if [ "${ENABLE_PARALLEL:-true}" = true ]; then
            info "Running security checks in parallel for faster execution"
        fi
    fi

# Performance tracking for parallel checks
if type perf_start &> /dev/null; then
    perf_start "security_checks_parallel"
fi

# Initialize parallel processing if enabled
if [ "${ENABLE_PARALLEL:-true}" = true ]; then
    init_parallel
fi

# Run security checks in parallel
SECURITY_RESULTS="$CONFIG_DIR/security_check_results_$$.txt"
> "$SECURITY_RESULTS"

# Source utils to ensure functions are available
if [ -f "$SCRIPT_DIR/utils.sh" ]; then
    source "$SCRIPT_DIR/utils.sh"
fi

# Run checks in parallel with proper function sourcing
(
    source "$SCRIPT_DIR/utils.sh" 2>/dev/null || true
    check_disk_space 85
) >> "$SECURITY_RESULTS" 2>&1 &
JOB_PIDS+=($!)
JOB_NAMES+=("disk_space_check")
ACTIVE_JOBS=$((ACTIVE_JOBS + 1))

(
    source "$SCRIPT_DIR/utils.sh" 2>/dev/null || true
    check_suspicious_processes
) >> "$SECURITY_RESULTS" 2>&1 &
JOB_PIDS+=($!)
JOB_NAMES+=("process_check")
ACTIVE_JOBS=$((ACTIVE_JOBS + 1))

(
    source "$SCRIPT_DIR/utils.sh" 2>/dev/null || true
    check_network_connections
) >> "$SECURITY_RESULTS" 2>&1 &
JOB_PIDS+=($!)
JOB_NAMES+=("network_check")
ACTIVE_JOBS=$((ACTIVE_JOBS + 1))

(
    source "$SCRIPT_DIR/utils.sh" 2>/dev/null || true
    check_file_permissions "$HOME/Documents"
) >> "$SECURITY_RESULTS" 2>&1 &
JOB_PIDS+=($!)
JOB_NAMES+=("permissions_check")
ACTIVE_JOBS=$((ACTIVE_JOBS + 1))

# Wait for all security checks to complete
wait_all_jobs

# End performance tracking for parallel checks
if type perf_end &> /dev/null; then
    duration=$(perf_end "security_checks_parallel")
    if [ -n "$duration" ] && [ "${duration%.*}" -gt 5000 ] 2>/dev/null; then
        info "Security checks completed in ${duration}ms"
    fi
fi

# Process results
if [ -f "$SECURITY_RESULTS" ]; then
    check_issues=$( (grep -c "⚠️\|❌" "$SECURITY_RESULTS" 2>/dev/null | tr -d ' ' || echo "0") | head -1)
    check_issues=${check_issues:-0}
    if [ "$check_issues" -gt 0 ] 2>/dev/null; then
        ISSUES_FOUND=$((ISSUES_FOUND + check_issues))
        if [ "$VERBOSE" = true ]; then
            cat "$SECURITY_RESULTS"
        fi
    fi
    # Show results even if no issues (for success messages)
    if [ "$VERBOSE" = true ] && [ "$QUIET" != true ]; then
        cat "$SECURITY_RESULTS" | grep -E "✅|⚠️|❌" || true
    fi
    rm -f "$SECURITY_RESULTS"
    
    save_checkpoint "security_checks"
fi
fi

# ClamAV antivirus
if [ "$SKIP_SCAN" != true ] && [ "${ENABLE_CLAMAV:-true}" = true ] && ! should_skip_step "clamav_scan"; then
    if [ "$QUIET" != true ]; then
echo ""
        show_step 3 9 "Running Antivirus Scan (ClamAV)"
    fi
    
    # Performance tracking
    if type perf_start &> /dev/null; then
        perf_start "clamav_scan"
    fi

# Ensure ClamAV is installed
if ! command -v clamscan &> /dev/null; then
        if [ "$QUIET" != true ]; then
            echo "📦 ClamAV not found. Installing it now..."
        fi
        # Error handling for ClamAV installation
        set +e  # Temporarily disable exit on error
        if brew install clamav 2>&1; then
            success "ClamAV installed successfully."
            log_message "SUCCESS" "ClamAV installed"
        else
            warning "ClamAV installation failed. Skipping antivirus scan."
            log_message "WARNING" "ClamAV installation failed, skipping scan"
            SKIP_CLAMAV=true
            WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
        fi
        set -e  # Re-enable exit on error
    fi

    if [ "${SKIP_CLAMAV:-false}" != "true" ]; then
        if [ "$QUIET" != true ]; then
echo "📥 Updating virus definitions..."
        fi
        # Error handling for freshclam
        set +e  # Temporarily disable exit on error
        if freshclam 2>&1; then
            success "Virus definitions updated."
            log_message "SUCCESS" "ClamAV definitions updated"
        else
            warning "Could not update virus definitions. Continuing with existing database..."
            log_message "WARNING" "ClamAV definition update failed, using existing database"
            WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
        fi
        set -e  # Re-enable exit on error

        # Use configured scan directory
        SCAN_TARGET="${SCAN_DIR:-$HOME/Documents}"
        if [ -d "$SCAN_TARGET" ]; then
            # Use fast scanner if available, otherwise use optimized clamscan
            if [ -f "$SCRIPT_DIR/clamav_fast.sh" ] && [ "${FAST_SCAN:-true}" != false ]; then
                if [ "$QUIET" != true ]; then
                    echo "🔍 Fast scanning $SCAN_TARGET for viruses..."
                    echo "   • Skipping large files and media"
                    echo "   • Optimized for speed"
                fi
                # Error handling for ClamAV scan
                set +e  # Temporarily disable exit on error
                SCAN_OUTPUT=$(bash "$SCRIPT_DIR/clamav_fast.sh" "$SCAN_TARGET" 100M 50000 2>&1)
                SCAN_EXIT=$?
                set -e  # Re-enable exit on error
                
                # Log scan result
                if [ $SCAN_EXIT -ne 0 ] && [ $SCAN_EXIT -ne 1 ]; then
                    # Exit code 1 is normal for ClamAV (means threats found), other codes are errors
                    log_message "WARNING" "ClamAV scan encountered an error (exit code: $SCAN_EXIT)"
                fi
            else
                # Optimized clamscan with exclusions
                if [ "$QUIET" != true ]; then
                    echo "🔍 Scanning $SCAN_TARGET for viruses (optimized for speed)..."
                    echo "   • Skipping files larger than 100MB"
                    echo "   • Excluding media and cache files"
                fi
                
                # Create exclude pattern file
                EXCLUDE_PATTERNS="$CONFIG_DIR/clamav_excludes.txt"
                cat > "$EXCLUDE_PATTERNS" <<'EXCLUDEEOF'
*.log
*.tmp
*.cache
*.swp
*.bak
*.old
*.DS_Store
*/.git/*
*/.Trash/*
*/Library/Caches/*
*/node_modules/*
*.mp4
*.mov
*.avi
*.mkv
*.mp3
*.wav
*.flac
*.jpg
*.jpeg
*.png
*.gif
*.pdf
*.zip
*.tar
*.gz
*.dmg
*.iso
EXCLUDEEOF
                
                # Fast scan with limits (with error handling)
                set +e  # Temporarily disable exit on error
                SCAN_OUTPUT=$(clamscan -r \
                    --bell \
                    -i \
                    --max-filesize=100M \
                    --max-scansize=200M \
                    --max-files=50000 \
                    --exclude-from="$EXCLUDE_PATTERNS" \
                    --no-summary \
                    "$SCAN_TARGET" 2>&1)
                SCAN_EXIT=$?
                set -e  # Re-enable exit on error
                rm -f "$EXCLUDE_PATTERNS"
                
                # Log scan result
                if [ $SCAN_EXIT -ne 0 ] && [ $SCAN_EXIT -ne 1 ]; then
                    log_message "WARNING" "ClamAV scan encountered an error (exit code: $SCAN_EXIT)"
                fi
            fi
            
            # Error handling for scan results
            set +e  # Temporarily disable exit on error
            if [ $SCAN_EXIT -eq 0 ]; then
                success "Antivirus scan finished - no threats found."
                log_message "SUCCESS" "Antivirus scan completed - no threats"
            elif [ $SCAN_EXIT -eq 1 ]; then
                # Exit code 1 means threats were found (this is expected behavior from ClamAV)
                warning "Antivirus scan found potential threats! Check the output above."
                ISSUES_FOUND=$((ISSUES_FOUND + 1))
                send_notification "Mac Guardian Alert" "Potential threats detected!" "${NOTIFICATION_SOUND:-true}" "critical"
                log_message "ALERT" "Antivirus found threats"
            else
                # Other exit codes indicate errors
                warning "Antivirus scan encountered an error (exit code: $SCAN_EXIT)."
                log_message "WARNING" "ClamAV scan error (exit code: $SCAN_EXIT)"
                WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
            fi
            set -e  # Re-enable exit on error
            
            # End performance tracking
            if type perf_end &> /dev/null; then
                duration=$(perf_end "clamav_scan")
                if [ -n "$duration" ] && [ "${duration%.*}" -gt 30000 ] 2>/dev/null; then
                    info "Antivirus scan took ${duration}ms"
                fi
            fi
            
            save_checkpoint "clamav_scan"
        else
            warning "Scan directory not found at $SCAN_TARGET. Skipping scan."
            WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
        fi
    fi
else
    if [ "$QUIET" != true ]; then
        if should_skip_step "clamav_scan"; then
            info "Skipping antivirus scan (already completed in previous run)"
        else
            info "Skipping antivirus scan (--skip-scan flag or disabled in config)"
        fi
    fi
fi

# Rootkit check
if [ "$SKIP_SCAN" != true ] && [ "${ENABLE_RKHUNTER:-true}" = true ] && ! should_skip_step "rkhunter_scan"; then
    if [ "$QUIET" != true ]; then
echo ""
        echo "${bold}💀 Step 4: Checking for hidden rootkits (rkhunter)...${normal}"
    fi
    
if ! command -v rkhunter &> /dev/null; then
        if [ "$QUIET" != true ]; then
            echo "📦 Rootkit Hunter not found. Installing it now..."
        fi
        if brew install rkhunter 2>&1; then
            success "Rootkit Hunter installed successfully."
            log_message "SUCCESS" "rkhunter installed"
        else
            warning "Rootkit Hunter installation failed. Skipping rootkit check."
            SKIP_RKHUNTER=true
            WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
        fi
    fi

    if [ "${SKIP_RKHUNTER:-false}" != "true" ]; then
        # Try to get sudo access - attempt non-interactive first
        has_sudo=false
        if sudo -n true 2>/dev/null; then
            has_sudo=true
            if [ "$QUIET" != true ]; then
                info "Using passwordless sudo for rootkit scan"
            fi
        elif [ "$INTERACTIVE" = true ]; then
            if check_sudo_graceful; then
                has_sudo=true
            fi
        else
            # In non-interactive mode, try one more time
            if sudo -n true 2>/dev/null; then
                has_sudo=true
            else
                warning "Skipping rootkit scan (sudo access required)"
                info "💡 To run rootkit scan:"
                info "   Option 1: Run from Terminal (safest - recommended):"
                info "     cd '$SCRIPT_DIR' && sudo ./mac_guardian.sh --resume"
                info "   Option 2: Use sudo cache (password lasts 15 min):"
                info "     Run: sudo -v"
                info "     Then: cd '$SCRIPT_DIR' && ./mac_guardian.sh --resume"
                info "   Option 3: Command-specific passwordless sudo (advanced):"
                info "     Run: sudo visudo"
                info "     Add: $(whoami) ALL=(ALL) NOPASSWD: /usr/local/bin/rkhunter, /opt/homebrew/bin/rkhunter"
                info "     ⚠️  Note: This reduces security. See SUDO_SECURITY.md for details."
                SKIP_RKHUNTER=true
                WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
            fi
        fi
        
        if [ "$has_sudo" = true ] && [ "${SKIP_RKHUNTER:-false}" != "true" ]; then
            if [ "$QUIET" != true ]; then
                echo "📥 Updating rootkit database..."
            fi
            
            # Fix rkhunter BINDIR configuration issue if ~/.dotnet/tools exists
            if [ -d "$HOME/.dotnet/tools" ] && [ -f /etc/rkhunter.conf ]; then
                # Temporarily fix BINDIR to exclude problematic directory
                sudo -n sed -i.bak 's|^BINDIR=.*|BINDIR=/usr/bin:/bin:/usr/local/bin:/usr/local/sbin|' /etc/rkhunter.conf 2>/dev/null || true
            fi
            
            if sudo -n rkhunter --update > /dev/null 2>&1; then
                success "Rootkit database updated."
            else
                warning "Could not update rootkit database (this is often normal)."
                WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
            fi
            
            if [ "$QUIET" != true ]; then
                echo "🔍 Running rootkit scan..."
            fi
            # Run scan and filter out BINDIR configuration warnings (these are harmless)
            rkhunter_output=$(sudo -n rkhunter --check --sk 2>&1 || true)
            
            # Check if scan actually completed (look for summary)
            if echo "$rkhunter_output" | grep -q "System checks summary\|Rootkit scan results"; then
                # Filter out BINDIR warnings from output
                echo "$rkhunter_output" | grep -v "Invalid BINDIR\|Invalid directory found" || true
                success "Rootkit scan completed (configuration warnings are normal)."
                log_message "SUCCESS" "Rootkit scan completed"
            else
                # Show output but note that BINDIR warnings are normal
                echo "$rkhunter_output" | grep -v "Invalid BINDIR\|Invalid directory found" || echo "$rkhunter_output"
                warning "Rootkit scan completed with warnings. BINDIR configuration warnings are normal and can be ignored."
                WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
            fi
            
            save_checkpoint "rkhunter_scan"
        fi
    fi
else
    if [ "$QUIET" != true ]; then
        if should_skip_step "rkhunter_scan"; then
            info "Skipping rootkit scan (already completed in previous run)"
        else
            info "Skipping rootkit scan (--skip-scan flag or disabled in config)"
        fi
    fi
fi

# Firewall check
if [ "$QUIET" != true ]; then
echo ""
    echo "${bold}🧱 Step 5: Checking Firewall status...${normal}"
fi
# Try multiple methods to check firewall
FIREWALL_STATUS=""
if [ -f /Library/Preferences/com.apple.alf.plist ]; then
    FIREWALL_STATUS=$(defaults read /Library/Preferences/com.apple.alf globalstate 2>/dev/null || echo "")
fi
if [ -z "$FIREWALL_STATUS" ]; then
    # Try using socketfilterfw command
    FIREWALL_STATUS=$(/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null | grep -o "enabled\|disabled" || echo "")
fi
if [ -n "$FIREWALL_STATUS" ]; then
    # Handle numeric status (0, 1, 2) or text status (enabled/disabled)
    if echo "$FIREWALL_STATUS" | grep -qi "enabled"; then
        success "Firewall is ON and protecting your Mac."
    elif echo "$FIREWALL_STATUS" | grep -qi "disabled"; then
        warning "Firewall is OFF. You should enable it (System Settings > Network > Firewall)."
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    else
case $FIREWALL_STATUS in
            0) warning "Firewall is OFF. You should enable it (System Settings > Network > Firewall)."; ISSUES_FOUND=$((ISSUES_FOUND + 1));;
            1) warning "Firewall is partially on. Turn it fully ON for better security."; WARNINGS_FOUND=$((WARNINGS_FOUND + 1));;
            2) success "Firewall is ON and protecting your Mac.";;
            *) warning "Unknown firewall status: $FIREWALL_STATUS"; WARNINGS_FOUND=$((WARNINGS_FOUND + 1));;
esac
    fi
else
    # Last resort: try system_profiler
    local firewall_info=$(system_profiler SPFirewallDataType 2>/dev/null | grep -i "firewall" | head -1 || echo "")
    if echo "$firewall_info" | grep -qi "enabled\|on"; then
        success "Firewall is enabled."
    else
        warning "Could not determine firewall status. Check System Settings > Network > Firewall manually."
        WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
    fi
fi

# LuLu check (optional outbound firewall)
if [ "$QUIET" != true ]; then
    echo ""
    echo "${bold}🔎 Step 6: Checking for LuLu (outbound firewall tool)...${normal}"
fi
if pgrep -x LuLu &> /dev/null || pgrep -f "LuLu" &> /dev/null; then
    success "LuLu is running and monitoring outbound connections."
else
    info "LuLu is not active. Download it here: https://objective-see.org/products/lulu.html"
fi

# Gatekeeper status check
if [ "$QUIET" != true ]; then
    echo ""
    echo "${bold}🔐 Step 7: Checking Gatekeeper status...${normal}"
fi
if spctl --status 2>/dev/null | grep -q "enabled"; then
    success "Gatekeeper is enabled and protecting your Mac."
else
    warning "Gatekeeper appears to be disabled."
    WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
fi

# System Integrity Protection (SIP) check
if [ "$QUIET" != true ]; then
echo ""
    echo "${bold}🛡️  Step 8: Checking System Integrity Protection (SIP)...${normal}"
fi
if csrutil status 2>/dev/null | grep -q "enabled"; then
    success "SIP is enabled and protecting system files."
elif csrutil status 2>/dev/null | grep -q "disabled"; then
    warning "SIP is disabled. This reduces system security."
    WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
else
    info "Could not determine SIP status (may require Recovery Mode to check)."
fi

# Backup reminder
if [ "$QUIET" != true ]; then
echo ""
    echo "${bold}💾 Step 9: Backup Status${normal}"
fi
if tmutil status 2>/dev/null | grep -q "Running = 1"; then
    success "Time Machine appears to be running."
else
    warning "Time Machine may not be active. Make sure to back up your important files."
    WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
fi

# Final message
if [ "$QUIET" != true ]; then
echo ""
    if [ $ISSUES_FOUND -eq 0 ] && [ $WARNINGS_FOUND -eq 0 ]; then
        echo "${bold}${green}🎉 All done! Your Mac is now cleaner, safer, and more up to date.${normal}"
        # Don't send notification when everything is clear (reduces spam)
        # Only notify on actual threats
    elif [ $ISSUES_FOUND -gt 0 ]; then
        echo "${bold}${red}⚠️  Completed with $ISSUES_FOUND issue(s) and $WARNINGS_FOUND warning(s) found.${normal}"
        send_notification "Mac Guardian Alert" "Security issues detected!" "${NOTIFICATION_SOUND:-true}" "critical"
    else
        echo "${bold}${yellow}✅ Completed with $WARNINGS_FOUND warning(s). Review the output above.${normal}"
    fi
echo "Run this script once a week or so to keep your system fresh. Stay secure out there, warrior. 🔐🧠💻"
fi

# Generate report if requested
if [ "$GENERATE_REPORT" = true ] && [ -n "$REPORT_FILE" ]; then
    report_footer "$REPORT_FILE"
    if [ "$QUIET" != true ]; then
        success "Report generated: $REPORT_FILE"
    fi
    log_message "INFO" "Report generated: $REPORT_FILE"
fi

log_message "INFO" "Mac Guardian completed - Issues: $ISSUES_FOUND, Warnings: $WARNINGS_FOUND"

# Process alert rules if advanced alerting is available
if [ -f "$SCRIPT_DIR/advanced_alerting.sh" ]; then
    source "$SCRIPT_DIR/advanced_alerting.sh" 2>/dev/null || true
    if type process_alert_rules &> /dev/null; then
        process_alert_rules 2>/dev/null || true
    fi
fi

# Send action-based email with AI summary
if [ -f "$SCRIPT_DIR/action_email_notifier.sh" ] && [ -n "${REPORT_EMAIL:-${ALERT_EMAIL:-}}" ]; then
    source "$SCRIPT_DIR/action_email_notifier.sh" 2>/dev/null || true
    
    # Create event data
    event_data=""
    if [ $ISSUES_FOUND -gt 0 ]; then
        event_data=$(cat <<EOF
[
  {
    "category": "security_scan",
    "severity": "$([ $ISSUES_FOUND -gt 5 ] && echo "critical" || echo "high")",
    "title": "Security scan completed with issues",
    "description": "Found $ISSUES_FOUND issue(s) and $WARNINGS_FOUND warning(s)",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "issues_count": $ISSUES_FOUND,
    "warnings_count": $WARNINGS_FOUND
  }
]
EOF
)
        send_action_email "$ACTION_ISSUES_FOUND" "$event_data" 2>/dev/null || true
    else
        event_data=$(cat <<EOF
[
  {
    "category": "security_scan",
    "severity": "info",
    "title": "Security scan completed successfully",
    "description": "No issues found. System is secure.",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "issues_count": 0,
    "warnings_count": $WARNINGS_FOUND
  }
]
EOF
)
        send_action_email "$ACTION_SCAN_COMPLETE" "$event_data" 2>/dev/null || true
    fi
fi

# Always exit with success (0) - issues are already logged and reported
# Exit code 0 means the script ran successfully, not that no issues were found
exit 0
