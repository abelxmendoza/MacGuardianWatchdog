#!/bin/bash

# ===============================
# Action-Based Email Notifier
# Sends summarized emails after security actions
# ===============================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"
source "$SCRIPT_DIR/config.sh"

# Load SMTP credentials
if [ -z "${SMTP_USERNAME:-}" ] || [ -z "${SMTP_PASSWORD:-}" ]; then
    if [ -f ~/.zshrc ]; then
        eval $(grep "^export SMTP_USERNAME=" ~/.zshrc 2>/dev/null || true)
        eval $(grep "^export SMTP_PASSWORD=" ~/.zshrc 2>/dev/null || true)
    fi
fi

# Action types
ACTION_SCAN_COMPLETE="scan_complete"
ACTION_ISSUES_FOUND="issues_found"
ACTION_REMEDIATION_COMPLETE="remediation_complete"
ACTION_CRITICAL_ALERT="critical_alert"
ACTION_DAILY_SUMMARY="daily_summary"

# Send action-based email
send_action_email() {
    local action_type="$1"
    local action_data="$2"  # JSON string with action details
    
    local email="${REPORT_EMAIL:-${ALERT_EMAIL:-}}"
    if [ -z "$email" ]; then
        return 1
    fi
    
    # Generate AI summary with ML insights
    local events_file="/tmp/macguardian_events_$$.json"
    echo "$action_data" > "$events_file"
    
    # Get ML insights first
    local ml_insights=""
    local historical_file="$HOME/.macguardian/historical_data.json"
    if command -v python3 &> /dev/null && [ -f "$SCRIPT_DIR/ml_insights.py" ]; then
        ml_insights=$(python3 "$SCRIPT_DIR/ml_insights.py" "$events_file" "$historical_file" 2>/dev/null || echo "")
    fi
    
    # Generate AI summary
    local summary_output
    if command -v python3 &> /dev/null && [ -f "$SCRIPT_DIR/ai_email_summarizer.py" ]; then
        summary_output=$(python3 "$SCRIPT_DIR/ai_email_summarizer.py" "$events_file" 2>/dev/null || echo "")
    fi
    
    # Enhance summary with ML insights if available
    if [ -n "$ml_insights" ]; then
        local risk_score=$(echo "$ml_insights" | sed -n '/ML_INSIGHTS_START/,/ML_INSIGHTS_END/p' | grep -o '"risk_score": [0-9.]*' | cut -d' ' -f2)
        if [ -n "$risk_score" ]; then
            # Add risk score to text report
            text_report=$(echo "$summary_output" | sed -n '/TEXT_REPORT_START/,/TEXT_REPORT_END/p' | sed '1d;$d')
            text_report="📊 RISK SCORE: $risk_score/100\n\n$text_report"
            summary_output="TEXT_REPORT_START\n$text_report\nTEXT_REPORT_END\n$(echo "$summary_output" | sed -n '/HTML_REPORT_START/,/HTML_REPORT_END/p')"
        fi
    fi
    
    # Extract reports from output
    local text_report=$(echo "$summary_output" | sed -n '/TEXT_REPORT_START/,/TEXT_REPORT_END/p' | sed '1d;$d')
    local html_report=$(echo "$summary_output" | sed -n '/HTML_REPORT_START/,/HTML_REPORT_END/p' | sed '1d;$d')
    
    # Generate subject based on action
    local subject
    case "$action_type" in
        "$ACTION_SCAN_COMPLETE")
            subject="✅ MacGuardian: Security Scan Complete"
            ;;
        "$ACTION_ISSUES_FOUND")
            subject="⚠️ MacGuardian: Security Issues Detected"
            ;;
        "$ACTION_REMEDIATION_COMPLETE")
            subject="🔧 MacGuardian: Remediation Complete"
            ;;
        "$ACTION_CRITICAL_ALERT")
            subject="🚨 MacGuardian: CRITICAL Security Alert"
            ;;
        "$ACTION_DAILY_SUMMARY")
            subject="📊 MacGuardian: Daily Security Summary"
            ;;
        *)
            subject="📧 MacGuardian: Security Update"
            ;;
    esac
    
    # Use text report if HTML not available
    local body="${text_report:-Security action completed. See details in attached report.}"
    
    # Send email
    if command -v python3 &> /dev/null && [ -f "$SCRIPT_DIR/send_email.py" ]; then
        if [ -n "${SMTP_USERNAME:-}" ] && [ -n "${SMTP_PASSWORD:-}" ]; then
            if [ -n "$html_report" ]; then
                python3 "$SCRIPT_DIR/send_email.py" "$email" "$subject" "$body" --html "$html_report" --username "$SMTP_USERNAME" --password "$SMTP_PASSWORD" 2>/dev/null && {
                    log_message "INFO" "Action email sent: $action_type to $email"
                    rm -f "$events_file"
                    return 0
                }
            else
                python3 "$SCRIPT_DIR/send_email.py" "$email" "$subject" "$body" --username "$SMTP_USERNAME" --password "$SMTP_PASSWORD" 2>/dev/null && {
                    log_message "INFO" "Action email sent: $action_type to $email"
                    rm -f "$events_file"
                    return 0
                }
            fi
        fi
    fi
    
    rm -f "$events_file"
    return 1
}

# Collect events from scan results
collect_scan_events() {
    local scan_type="$1"
    local results_file="${2:-}"
    
    local events="[]"
    
    # Parse results and create event objects
    if [ -f "$results_file" ]; then
        local issues=$( (grep -c "⚠️\|❌\|🚨" "$results_file" 2>/dev/null || echo "0") | head -1)
        local warnings=$( (grep -c "⚠️" "$results_file" 2>/dev/null || echo "0") | head -1)
        local critical=$( (grep -c "🚨\|CRITICAL" "$results_file" 2>/dev/null || echo "0") | head -1)
        
        # Create JSON events array
        events=$(cat <<EOF
[
  {
    "category": "scan",
    "severity": "$([ "$critical" -gt 0 ] && echo "critical" || [ "$issues" -gt 0 ] && echo "high" || echo "info")",
    "title": "$scan_type scan completed",
    "description": "Found $issues issue(s), $critical critical",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  }
]
EOF
)
    fi
    
    echo "$events"
}

# Main function
main() {
    local action_type="${1:-}"
    local action_data="${2:-[]}"
    
    if [ -z "$action_type" ]; then
        echo "Usage: action_email_notifier.sh <action_type> [action_data_json]"
        exit 1
    fi
    
    send_action_email "$action_type" "$action_data"
}

# If run directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi

