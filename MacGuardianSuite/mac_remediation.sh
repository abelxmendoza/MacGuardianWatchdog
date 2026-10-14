#!/bin/bash

# ===============================
# 🔧 Mac Remediation v1.0
# Auto-Fix Security Issues
# Safe automated remediation with confirmations
# ===============================

set -euo pipefail

# Global error handler
trap 'error_handler $? $LINENO' ERR

error_handler() {
    local exit_code=$1
    local line_no=$2
    if [ $exit_code -ne 0 ] && [ "${CONTINUE_ON_ERROR:-false}" != "true" ]; then
        log_message "ERROR" "Script error at line $line_no (exit code: $exit_code)"
    fi
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"
source "$SCRIPT_DIR/config.sh"
source "$SCRIPT_DIR/quarantine_manager.sh" 2>/dev/null || true

# Remediation specific config
REMEDIATION_DIR="$CONFIG_DIR/remediation"
REMEDIATION_LOG="$REMEDIATION_DIR/remediation_$(date +%Y%m%d_%H%M%S).log"
REMEDIATION_BACKUP="$REMEDIATION_DIR/backups"
SESSION_ID=$(date +%Y%m%d_%H%M%S)
mkdir -p "$REMEDIATION_DIR" "$REMEDIATION_BACKUP"

# Parse arguments
QUIET=false
VERBOSE=false
DRY_RUN=true  # Default to dry-run for safety
AUTO_CONFIRM=false
FIX_PERMISSIONS=true
FIX_PROCESSES=false  # Dangerous, requires confirmation
FIX_NETWORK=false  # Dangerous, requires confirmation
FIX_FILES=false  # Dangerous, requires confirmation
FIX_LAUNCH_ITEMS=false  # Dangerous, requires confirmation
CLEANUP_DISK=true
FIX_ALL=false  # Fix all detected issues from Blue Team
BLUETEAM_RESULTS_FILE=""  # Path to Blue Team results file

while [[ $# -gt 0 ]]; do
    case $1 in
        -q|--quiet) QUIET=true; shift ;;
        -v|--verbose) VERBOSE=true; shift ;;
        --execute) DRY_RUN=false; shift ;;
        -y|--yes) AUTO_CONFIRM=true; DRY_RUN=false; shift ;;
        --fix-permissions) FIX_PERMISSIONS=true; shift ;;
        --fix-processes) FIX_PROCESSES=true; shift ;;
        --fix-network) FIX_NETWORK=true; shift ;;
        --fix-files) FIX_FILES=true; shift ;;
        --fix-launch) FIX_LAUNCH_ITEMS=true; shift ;;
        --cleanup-disk) CLEANUP_DISK=true; shift ;;
        --fix-all) FIX_ALL=true; FIX_PERMISSIONS=true; CLEANUP_DISK=true; shift ;;
        --from-blueteam) BLUETEAM_RESULTS_FILE="$2"; FIX_ALL=true; shift 2 ;;
        --preview-all) FIX_PROCESSES=true; FIX_LAUNCH_ITEMS=true; shift ;;
        --only)
            # Run exactly one kind of fix (used by the app's Apply button).
            FIX_PERMISSIONS=false; CLEANUP_DISK=false; FIX_PROCESSES=false; FIX_LAUNCH_ITEMS=false
            case "${2:-}" in
                permissions) FIX_PERMISSIONS=true ;;
                disk) CLEANUP_DISK=true ;;
                processes) FIX_PROCESSES=true ;;
                launch) FIX_LAUNCH_ITEMS=true ;;
                *) echo "Unknown --only category: ${2:-} (use permissions, disk, processes or launch)" >&2; exit 2 ;;
            esac
            shift 2 ;;
        -h|--help)
            cat <<EOF
Mac Remediation - Auto-Fix Security Issues

Usage: $0 [OPTIONS]

Options:
    -h, --help          Show this help
    -q, --quiet         Minimal output
    -v, --verbose       Detailed output
    --execute           Actually perform fixes (default is dry-run)
    -y, --yes           Auto-confirm all fixes (use with caution!)
    --fix-permissions   Fix file permission issues
    --fix-processes     Fix/kill suspicious processes (dangerous!)
    --fix-network       Block suspicious network connections
    --fix-files         Remove suspicious files (dangerous!)
    --fix-launch        Remove suspicious launch items
    --cleanup-disk      Clean up disk space
    --fix-all           Fix all safe issues (permissions, disk cleanup)
    --from-blueteam FILE  Fix issues from Blue Team results file
    --preview-all       Also preview process and launch-item fixes
    --only CATEGORY     Run one kind of fix: permissions, disk, processes or launch

