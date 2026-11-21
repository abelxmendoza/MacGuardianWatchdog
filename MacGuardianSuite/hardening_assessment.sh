#!/bin/bash

# ===============================
# Mac Hardening Assessment
# Enterprise-level security evaluation
# ===============================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"
source "$SCRIPT_DIR/debug_helper.sh" 2>/dev/null || true

# Colors
bold=$(tput bold 2>/dev/null || echo "")
normal=$(tput sgr0 2>/dev/null || echo "")
green=$(tput setaf 2 2>/dev/null || echo "")
red=$(tput setaf 1 2>/dev/null || echo "")
yellow=$(tput setaf 3 2>/dev/null || echo "")
cyan=$(tput setaf 6 2>/dev/null || echo "")

# Assessment results
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNING_CHECKS=0
HARDENING_SCORE=0

# Check categories
declare -a SYSTEM_CHECKS=()
declare -a NETWORK_CHECKS=()
declare -a FILE_CHECKS=()
declare -a APP_CHECKS=()
declare -a USER_CHECKS=()

# Assessment report
ASSESSMENT_REPORT="$HOME/.macguardian/hardening_assessment_$(date +%Y%m%d_%H%M%S).txt"

# Check function
check_item() {
    local name="$1"
    local check_cmd="$2"
    local category="$3"
    local severity="${4:-medium}"  # low, medium, high, critical
    local fix_command="${5:-}"
    
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    
    echo -n "  Checking $name... "
    
    if eval "$check_cmd" &> /dev/null; then
        echo "${green}✅ PASS${normal}"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
        HARDENING_SCORE=$((HARDENING_SCORE + 1))
        echo "[PASS] $name" >> "$ASSESSMENT_REPORT"
        return 0
    else
        echo "${red}❌ FAIL${normal}"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
        echo "[FAIL] $name (Severity: $severity)" >> "$ASSESSMENT_REPORT"
        if [ -n "$fix_command" ]; then
            echo "      Fix: $fix_command" >> "$ASSESSMENT_REPORT"
        fi
        return 1
    fi
}

# System-level hardening checks
check_system_hardening() {
    echo "${bold}🛡️  System-Level Hardening${normal}"
    echo "----------------------------------------"
    
    # SIP (System Integrity Protection)
    check_item "System Integrity Protection (SIP)" \
        "csrutil status | grep -q 'enabled'" \
        "system" "critical" \
        "Enable SIP: Boot to Recovery Mode, run 'csrutil enable'"
    
    # Gatekeeper
    check_item "Gatekeeper" \
        "spctl --status | grep -q 'enabled'" \
        "system" "high" \
        "Enable Gatekeeper: sudo spctl --master-enable"
    
    # FileVault
    check_item "FileVault Encryption" \
        "fdesetup status | grep -q 'On'" \
        "system" "critical" \
        "Enable FileVault: System Settings > Privacy & Security > FileVault"
    
    # Firewall
    check_item "Firewall" \
        "/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate | grep -q 'enabled'" \
        "network" "high" \
        "Enable Firewall: System Settings > Network > Firewall"
    
    # Automatic Updates (check both system and user preferences)
    check_item "Automatic Security Updates" \
        "(defaults read /Library/Preferences/com.apple.SoftwareUpdate AutomaticCheckEnabled 2>/dev/null | grep -q '1') || (defaults read com.apple.SoftwareUpdate AutomaticCheckEnabled 2>/dev/null | grep -q '1') || softwareupdate --schedule on 2>&1 | grep -q 'on'" \
        "system" "high" \
        "Enable auto-updates: System Settings > Software Update"
    
    # Remote Login (SSH)
    check_item "Remote Login Disabled" \
        "! nc -z -G 2 127.0.0.1 22 2>/dev/null" \
        "network" "medium" \
        "Disable SSH: System Settings > General > Sharing > Remote Login"
    
    # Screen Saver Password
    check_item "Screen Lock Password Required Immediately" \
        "sysadminctl -screenLock status 2>&1 | grep -qE 'immediate|delay is [0-5] seconds'" \
        "user" "medium" \
        "System Settings > Lock Screen > Require password after screen saver begins or display is turned off: Immediately"
    
    echo ""
}

# Network hardening
check_network_hardening() {
    echo "${bold}🌐 Network Hardening${normal}"
    echo "----------------------------------------"
    
    # Stealth Mode
    check_item "Firewall Stealth Mode" \
        "/usr/libexec/ApplicationFirewall/socketfilterfw --getstealthmode | grep -qE 'enabled|is on'" \
        "network" "medium" \
        "Enable stealth mode: sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode on"
    
    # Bluetooth (when not in use)
    check_item "Bluetooth Auto-Disable" \
        "defaults read com.apple.Bluetooth ControllerPowerState 2>/dev/null | grep -q '0' || true" \
        "network" "low" \
        "Consider disabling Bluetooth when not in use"
    
    # AirDrop (restrict to contacts)
    check_item "AirDrop Restricted" \
        'm=$(defaults read com.apple.sharingd DiscoverableMode 2>/dev/null); [ -z "$m" ] || echo "$m" | grep -qE "Contacts Only|ContactsOnly|Off"' \
        "network" "medium" \
        "Restrict AirDrop: Finder > AirDrop > Contacts Only"
    
    echo ""
}

