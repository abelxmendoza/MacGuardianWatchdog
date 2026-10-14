#!/bin/bash

# ===============================
# 🔍 Mac Security Audit v1.0
# Comprehensive Security Auditing & Hardening
# Enterprise-grade security assessment
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

# Security Audit specific config
AUDIT_DIR="$CONFIG_DIR/security_audit"
AUDIT_REPORT="$AUDIT_DIR/audit_report_$(date +%Y%m%d_%H%M%S).txt"
mkdir -p "$AUDIT_DIR"

# Parse arguments
QUIET=false
JSON=false
VERBOSE=false
RUN_LYNIS=false
CHECK_FILEVAULT=true
CHECK_LAUNCH_ITEMS=true
CHECK_SIP=true
CHECK_GATEKEEPER=true

while [[ $# -gt 0 ]]; do
    case $1 in
        -q|--quiet) QUIET=true; shift ;;
        --json) JSON=true; QUIET=true; shift ;;
        -v|--verbose) VERBOSE=true; shift ;;
        --lynis) RUN_LYNIS=true; shift ;;
        --no-filevault) CHECK_FILEVAULT=false; shift ;;
        --no-launch) CHECK_LAUNCH_ITEMS=false; shift ;;
        --no-certs) shift ;;  # certificate check removed; flag kept for compatibility
        -h|--help)
            cat <<EOF
Mac Security Audit - Comprehensive Security Assessment

Usage: $0 [OPTIONS]

Options:
    -h, --help          Show this help
    -q, --quiet         Minimal output
    --json              Print results as JSON (used by the app)
    -v, --verbose       Detailed output
    --lynis             Run full lynis security audit
    --no-filevault      Skip FileVault check
    --no-launch         Skip launch items check

EOF
            exit 0
            ;;
        *) shift ;;
    esac
done

# Each check records one result for the JSON summary.
CHECK_RESULTS=()
json_str() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
# record_check NAME CATEGORY STATUS(pass|warning|fail) SEVERITY DESCRIPTION RECOMMENDATION
record_check() {
    CHECK_RESULTS+=("{\"name\": \"$(json_str "$1")\", \"category\": \"$(json_str "$2")\", \"status\": \"$3\", \"severity\": \"$4\", \"description\": \"$(json_str "$5")\", \"recommendation\": \"$(json_str "$6")\"}")
}

# In JSON mode, everything except the final JSON goes to /dev/null so the
# app can parse the output directly.
if [ "$JSON" = true ]; then
    exec 3>&1 >/dev/null 2>&1
fi

# Check FileVault encryption status
check_filevault() {
    if [ "$CHECK_FILEVAULT" != true ]; then
        return 0
    fi
    
    if [ "$QUIET" != true ]; then
        echo "${bold}🔐 FileVault Encryption Status...${normal}"
    fi
    
    local fv_status=""
    if command -v fdesetup &> /dev/null; then
        set +e
        fv_status=$(fdesetup status 2>/dev/null)
        set -e
        
        if echo "$fv_status" | grep -q "FileVault is On"; then
            success "FileVault is enabled - Disk encryption is active"
            record_check "FileVault disk encryption" "Encryption" pass high "FileVault is on, so your data is unreadable without your password if the Mac is lost or stolen." ""
            log_message "SUCCESS" "FileVault encryption enabled"
            return 0
        elif echo "$fv_status" | grep -q "FileVault is Off"; then
            warning "FileVault is DISABLED - Your disk is not encrypted!"
            record_check "FileVault disk encryption" "Encryption" fail high "FileVault is off: anyone with physical access to this Mac can read its disk." "Turn on FileVault in System Settings → Privacy & Security → FileVault."
            log_message "WARNING" "FileVault encryption disabled"
            return 1
        else
            warning "Could not determine FileVault status"
            record_check "FileVault disk encryption" "Encryption" warning high "Could not read FileVault status." "Check System Settings → Privacy & Security → FileVault."
            log_message "WARNING" "FileVault status unknown"
            return 1
        fi
    else
        warning "fdesetup command not available"
        return 1
    fi
}