Safety:
    By default, this runs in DRY-RUN mode (shows what would be fixed)
    Use --execute to actually perform fixes
    Use -y to auto-confirm (use with extreme caution!)

Examples:
    $0                    # Dry-run: show what would be fixed
    $0 --execute          # Actually fix issues (with prompts)
    $0 -y --fix-permissions  # Auto-fix permissions without prompts

EOF
            exit 0
            ;;
        *) shift ;;
    esac
done

# Log remediation action
log_remediation() {
    local action="$1"
    local target="$2"
    local status="$3"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $action | $target | $status" >> "$REMEDIATION_LOG"
}

# Fix file permission issues
fix_file_permissions() {
    if [ "$FIX_PERMISSIONS" != true ]; then
        return 0
    fi
    
    if [ "$QUIET" != true ]; then
        echo "${bold}🔒 Fixing File Permissions...${normal}"
    fi
    
    local fixed=0
    local issues=0
    
    # Find world-writable files in important directories
    local important_dirs=("$HOME/Documents" "$HOME/Desktop" "$HOME/.ssh")
    
    for dir in "${important_dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            continue
        fi
        
        while IFS= read -r -d '' file; do
            if [ -f "$file" ]; then
                issues=$((issues + 1))
                
                if [ "$DRY_RUN" = true ]; then
                    if [ "$QUIET" != true ]; then
                        info "Would fix: $file (remove world-writable)"
                    fi
                    log_remediation "PERMISSION_FIX" "$file" "DRY_RUN"
                else
                    # Backup original permissions
                    local orig_perms=$(stat -f "%OLp" "$file" 2>/dev/null || echo "unknown")
                    echo "$file|$orig_perms" >> "$REMEDIATION_BACKUP/permissions_backup_$(date +%Y%m%d).txt" 2>/dev/null || true
                    
                    # Remove world-writable permission
                    if chmod o-w "$file" 2>/dev/null; then
                        fixed=$((fixed + 1))
                        success "Fixed permissions: $file"
                        log_remediation "PERMISSION_FIX" "$file" "SUCCESS"
                    else
                        warning "Failed to fix: $file"
                        log_remediation "PERMISSION_FIX" "$file" "FAILED"
                    fi
                fi
            fi
        done < <(find "$dir" -type f -perm -002 -print0 2>/dev/null)
    done
    
    if [ $issues -eq 0 ]; then
        success "No permission issues found"
    elif [ "$DRY_RUN" = true ]; then
        info "Found $issues permission issue(s) to fix (dry-run)"
    else
        success "Fixed $fixed permission issue(s)"
    fi
    
    return 0
}