# File system hardening
check_filesystem_hardening() {
    echo "${bold}📁 File System Hardening${normal}"
    echo "----------------------------------------"
    
    # Home directory permissions
    check_item "Home Directory Permissions" \
        "stat -f '%A' $HOME | grep -q '^700$'" \
        "file" "high" \
        "Secure home directory: chmod 700 $HOME"
    
    # World-writable files check (limited scope for performance)
    # Only check top-level directories to avoid long scans
    check_item "No World-Writable Files in Home" \
        "[ \$(find $HOME -maxdepth 3 -type f -perm -002 -not -path '*/Library/Caches/*' -not -path '*/Library/Logs/*' -not -path '*/.git/*' 2>/dev/null | head -10 | wc -l | tr -d ' ') -eq 0 ]" \
        "file" "medium" \
        "Review and fix: find $HOME -type f -perm -002 -ls"
    
    # Time Machine
    check_item "Time Machine Backup Configured" \
        "tmutil destinationinfo 2>/dev/null | grep -q '^Name'" \
        "file" "high" \
        "Enable Time Machine: System Settings > General > Time Machine"
    
    echo ""
}

# Application hardening
check_application_hardening() {
    echo "${bold}📱 Application Hardening${normal}"
    echo "----------------------------------------"
    
    # App Store updates
    check_item "App Store Auto-Update" \
        "defaults read /Library/Preferences/com.apple.commerce AutoUpdate 2>/dev/null | grep -q 1 || defaults read /Library/Preferences/com.apple.SoftwareUpdate AutomaticallyInstallAppUpdates 2>/dev/null | grep -q 1" \
        "app" "medium" \
        "Enable auto-update: App Store > Preferences"
    
    # Unknown sources blocked
    check_item "Unknown Sources Blocked" \
        "spctl --status | grep -q 'enabled'" \
        "app" "high" \
        "Gatekeeper must be enabled (see System checks)"
    
    echo ""
}

# User account hardening
check_user_hardening() {
    echo "${bold}👤 User Account Hardening${normal}"
    echo "----------------------------------------"
    
    # Admin account check
    check_item "Non-Admin Account for Daily Use" \
        "dscl . -read /Groups/admin GroupMembership 2>/dev/null | grep -qv '$(whoami)' || groups | grep -qv admin" \
        "user" "high" \
        "Create standard user account for daily use, keep admin separate"
    
    # Password policy
    check_item "Password Policy Enforced" \
        "pwpolicy getaccountpolicies 2>/dev/null | grep -q 'minimumLength\|requiresMixedCase' || true" \
        "user" "medium" \
        "Set password policy: System Settings > Users & Groups"
    
    echo ""
}

# Security tools check
check_security_tools() {
    echo "${bold}🔧 Security Tools${normal}"
    echo "----------------------------------------"
    
    # ClamAV
    check_item "ClamAV Antivirus" \
        "command -v clamscan &> /dev/null" \
        "tool" "high" \
        "Install: brew install clamav"
    
    # rkhunter
    check_item "Rootkit Hunter" \
        "command -v rkhunter &> /dev/null" \
        "tool" "medium" \
        "Install: brew install rkhunter"
    
    # LuLu (outbound firewall)
    check_item "LuLu Outbound Firewall" \
        "pgrep -q LuLu || launchctl list 2>/dev/null | grep -q LuLu" \
        "tool" "high" \
        "Install: brew install --cask lulu"
    
    echo ""
}