# Check launch agents and daemons for suspicious items
check_launch_items() {
    if [ "$CHECK_LAUNCH_ITEMS" != true ]; then
        return 0
    fi
    
    if [ "$QUIET" != true ]; then
        echo "${bold}🚀 Launch Items & Persistence Mechanisms...${normal}"
    fi
    
    local issues=0
    local suspicious_patterns=("miner" "crypto" "bitcoin" "malware" "backdoor" "trojan" "keylogger")
    
    # Check user launch agents
    local user_agents="$HOME/Library/LaunchAgents"
    if [ -d "$user_agents" ]; then
        local agent_count=$(find "$user_agents" -name "*.plist" 2>/dev/null | wc -l | tr -d ' ')
        if [ "$agent_count" -gt 0 ]; then
            info "Found $agent_count user launch agent(s)"
            
            # Check for suspicious patterns
            for plist in "$user_agents"/*.plist; do
                if [ -f "$plist" ]; then
                    local basename_plist=$(basename "$plist")
                    for pattern in "${suspicious_patterns[@]}"; do
                        if echo "$basename_plist" | grep -qi "$pattern"; then
                            warning "Suspicious launch agent: $basename_plist"
                            issues=$((issues + 1))
                            log_message "WARNING" "Suspicious launch agent: $plist"
                        fi
                    done
                fi
            done
        fi
    fi
    
    # Check system launch agents (requires sudo)
    if sudo -n true 2>/dev/null; then
        local system_agents="/Library/LaunchAgents"
        if [ -d "$system_agents" ]; then
            local sys_count=$(sudo find "$system_agents" -name "*.plist" 2>/dev/null | wc -l | tr -d ' ')
            if [ "$sys_count" -gt 0 ] && [ "$VERBOSE" = true ]; then
                info "Found $sys_count system launch agent(s)"
            fi
        fi
        
        # Check launch daemons
        local system_daemons="/Library/LaunchDaemons"
        if [ -d "$system_daemons" ]; then
            local daemon_count=$(sudo find "$system_daemons" -name "*.plist" 2>/dev/null | wc -l | tr -d ' ')
            if [ "$daemon_count" -gt 0 ] && [ "$VERBOSE" = true ]; then
                info "Found $daemon_count system launch daemon(s)"
            fi
        fi
    fi
    
    # List active launch items
    if [ "$VERBOSE" = true ]; then
        info "Active launch items:"
        launchctl list 2>/dev/null | head -20 || true
    fi
    
    if [ $issues -eq 0 ]; then
        success "No suspicious launch items detected"
        record_check "Startup items" "Persistence" pass medium "No launch agent has a name associated with miners, backdoors or keyloggers." ""
        return 0
    else
        warning "Found $issues suspicious launch item(s)"
        record_check "Startup items" "Persistence" warning medium "Found $issues launch agent(s) with a suspicious name in ~/Library/LaunchAgents." "Open ~/Library/LaunchAgents, check what each flagged item belongs to, and remove it if you don't recognise it."
        return 1
    fi
}

# Check the macOS application firewall
check_firewall() {
    if [ "$QUIET" != true ]; then
        echo "${bold}🧱 Firewall...${normal}"
    fi
    local state
    state=$(/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null || echo "")
    if echo "$state" | grep -q "enabled"; then
        success "Firewall is enabled"
        record_check "Firewall" "Network" pass high "The macOS firewall is on and blocks unwanted incoming connections." ""
        return 0
    fi
    warning "Firewall is disabled"
    record_check "Firewall" "Network" fail high "The macOS firewall is off, so any app can accept incoming connections from the network." "Turn it on in System Settings → Network → Firewall."
    return 1
}

# Check that macOS installs security updates automatically
check_auto_updates() {
    if [ "$QUIET" != true ]; then
        echo "${bold}⬇️  Automatic Security Updates...${normal}"
    fi
    local prefs=/Library/Preferences/com.apple.SoftwareUpdate
    local critical config
    critical=$(defaults read "$prefs" CriticalUpdateInstall 2>/dev/null || echo "1")
    config=$(defaults read "$prefs" ConfigDataInstall 2>/dev/null || echo "1")
    if [ "$critical" = "1" ] && [ "$config" = "1" ]; then
        success "Security responses and system files install automatically"
        record_check "Automatic security updates" "Updates" pass high "macOS installs security responses and system data files (like malware definitions) on its own." ""
        return 0
    fi
    warning "Automatic security updates are off"
    record_check "Automatic security updates" "Updates" warning high "macOS is not set to install security responses and system files automatically, so fixes for actively exploited bugs can be delayed." "Turn on 'Install Security Responses and system files' in System Settings → General → Software Update → Automatic Updates."
    return 1
}

# Check whether Remote Login (SSH) accepts connections
check_remote_login() {
    if [ "$QUIET" != true ]; then
        echo "${bold}🔑 Remote Login (SSH)...${normal}"
    fi
    if netstat -an -p tcp 2>/dev/null | grep -qE '[.*]22 .*LISTEN'; then
        warning "Remote Login (SSH) is on"
        record_check "Remote Login (SSH)" "Network" warning medium "Remote Login is on, so this Mac accepts SSH logins from the network. That's fine if you use it; otherwise it's an open door." "If you don't log in to this Mac remotely, turn off Remote Login in System Settings → General → Sharing."
        return 1
    fi
    success "Remote Login (SSH) is off"
    record_check "Remote Login (SSH)" "Network" pass medium "Remote Login is off, so nobody can SSH into this Mac." ""
    return 0
}

# Run lynis security audit
run_lynis_audit() {
    if [ "$RUN_LYNIS" != true ]; then
        return 0
    fi
    
    if [ "$QUIET" != true ]; then
        echo "${bold}🛡️ Running Lynis Security Audit...${normal}"
        echo "   This may take a few minutes..."
    fi
    
    # Check if lynis is installed
    if ! command -v lynis &> /dev/null; then
        if [ "$QUIET" != true ]; then
            warning "Lynis not found. Installing..."
        fi
        
        set +e
        if brew install lynis 2>&1; then
            set -e
            success "Lynis installed successfully"
        else
            set -e
            warning "Lynis installation failed. Skipping audit"
            return 1
        fi
    fi
    
    # Run lynis audit
    local lynis_output="$AUDIT_DIR/lynis_audit_$(date +%Y%m%d_%H%M%S).txt"
    set +e
    if lynis audit system --quick 2>&1 | tee "$lynis_output"; then
        set -e
        success "Lynis audit completed - Report: $lynis_output"
        log_message "SUCCESS" "Lynis audit completed"
        return 0
    else
        set -e
        warning "Lynis audit encountered issues"
        log_message "WARNING" "Lynis audit had issues"
        return 1
    fi
}

# Check System Integrity Protection (SIP)
check_sip() {
    if [ "$CHECK_SIP" != true ]; then
        return 0
    fi
    
    if [ "$QUIET" != true ]; then
        echo "${bold}🛡️ System Integrity Protection (SIP)...${normal}"
    fi
    
    if command -v csrutil &> /dev/null; then
        set +e
        local sip_status=$(csrutil status 2>/dev/null)
        set -e
        
        if echo "$sip_status" | grep -q "System Integrity Protection status: enabled"; then
            success "SIP is enabled"
            record_check "System Integrity Protection" "System" pass critical "SIP is on, protecting macOS system files from modification, even by administrators." ""
            log_message "SUCCESS" "SIP enabled"
            return 0
        else
            warning "SIP may be disabled or status unknown"
            record_check "System Integrity Protection" "System" fail critical "SIP is off or its status is unknown; malware with admin rights could modify macOS itself." "Restart into Recovery, open Terminal and run: csrutil enable"
            log_message "WARNING" "SIP status unclear"
            return 1
        fi
    else
        info "csrutil not available (may require Recovery Mode)"
        return 0
    fi
}

# Check Gatekeeper status
check_gatekeeper() {
    if [ "$CHECK_GATEKEEPER" != true ]; then
        return 0
    fi
    
    if [ "$QUIET" != true ]; then
        echo "${bold}🚪 Gatekeeper Status...${normal}"
    fi
    
    if command -v spctl &> /dev/null; then
        set +e
        local gatekeeper_status=$(spctl --status 2>/dev/null)
        set -e
        
        if echo "$gatekeeper_status" | grep -q "assessments enabled"; then
            success "Gatekeeper is enabled"
            record_check "Gatekeeper" "Apps" pass high "Gatekeeper is on, so unsigned or known-malicious apps are blocked from opening." ""
            log_message "SUCCESS" "Gatekeeper enabled"
            return 0
        else
            warning "Gatekeeper may be disabled"
            record_check "Gatekeeper" "Apps" fail high "Gatekeeper is off, so any downloaded app can run without a check." "Run: sudo spctl --master-enable"
            log_message "WARNING" "Gatekeeper disabled or unknown"
            return 1
        fi
    else
        warning "spctl command not available"
        return 1
    fi
}

# Main audit function
main() {
    if [ "$QUIET" != true ]; then
        echo "${bold}🔍 Mac Security Audit - Comprehensive Security Assessment${normal}"
        echo "=========================================="
        echo ""
    fi
    
    log_message "INFO" "Security audit started"
    
    local total_issues=0
    
    # Run security checks
    check_filevault || total_issues=$((total_issues + 1))
    check_launch_items || total_issues=$((total_issues + 1))
    check_sip || total_issues=$((total_issues + 1))
    check_gatekeeper || total_issues=$((total_issues + 1))
    check_firewall || total_issues=$((total_issues + 1))
    check_auto_updates || total_issues=$((total_issues + 1))
    check_remote_login || total_issues=$((total_issues + 1))
    
    # Run lynis if requested
    if [ "$RUN_LYNIS" = true ]; then
        run_lynis_audit || total_issues=$((total_issues + 1))
    fi
    
    # Summary
    if [ "$QUIET" != true ]; then
        echo ""
        if [ $total_issues -eq 0 ]; then
            echo "${bold}${green}✅ Security Audit Complete - No Issues Detected${normal}"
        else
            echo "${bold}${yellow}⚠️  Security Audit Complete - $total_issues Issue(s) Detected${normal}"
            echo "${yellow}   Review the findings above for details.${normal}"
            send_notification "Security Audit Alert" "$total_issues security issue(s) found" "${NOTIFICATION_SOUND:-true}" "critical"
        fi
        echo ""
        echo "Detailed logs: $AUDIT_DIR"
    fi
    
    log_message "INFO" "Security audit completed - $total_issues issues found"

    if [ "$JSON" = true ]; then
        local passed=0 failed=0 warnings=0
        for r in "${CHECK_RESULTS[@]}"; do
            case "$r" in
                *'"status": "pass"'*) passed=$((passed + 1)) ;;
                *'"status": "fail"'*) failed=$((failed + 1)) ;;
                *) warnings=$((warnings + 1)) ;;
            esac
        done
        local total=${#CHECK_RESULTS[@]}
        # Warnings count half: they're risks worth reviewing, not failures.
        local score=0
        [ "$total" -gt 0 ] && score=$(( (passed * 100 + warnings * 50) / total ))
        {
            echo "{"
            echo "  \"checks\": ["
            local i=0
            for r in "${CHECK_RESULTS[@]}"; do
                i=$((i + 1))
                if [ "$i" -lt "$total" ]; then echo "    $r,"; else echo "    $r"; fi
            done
            echo "  ],"
            echo "  \"summary\": {\"score\": $score, \"passed\": $passed, \"failed\": $failed, \"warnings\": $warnings, \"total\": $total}"
            echo "}"
        } >&3
    fi

    exit 0
}

main "$@"