# Fix suspicious processes (with confirmation)
fix_suspicious_processes() {
    if [ "$FIX_PROCESSES" != true ]; then
        return 0
    fi
    
    if [ "$QUIET" != true ]; then
        echo "${bold}⚙️  Analyzing Suspicious Processes...${normal}"
    fi
    
    local suspicious_patterns=("miner" "crypto" "bitcoin" "malware" "trojan" "backdoor" "keylogger")
    local suspicious_pids=()
    
    # Find suspicious processes. Match the program's own name, not its whole
    # path or arguments - otherwise e.g. Malwarebytes (installed under
    # ".../Malwarebytes/...") is flagged as "malware" and would be killed.
    while read -r pid comm; do
        [ -n "$pid" ] || continue
        local name
        name="$(basename "$comm")"
        local matched=false
        for pattern in "${suspicious_patterns[@]}"; do
            if echo "$name" | grep -qi "$pattern"; then matched=true; break; fi
        done
        $matched || continue
        # macOS's own read-only system volume can't hold a dropped program.
        case "$comm" in /System/*|/usr/bin/*|/usr/sbin/*|/usr/libexec/*|/bin/*|/sbin/*) continue ;; esac
        # Skip software signed by Apple or an identified developer; dropped
        # miners and backdoors don't carry a valid Developer ID signature.
        if [ -f "$comm" ] && codesign --verify "$comm" 2>/dev/null && \
           codesign -dv --verbose=2 "$comm" 2>&1 | grep -qE "Authority=(Developer ID Application|(macOS )?Software Signing|Apple Mac OS Application Signing)"; then
            continue
        fi
        suspicious_pids+=("$pid|$comm")
    done < <(ps -axo pid=,comm=)

    if [ ${#suspicious_pids[@]} -eq 0 ]; then
        success "No suspicious processes found"
        return 0
    fi
    
    if [ "$DRY_RUN" = true ]; then
        warning "Found ${#suspicious_pids[@]} suspicious process(es) (dry-run):"
        for item in "${suspicious_pids[@]}"; do
            local pid=$(echo "$item" | cut -d'|' -f1)
            local cmd=$(echo "$item" | cut -d'|' -f2-)
            info "  Would kill: PID $pid - $cmd"
        done
        return 0
    fi
    
    # Ask for confirmation
    if [ "$AUTO_CONFIRM" != true ]; then
        warning "Found ${#suspicious_pids[@]} suspicious process(es):"
        for item in "${suspicious_pids[@]}"; do
            local pid=$(echo "$item" | cut -d'|' -f1)
            local cmd=$(echo "$item" | cut -d'|' -f2-)
            echo "  PID $pid: $cmd"
        done
        echo ""
        read -p "Kill these processes? (y/N): " confirm
        if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
            info "Skipping process termination"
            return 0
        fi
    fi
    
    # Kill processes
    local killed=0
    for item in "${suspicious_pids[@]}"; do
        local pid=$(echo "$item" | cut -d'|' -f1)
        local cmd=$(echo "$item" | cut -d'|' -f2-)
        
        if kill "$pid" 2>/dev/null; then
            killed=$((killed + 1))
            success "Terminated: PID $pid"
            log_remediation "PROCESS_KILL" "PID $pid" "SUCCESS"
        else
            warning "Failed to kill: PID $pid"
            log_remediation "PROCESS_KILL" "PID $pid" "FAILED"
        fi
    done
    
    if [ $killed -gt 0 ]; then
        success "Terminated $killed suspicious process(es)"
    fi
    
    return 0
}

# Clean up disk space
cleanup_disk_space() {
    if [ "$CLEANUP_DISK" != true ]; then
        return 0
    fi
    
    if [ "$QUIET" != true ]; then
        echo "${bold}🧹 Cleaning Up Disk Space...${normal}"
    fi
    
    local freed=0
    
    # Clean common cache directories
    local cache_dirs=(
        "$HOME/Library/Caches"
        "$HOME/.cache"
        "/tmp"
    )
    
    for cache_dir in "${cache_dirs[@]}"; do
        if [ ! -d "$cache_dir" ]; then
            continue
        fi
        
        if [ "$DRY_RUN" = true ]; then
            local size=$(du -sh "$cache_dir" 2>/dev/null | awk '{print $1}' || echo "0")
            info "Would clean: $cache_dir (current size: $size)"
            log_remediation "DISK_CLEANUP" "$cache_dir" "DRY_RUN"
        else
            # Clean old cache files (older than 30 days)
            local cleaned=$( (find "$cache_dir" -type f -mtime +30 -print -delete 2>/dev/null | wc -l | tr -d ' ' || echo "0") | head -1)
            if [ "$cleaned" -gt 0 ]; then
                freed=$((freed + cleaned))
                success "Cleaned $cleaned old cache file(s) from $cache_dir"
                log_remediation "DISK_CLEANUP" "$cache_dir" "SUCCESS"
            fi
        fi
    done
    
    # Clean Homebrew cache
    if command -v brew &> /dev/null; then
        if [ "$DRY_RUN" = true ]; then
            info "Would run: brew cleanup"
            log_remediation "BREW_CLEANUP" "brew cleanup" "DRY_RUN"
        else
            if brew cleanup 2>&1 | grep -q "Removing"; then
                success "Cleaned Homebrew cache"
                log_remediation "BREW_CLEANUP" "brew cleanup" "SUCCESS"
            fi
        fi
    fi
    
    if [ "$DRY_RUN" = true ]; then
        info "Disk cleanup preview complete (dry-run)"
    else
        success "Disk cleanup complete"
    fi
    
    return 0
}

# Fix suspicious launch items
fix_launch_items() {
    if [ "$FIX_LAUNCH_ITEMS" != true ]; then
        return 0
    fi
    
    if [ "$QUIET" != true ]; then
        echo "${bold}🚀 Fixing Suspicious Launch Items...${normal}"
    fi
    
    local suspicious_patterns=("miner" "crypto" "bitcoin" "malware" "backdoor" "trojan" "keylogger")
    local suspicious_items=()
    
    # Check user launch agents
    local user_agents="$HOME/Library/LaunchAgents"
    if [ -d "$user_agents" ]; then
        for plist in "$user_agents"/*.plist; do
            if [ -f "$plist" ]; then
                local basename_plist=$(basename "$plist")
                for pattern in "${suspicious_patterns[@]}"; do
                    if echo "$basename_plist" | grep -qi "$pattern"; then
                        suspicious_items+=("$plist")
                        break
                    fi
                done
            fi
        done
    fi
    
    if [ ${#suspicious_items[@]} -eq 0 ]; then
        success "No suspicious launch items found"
        return 0
    fi
    
    if [ "$DRY_RUN" = true ]; then
        warning "Found ${#suspicious_items[@]} suspicious launch item(s) (dry-run):"
        for item in "${suspicious_items[@]}"; do
            info "  Would remove: $item"
        done
        return 0
    fi
    
    # Ask for confirmation
    if [ "$AUTO_CONFIRM" != true ]; then
        warning "Found ${#suspicious_items[@]} suspicious launch item(s):"
        for item in "${suspicious_items[@]}"; do
            echo "  $item"
        done
        echo ""
        read -p "Remove these launch items? (y/N): " confirm
        if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
            info "Skipping launch item removal"
            return 0
        fi
    fi
    
    # Quarantine launch items
    local removed=0
    for item in "${suspicious_items[@]}"; do
        # Unload first
        launchctl unload "$item" 2>/dev/null || true
        
        # Quarantine instead of deleting
        if manifest_path=$(quarantine_file "$item" "suspicious_launch_item" "LAUNCH_ITEM_REMOVE" 2>/dev/null); then
            removed=$((removed + 1))
            success "Quarantined: $item"
            log_remediation "LAUNCH_ITEM_QUARANTINE" "$item" "SUCCESS"
        else
            warning "Failed to quarantine: $item"
            log_remediation "LAUNCH_ITEM_QUARANTINE" "$item" "FAILED"
        fi
    done
    
    if [ $removed -gt 0 ]; then
        success "Removed $removed suspicious launch item(s)"
    fi
    
    return 0
}

# Parse Blue Team results and fix issues
fix_from_blueteam_results() {
    if [ -z "$BLUETEAM_RESULTS_FILE" ] || [ ! -f "$BLUETEAM_RESULTS_FILE" ]; then
        # Try to find latest Blue Team results
        BLUETEAM_DIR="$CONFIG_DIR/blueteam"
        BLUETEAM_RESULTS_FILE=$(ls -t "$BLUETEAM_DIR"/results_*.txt 2>/dev/null | head -1 || echo "")
        
        if [ -z "$BLUETEAM_RESULTS_FILE" ] || [ ! -f "$BLUETEAM_RESULTS_FILE" ]; then
            warning "No Blue Team results file found. Run Blue Team analysis first."
            return 1
        fi
    fi
    
    if [ "$QUIET" != true ]; then
        echo "${bold}📋 Parsing Blue Team Results...${normal}"
        echo "   Source: $BLUETEAM_RESULTS_FILE"
    fi
    
    local fixes_applied=0
    
    # Extract and fix permission issues
    if grep -q "World-writable\|world-writable\|permission" "$BLUETEAM_RESULTS_FILE" 2>/dev/null; then
        if [ "$FIX_PERMISSIONS" = true ]; then
            fix_file_permissions && fixes_applied=$((fixes_applied + 1))
        fi
    fi
    
    # Extract and fix high CPU/memory processes
    if grep -q "High CPU\|High memory\|high CPU\|high memory" "$BLUETEAM_RESULTS_FILE" 2>/dev/null; then
        if [ "$FIX_PROCESSES" = true ]; then
            # Extract PIDs from results
            local pids=$(grep -oE "PID [0-9]+" "$BLUETEAM_RESULTS_FILE" 2>/dev/null | awk '{print $2}' | sort -u || true)
            if [ -n "$pids" ]; then
                if [ "$DRY_RUN" = true ]; then
                    info "Would investigate high-resource processes: $pids"
                else
                    # Don't auto-kill, just warn
                    warning "High-resource processes detected. Review manually: $pids"
                fi
            fi
        fi
    fi
    
    # Extract and fix suspicious launch items
    if grep -q "launch agent\|LaunchAgent\|suspicious launch" "$BLUETEAM_RESULTS_FILE" 2>/dev/null; then
        if [ "$FIX_LAUNCH_ITEMS" = true ]; then
            fix_launch_items && fixes_applied=$((fixes_applied + 1))
        fi
    fi
    
    # Extract and fix file system anomalies
    if grep -q "anomaly\|suspicious file\|hidden executable" "$BLUETEAM_RESULTS_FILE" 2>/dev/null; then
        if [ "$FIX_FILES" = true ]; then
            # Extract file paths
            local suspicious_files=$(grep -oE "/[^ ]+\.(exe|bat|scr|vbs|ps1)" "$BLUETEAM_RESULTS_FILE" 2>/dev/null | sort -u || true)
            if [ -n "$suspicious_files" ]; then
                if [ "$DRY_RUN" = true ]; then
                    warning "Would review suspicious files (dry-run):"
                    echo "$suspicious_files" | head -10
                else
                    if [ "$AUTO_CONFIRM" != true ]; then
                        warning "Suspicious files found. Review manually:"
                        echo "$suspicious_files" | head -10
                        read -p "Remove these files? (y/N): " confirm
                        if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
                            for file in $suspicious_files; do
                                if [ -f "$file" ]; then
                                    # Quarantine instead of deleting
                                    if manifest_path=$(quarantine_file "$file" "suspicious_file_from_blueteam" "FILE_REMOVE" 2>/dev/null); then
                                        success "Quarantined: $file"
                                        log_remediation "FILE_QUARANTINE" "$file" "SUCCESS"
                                        fixes_applied=$((fixes_applied + 1))
                                    else
                                        warning "Failed to quarantine: $file"
                                        log_remediation "FILE_QUARANTINE" "$file" "FAILED"
                                    fi
                                fi
                            done
                        fi
                    fi
                fi
            fi
        fi
    fi
    
    return $fixes_applied
}

# Main remediation function
main() {
    if [ "$QUIET" != true ]; then
        echo "${bold}🔧 Mac Remediation - Auto-Fix Security Issues${normal}"
        echo "=========================================="
        echo ""
        
        if [ "$DRY_RUN" = true ]; then
            echo "${yellow}⚠️  DRY-RUN MODE: No changes will be made${normal}"
            echo "${yellow}   Use --execute to actually perform fixes${normal}"
            echo ""
        else
            echo "${red}⚠️  EXECUTION MODE: Changes will be made!${normal}"
            if [ "$AUTO_CONFIRM" != true ]; then
                echo "${yellow}   You will be prompted for dangerous operations${normal}"
            fi
            echo ""
        fi
    fi
    
    log_message "INFO" "Remediation started - Dry-run: $DRY_RUN, Auto-confirm: $AUTO_CONFIRM"
    
    local fixes_applied=0
    
    # If --from-blueteam or --fix-all, parse Blue Team results first
    if [ "$FIX_ALL" = true ] || [ -n "$BLUETEAM_RESULTS_FILE" ]; then
        fix_from_blueteam_results && fixes_applied=$((fixes_applied + $?))
    fi
    
    # Run standard remediation tasks
    if [ "$FIX_PERMISSIONS" = true ]; then
        fix_file_permissions && fixes_applied=$((fixes_applied + 1))
    fi
    
    if [ "$CLEANUP_DISK" = true ]; then
        cleanup_disk_space && fixes_applied=$((fixes_applied + 1))
    fi
    
    # Dangerous operations (require explicit flags)
    if [ "$FIX_PROCESSES" = true ]; then
        fix_suspicious_processes && fixes_applied=$((fixes_applied + 1))
    fi
    
    if [ "$FIX_LAUNCH_ITEMS" = true ]; then
        fix_launch_items && fixes_applied=$((fixes_applied + 1))
    fi
    
    # Create rollback manifest if files were quarantined
    if [ "$DRY_RUN" != true ] && [ $fixes_applied -gt 0 ]; then
        create_rollback_manifest "$SESSION_ID" >/dev/null 2>&1 || true
    fi
    
    # Summary
    if [ "$QUIET" != true ]; then
        echo ""
        if [ "$DRY_RUN" = true ]; then
            echo "${bold}${cyan}✅ Remediation Preview Complete${normal}"
            echo "${cyan}   Review the changes above and run with --execute to apply${normal}"
        else
            echo "${bold}${green}✅ Remediation Complete${normal}"
            echo "${green}   Applied $fixes_applied fix(es)${normal}"
            if [ $fixes_applied -gt 0 ]; then
                echo ""
                echo "${cyan}📋 Quarantine Info:${normal}"
                echo "   Quarantine: $QUARANTINE_DIR"
                echo "   Manifests: $QUARANTINE_MANIFEST"
                echo "   To restore files: ./quarantine_manager.sh list"
                echo "   To restore a file: ./quarantine_manager.sh restore <manifest>"
            fi
        fi
        echo ""
        echo "Remediation log: $REMEDIATION_LOG"
        echo "Backups: $REMEDIATION_BACKUP"
    fi
    
    log_message "INFO" "Remediation completed - Fixes applied: $fixes_applied"
    
    exit 0
}

main "$@"