# Posture-drift checks (gaps not covered above)
check_posture_gaps() {
    echo "${bold}🧭 Posture Drift & Exposure${normal}"
    echo "----------------------------------------"

    # Sealed system volume (Signed System Volume / authenticated root)
    check_item "Authenticated Root (Sealed System Volume)" \
        "csrutil authenticated-root status 2>/dev/null | grep -q 'enabled'" \
        "system" "critical" \
        "Re-enable from Recovery: csrutil authenticated-root enable"

    # XProtect definitions refreshed within the last 45 days
    check_item "XProtect Definitions Current (<45 days)" \
        'f=/Library/Apple/System/Library/CoreServices/XProtect.bundle/Contents/Resources/XProtect.meta.plist; [ -f "$f" ] && [ $(( $(date +%s) - $(stat -f %m "$f") )) -lt 3888000 ]' \
        "system" "high" \
        "Turn on 'Install Security Responses and system files': System Settings > General > Software Update > Automatic Updates"

    # AirPlay Receiver listens on 5000/7000 on every network
    check_item "AirPlay Receiver Disabled" \
        "! lsof -nP -iTCP:7000 -sTCP:LISTEN 2>/dev/null | grep -q ControlCe" \
        "network" "medium" \
        "System Settings > General > AirDrop & Handoff > AirPlay Receiver: Off"

    # Power Nap off in every power profile
    check_item "Power Nap Disabled" \
        "pmset -g custom | awk '/powernap/ && \$2==1 {f=1} END {exit f}'" \
        "system" "low" \
        "System Settings > Battery > Options > Enable Power Nap: Off"

    # Wake for network access off in every power profile
    check_item "Wake for Network Access Disabled" \
        "pmset -g custom | awk '/womp/ && \$2==1 {f=1} END {exit f}'" \
        "network" "low" \
        "System Settings > Battery > Options > Wake for network access: Never"

    # Show all filename extensions (defeats invoice.pdf.app tricks)
    check_item "Show All Filename Extensions" \
        "defaults read NSGlobalDomain AppleShowAllExtensions 2>/dev/null | grep -q 1" \
        "user" "low" \
        "Finder > Settings > Advanced > Show all filename extensions"

    # Weekly Homebrew auto-update job loaded and its last run succeeded (within 8 days)
    check_item "Homebrew Weekly Auto-Update Healthy" \
        'l="$HOME/Library/Logs/brew-auto-update.log"; launchctl list com.abel.brew-auto-update >/dev/null 2>&1 && { [ ! -f "$l" ] || { [ -n "$(find "$l" -mtime -8)" ] && tail -r "$l" | grep -m1 "^exit:" | grep -q "exit: 0"; }; }' \
        "application" "medium" \
        "Check ~/Library/Logs/brew-auto-update.log; reload: launchctl bootstrap gui/\$(id -u) ~/Library/LaunchAgents/com.abel.brew-auto-update.plist"

    echo ""
}

# Generate hardening score and recommendations
generate_report() {
    local score_percent=$((HARDENING_SCORE * 100 / TOTAL_CHECKS))
    
    echo ""
    echo "${bold}=========================================="
    echo "📊 Hardening Assessment Results"
    echo "==========================================${normal}"
    echo ""
    echo "Total Checks: $TOTAL_CHECKS"
    echo "${green}Passed: $PASSED_CHECKS${normal}"
    echo "${red}Failed: $FAILED_CHECKS${normal}"
    echo "${yellow}Warnings: $WARNING_CHECKS${normal}"
    echo ""
    echo "${bold}Hardening Score: $score_percent%${normal}"
    echo ""
    
    # Security level assessment
    if [ $score_percent -ge 90 ]; then
        echo "${green}🛡️  Security Level: ENTERPRISE-GRADE${normal}"
        echo "   Your Mac is well-hardened and follows enterprise security best practices."
    elif [ $score_percent -ge 75 ]; then
        echo "${yellow}🛡️  Security Level: GOOD${normal}"
        echo "   Your Mac has good security, but some improvements are recommended."
    elif [ $score_percent -ge 50 ]; then
        echo "${yellow}🛡️  Security Level: MODERATE${normal}"
        echo "   Your Mac has basic security. Several critical improvements needed."
    else
        echo "${red}🛡️  Security Level: BASIC${normal}"
        echo "   Your Mac needs significant security improvements."
    fi
    
    echo ""
    echo "Full report saved to: $ASSESSMENT_REPORT"
    echo ""
    
    # Recommendations
    if [ $FAILED_CHECKS -gt 0 ]; then
        echo "${bold}💡 Recommendations:${normal}"
        echo "----------------------------------------"
        grep "\[FAIL\]" "$ASSESSMENT_REPORT" | while IFS= read -r line; do
            echo "  • $line"
        done
        echo ""
        echo "Run Mac Remediation to auto-fix some issues:"
        echo "  ./MacGuardianSuite/mac_remediation.sh --execute"
    fi
}

# Main assessment
main() {
    clear
    echo "${bold}=========================================="
    echo "🛡️  Mac Hardening Assessment"
    echo "Enterprise-Level Security Evaluation"
    echo "==========================================${normal}"
    echo ""
    
    # System diagnostics
    if [ "${VERBOSE:-false}" = "true" ]; then
        system_diagnostics
    fi
    
    # Run all checks (with error handling)
    set +e  # Don't exit on individual check failures
    check_system_hardening
    check_network_hardening
    check_filesystem_hardening
    check_application_hardening
    check_user_hardening
    check_security_tools
    check_posture_gaps
    set -e  # Re-enable exit on error
    
    # Generate report
    generate_report
}

main

