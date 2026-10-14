#!/bin/bash

# ===============================
# Scheduled Automated Reports
# Generates and emails security reports on schedule
# ===============================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"
source "$SCRIPT_DIR/config.sh"

# Load SMTP credentials from ~/.zshrc if not already set
if [ -z "${SMTP_USERNAME:-}" ] || [ -z "${SMTP_PASSWORD:-}" ]; then
    if [ -f ~/.zshrc ]; then
        eval $(grep "^export SMTP_USERNAME=" ~/.zshrc 2>/dev/null || true)
        eval $(grep "^export SMTP_PASSWORD=" ~/.zshrc 2>/dev/null || true)
    fi
fi

# Report configuration
REPORT_DIR="${REPORT_DIR:-$HOME/.macguardian/reports}"
REPORT_EMAIL="${REPORT_EMAIL:-}"
REPORT_SCHEDULE="${REPORT_SCHEDULE:-daily}"  # daily, weekly, monthly
REPORT_FORMAT="${REPORT_FORMAT:-html}"  # html, text, json

mkdir -p "$REPORT_DIR"

# Generate executive summary
generate_executive_summary() {
    local report_file="$1"
    local date=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Try to embed logo as base64
    local logo_base64=""
    local logo_paths=(
        "$SCRIPT_DIR/../MacGuardianSuiteUI/Resources/images/MacGuardianLogo.png"
        "$SCRIPT_DIR/../MacGuardianSuiteUI/Resources/MacGuardianLogo.png"
        "$HOME/Desktop/MacGuardianProject/MacGuardianSuiteUI/Resources/images/MacGuardianLogo.png"
    )
    
    for logo_path in "${logo_paths[@]}"; do
        if [ -f "$logo_path" ]; then
            if command -v base64 &> /dev/null; then
                logo_base64=$(base64 -i "$logo_path" 2>/dev/null || base64 "$logo_path" 2>/dev/null || echo "")
                if [ -n "$logo_base64" ]; then
                    logo_base64="data:image/png;base64,$logo_base64"
                    break
                fi
            fi
        fi
    done
    
    # Pre-calculate values
    local security_score=$(get_security_score)
    local total_issues=$(get_total_issues)
    local fixed_issues=$(get_fixed_issues)
    local scans_run=$(get_scans_run)
    local status_table=$(generate_status_table)
    local threats_section=$(generate_threats_section)
    local recommendations=$(generate_recommendations)
    
    cat > "$report_file" <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>🛡️ MacGuardian Security Report - $date</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; margin: 0; padding: 0; background: #0D0D12; color: #E0E0E0; }
        .container { max-width: 1200px; margin: 0 auto; background: #1a1a24; padding: 0; }
        .omega-header { background: linear-gradient(135deg, #0D0D12 0%, #1a1a24 100%); padding: 40px 30px; border-bottom: 3px solid #8A29F0; display: flex; align-items: center; gap: 20px; }
        .omega-header-content { flex: 1; }
        .omega-logo-img { width: 80px; height: 80px; object-fit: contain; }
        .omega-logo { color: #8A29F0; font-size: 36px; font-weight: bold; margin-bottom: 10px; }
        .omega-title { color: #FFFFFF; font-size: 32px; font-weight: bold; margin-bottom: 5px; }
        .omega-subtitle { color: #8A29F0; font-size: 16px; letter-spacing: 3px; margin-top: 15px; font-weight: 600; }
        .content { padding: 30px; }
        h1 { color: #FFFFFF; border-bottom: 3px solid #8A29F0; padding-bottom: 10px; margin-top: 0; }
        h2 { color: #8A29F0; margin-top: 30px; font-size: 24px; }
        .summary { background: #0D0D12; padding: 25px; border-radius: 8px; margin: 20px 0; border: 1px solid #8A29F0; }
        .metric { display: inline-block; margin: 10px 20px 10px 0; padding: 20px; background: #0D0D12; border-radius: 8px; min-width: 150px; border: 1px solid #333; }
        .metric-value { font-size: 36px; font-weight: bold; color: #8A29F0; }
        .metric-label { color: #888; font-size: 14px; margin-top: 5px; }
        .status-good { color: #34c759; }
        .status-warning { color: #ff9500; }
        .status-critical { color: #FF2E63; }
        table { width: 100%; border-collapse: collapse; margin: 20px 0; background: #0D0D12; }
        th, td { padding: 12px; text-align: left; border-bottom: 1px solid #333; }
        th { background: #1a1a24; font-weight: 600; color: #8A29F0; }
        td { color: #E0E0E0; }
            .footer { margin-top: 40px; padding: 30px; border-top: 2px solid #8A29F0; background: #0D0D12; text-align: center; color: #888; font-size: 12px; }
            .footer-brand { color: #8A29F0; font-weight: bold; font-size: 14px; margin-top: 10px; }
            .omega-footer-logo { width: 40px; height: 40px; margin: 10px auto; object-fit: contain; }
    </style>
</head>
<body>
    <div class="container">
        <div class="omega-header">
            $(if [ -n "$logo_base64" ]; then echo "<img src=\"$logo_base64\" alt=\"MacGuardian Logo\" class=\"omega-logo-img\" />"; fi)
            <div class="omega-header-content">
                <div class="omega-logo">🛡️ MacGuardian Security Report</div>
                <div class="omega-title">Security Assessment Report</div>
                <p style="color: #888; margin-top: 10px;"><strong>Generated:</strong> $date</p>
                <p style="color: #888;"><strong>System:</strong> $(sw_vers -productName) $(sw_vers -productVersion)</p>
                <div class="omega-subtitle">OMEGA TECHNOLOGIES</div>
            </div>
        </div>
        <div class="content">
        
        <div class="summary">
            <h2>Executive Summary</h2>
            <div class="metric">
                <div class="metric-value status-good">$security_score</div>
                <div class="metric-label">Security Score</div>
            </div>
            <div class="metric">
                <div class="metric-value">$total_issues</div>
                <div class="metric-label">Issues Found</div>
            </div>
            <div class="metric">
                <div class="metric-value">$fixed_issues</div>
                <div class="metric-label">Issues Fixed</div>
            </div>
            <div class="metric">
                <div class="metric-value">$scans_run</div>
                <div class="metric-label">Scans Completed</div>
            </div>
        </div>
        
        <h2>Security Status</h2>
        <table>
            <tr>
                <th>Component</th>
                <th>Status</th>
                <th>Last Check</th>
                <th>Details</th>
            </tr>
            $status_table
        </table>
        
        <h2>Recent Threats Detected</h2>
        $threats_section
        
        <h2>Recommendations</h2>
        $recommendations
        
        </div>
        <div class="footer">
            $(if [ -n "$logo_base64" ]; then echo "<img src=\"$logo_base64\" alt=\"MacGuardian Logo\" class=\"omega-footer-logo\" />"; fi)
            <div style="font-size: 18px; margin-bottom: 10px;">🛡️ MacGuardian Security Suite</div>
            <div class="footer-brand">Powered by OMEGA TECHNOLOGIES</div>
            <p style="margin-top: 10px;">Security Intelligence Platform</p>
            <p style="margin-top: 15px; font-size: 11px;">This report was automatically generated by MacGuardian Suite.</p>
            <p style="font-size: 11px;">For detailed logs, visit: $HOME/.macguardian/</p>
        </div>
    </div>
</body>
</html>
EOF
}

# Get security score
get_security_score() {
    local latest=$(ls -t "$HOME/.macguardian/hardening_assessment_"*.txt 2>/dev/null | head -1)
    if [ -n "$latest" ] && [ -f "$latest" ]; then
        grep "Hardening Score:" "$latest" 2>/dev/null | awk '{print $3}' | tr -d '%' || echo "N/A"
    else
        echo "N/A"
    fi
}

# Get total issues
get_total_issues() {
    if type get_unresolved_errors &> /dev/null; then
        { get_unresolved_errors 2>/dev/null | wc -l | tr -d ' ' || echo "0"; } | head -1
    else
        echo "0"
    fi
}

# Get fixed issues
get_fixed_issues() {
    local error_db="${ERROR_DB:-$HOME/.macguardian/errors/error_database.jsonl}"
    if [ -f "$error_db" ]; then
        { grep -c '"status": "resolved"' "$error_db" 2>/dev/null || echo "0"; } | head -1
    else
        echo "0"
    fi
}

# Get scans run
get_scans_run() {
    local log_dir="${LOG_DIR:-$HOME/.macguardian/logs}"
    if [ -d "$log_dir" ]; then
        { find "$log_dir" -name "*.log" -mtime -1 2>/dev/null | wc -l | tr -d ' ' || echo "0"; } | head -1
    else
        echo "0"
    fi
}

# Generate status table
generate_status_table() {
    local status_html=""
    
    # Check FileVault
    if fdesetup status 2>/dev/null | grep -q "On"; then
        status_html+="<tr><td>FileVault</td><td class=\"status-good\">✅ Enabled</td><td>$(date '+%Y-%m-%d')</td><td>Disk encryption active</td></tr>"
    else
        status_html+="<tr><td>FileVault</td><td class=\"status-warning\">⚠️ Disabled</td><td>$(date '+%Y-%m-%d')</td><td>Enable for data protection</td></tr>"
    fi
    
    # Check SIP
    if csrutil status 2>/dev/null | grep -q "enabled"; then
        status_html+="<tr><td>SIP</td><td class=\"status-good\">✅ Enabled</td><td>$(date '+%Y-%m-%d')</td><td>System protection active</td></tr>"
    else
        status_html+="<tr><td>SIP</td><td class=\"status-critical\">❌ Disabled</td><td>$(date '+%Y-%m-%d')</td><td>Critical: Enable immediately</td></tr>"
    fi
    
    # Check Firewall
    if /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null | grep -q "enabled"; then
        status_html+="<tr><td>Firewall</td><td class=\"status-good\">✅ Enabled</td><td>$(date '+%Y-%m-%d')</td><td>Network protection active</td></tr>"
    else
        status_html+="<tr><td>Firewall</td><td class=\"status-warning\">⚠️ Disabled</td><td>$(date '+%Y-%m-%d')</td><td>Enable for network security</td></tr>"
    fi
    
    # Check ClamAV
    if command -v clamscan &> /dev/null; then
        status_html+="<tr><td>Antivirus</td><td class=\"status-good\">✅ Installed</td><td>$(date '+%Y-%m-%d')</td><td>ClamAV active</td></tr>"
    else
        status_html+="<tr><td>Antivirus</td><td class=\"status-warning\">⚠️ Not Installed</td><td>$(date '+%Y-%m-%d')</td><td>Install ClamAV</td></tr>"
    fi
    
    # Check Time Machine
    if tmutil status 2>/dev/null | grep -q "Running = 1"; then
        status_html+="<tr><td>Time Machine</td><td class=\"status-good\">✅ Active</td><td>$(date '+%Y-%m-%d')</td><td>Backups running</td></tr>"
    else
        status_html+="<tr><td>Time Machine</td><td class=\"status-warning\">⚠️ Inactive</td><td>$(date '+%Y-%m-%d')</td><td>Enable backups</td></tr>"
    fi
    
    echo "$status_html"
}

# Generate threats section
generate_threats_section() {
    local threats_html="<p>No recent threats detected.</p>"
    
    # Check for recent threats in logs
    local log_dir="${LOG_DIR:-$HOME/.macguardian/logs}"
    local recent_threats=$(find "$log_dir" -name "*.log" -mtime -1 -exec grep -l "THREAT\|CRITICAL\|threat detected" {} \; 2>/dev/null | head -5)
    
    if [ -n "$recent_threats" ]; then
        threats_html="<ul>"
        echo "$recent_threats" | while IFS= read -r log_file; do
            local threat=$(grep -i "threat\|critical" "$log_file" 2>/dev/null | tail -1 || echo "")
            if [ -n "$threat" ]; then
                threats_html+="<li>$threat</li>"
            fi
        done
        threats_html+="</ul>"
    fi
    
    echo "$threats_html"
}

# Generate recommendations
generate_recommendations() {
    local recs_html="<ul>"
    
    # Check for common recommendations
    if ! fdesetup status 2>/dev/null | grep -q "On"; then
        recs_html+="<li><strong>Enable FileVault:</strong> Encrypt your disk for data protection</li>"
    fi
    
    if ! /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null | grep -q "enabled"; then
        recs_html+="<li><strong>Enable Firewall:</strong> Protect against network attacks</li>"
    fi
    
    if ! command -v clamscan &> /dev/null; then
        recs_html+="<li><strong>Install ClamAV:</strong> Run: brew install clamav</li>"
    fi
    
    local unresolved=$(get_total_issues)
    if [ "$unresolved" -gt 0 ]; then
        recs_html+="<li><strong>Fix $unresolved issue(s):</strong> Run Mac Remediation to auto-fix</li>"
    fi
    
    recs_html+="</ul>"
    echo "$recs_html"
}

# Send report via email
send_report_email() {
    local report_file="$1"
    local subject="MacGuardian Security Report - $(date '+%Y-%m-%d')"
    
    if [ -z "$REPORT_EMAIL" ]; then
        warning "REPORT_EMAIL not configured. Set it in config.sh or export REPORT_EMAIL"
        return 1
    fi
    
    # Try Python SMTP first (most reliable)
    if command -v python3 &> /dev/null && [ -f "$SCRIPT_DIR/send_email.py" ]; then
        if [ -n "${SMTP_USERNAME:-}" ] && [ -n "${SMTP_PASSWORD:-}" ]; then
            local html_content=$(cat "$report_file")
            local text_content="MacGuardian Security Report\n\nSee attached HTML report for full details.\n\nReport generated: $(date)\nSystem: $(hostname)"
            
            if python3 "$SCRIPT_DIR/send_email.py" "$REPORT_EMAIL" "$subject" "$text_content" --html "$html_content" --attachment "$report_file" --username "$SMTP_USERNAME" --password "$SMTP_PASSWORD" 2>/dev/null; then
                success "Report sent to $REPORT_EMAIL via SMTP"
                return 0
            fi
        fi
    fi
    
    # Fallback: Try system mail (may not work on macOS)
    if command -v mail &> /dev/null; then
        {
            echo "To: $REPORT_EMAIL"
            echo "Subject: $subject"
            echo "Content-Type: text/html"
            echo ""
            cat "$report_file"
        } | sendmail "$REPORT_EMAIL" 2>/dev/null && {
                warning "Report may have been queued (check if SMTP is configured)"
                return 0
            }
    fi
    
    warning "Email sending not available. Report saved to: $report_file"
    return 1
}

# Generate text report
generate_text_report() {
    local report_file="$1"
    local date=$(date '+%Y-%m-%d %H:%M:%S')
    
    cat > "$report_file" <<EOF
========================================
MacGuardian Security Report
Generated: $date
System: $(sw_vers -productName) $(sw_vers -productVersion)
========================================

EXECUTIVE SUMMARY
-----------------
Security Score: $(get_security_score)%
Issues Found: $(get_total_issues)
Issues Fixed: $(get_fixed_issues)
Scans Completed: $(get_scans_run)

SECURITY STATUS
---------------
FileVault: $(fdesetup status 2>/dev/null | grep -q "On" && echo "✅ Enabled" || echo "⚠️ Disabled")
SIP: $(csrutil status 2>/dev/null | grep -q "enabled" && echo "✅ Enabled" || echo "❌ Disabled")
Firewall: $(/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null | grep -q "enabled" && echo "✅ Enabled" || echo "⚠️ Disabled")
Antivirus: $(command -v clamscan &> /dev/null && echo "✅ Installed" || echo "⚠️ Not Installed")
Time Machine: $(tmutil status 2>/dev/null | grep -q "Running = 1" && echo "✅ Active" || echo "⚠️ Inactive")

RECOMMENDATIONS
---------------
$(generate_text_recommendations)

For detailed logs, visit: $HOME/.macguardian/
EOF
}

generate_text_recommendations() {
    local recs=""
    
    if ! fdesetup status 2>/dev/null | grep -q "On"; then
        recs+="• Enable FileVault for disk encryption\n"
    fi
    
    if ! /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null | grep -q "enabled"; then
        recs+="• Enable Firewall for network protection\n"
    fi
    
    local unresolved=$(get_total_issues)
    if [ "$unresolved" -gt 0 ]; then
        recs+="• Fix $unresolved unresolved issue(s) - Run: ./MacGuardianSuite/mac_remediation.sh --execute\n"
    fi
    
    echo -e "$recs"
}

# Main function
main() {
    local schedule="${1:-${REPORT_SCHEDULE:-daily}}"
    local format="${2:-${REPORT_FORMAT:-html}}"
    
    echo "${bold}📊 Generating $schedule Security Report...${normal}"
    echo "----------------------------------------"
    
    local report_file="$REPORT_DIR/security_report_${schedule}_$(date +%Y%m%d_%H%M%S).${format}"
    
    if [ "$format" = "html" ]; then
        generate_executive_summary "$report_file"
    else
        generate_text_report "$report_file"
    fi
    
    success "Report generated: $report_file"
    
    # Send email if configured
    if [ -n "$REPORT_EMAIL" ]; then
        echo ""
        send_report_email "$report_file"
    else
        info "To enable email reports, set REPORT_EMAIL in config.sh"
    fi
    
    # Also save to standard location
    cp "$report_file" "$REPORT_DIR/latest_report.${format}" 2>/dev/null || true
    
    echo ""
    echo "${green}✅ Report generation complete${normal}"
    echo "   Location: $report_file"
}

# If run directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi

