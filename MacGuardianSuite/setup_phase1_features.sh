#!/bin/bash

# ===============================
# Phase 1 Features Setup
# Sets up scheduled reports and advanced alerting
# ===============================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"
source "$SCRIPT_DIR/config.sh"

echo "${bold}🚀 Setting Up Phase 1 Features${normal}"
echo "=========================================="
echo ""

# 1. Setup Scheduled Reports
echo "${bold}📊 Setting Up Scheduled Reports...${normal}"
echo "----------------------------------------"

# Add to launchd for daily reports
if [ -z "${REPORT_EMAIL:-}" ]; then
    read -p "Enter email for reports (or press Enter to skip): " email
    if [ -n "$email" ]; then
        export REPORT_EMAIL="$email"
        # Update config
        if [ -f "$MAIN_CONFIG" ]; then
            sed -i.bak "s|REPORT_EMAIL=\"\"|REPORT_EMAIL=\"$email\"|" "$MAIN_CONFIG" 2>/dev/null || true
        fi
    fi
fi

# Daily reports run from launchd via the shared scheduler, which installs a
# private copy of the scripts that background jobs are allowed to run.
if "$SCRIPT_DIR/install_scheduler.sh" --jobs reports >/dev/null; then
    success "✅ Daily reports scheduled (9:00 AM daily)"
else
    warning "⚠️  Could not install the scheduler (run install_scheduler.sh manually)"
fi

echo ""

# 2. Setup Advanced Alerting
echo "${bold}🔔 Setting Up Advanced Alerting...${normal}"
echo "----------------------------------------"

# Initialize alert rules (with timeout to prevent hanging)
if [ -f "$SCRIPT_DIR/advanced_alerting.sh" ]; then
    # Set default alert rules file path
    ALERT_RULES_FILE="${ALERT_RULES_FILE:-$HOME/.macguardian/alerts/rules.conf}"
    
    # Initialize rules without processing (just create the file)
    source "$SCRIPT_DIR/advanced_alerting.sh" 2>/dev/null || true
    if type init_default_rules &> /dev/null; then
        init_default_rules 2>/dev/null || true
    fi
    success "✅ Alert rules initialized"
    
    # Show configured rules
    echo ""
    echo "Configured alert rules:"
    if [ -f "$ALERT_RULES_FILE" ]; then
        # Just show a summary instead of processing all rules
        rule_count=$(grep -v '^#' "$ALERT_RULES_FILE" | grep -v '^$' | wc -l | tr -d ' ')
        echo "  ✅ $rule_count alert rule(s) configured"
        echo "  📄 Rules file: $ALERT_RULES_FILE"
        echo "  💡 Run 'advanced_alerting.sh list' to view all rules"
    else
        echo "  (Rules file not found)"
    fi
else
    warning "⚠️  Advanced alerting script not found"
fi

# Add alert processing to main suite
echo ""
echo "${bold}📋 Integration Complete${normal}"
echo "----------------------------------------"
echo ""
echo "✅ Scheduled Reports:"
echo "   • Daily reports at 9:00 AM"
echo "   • Reports saved to: $REPORT_DIR"
if [ -n "${REPORT_EMAIL:-}" ]; then
    echo "   • Email reports to: $REPORT_EMAIL"
fi
echo ""
echo "✅ Advanced Alerting:"
echo "   • Custom alert rules configured"
echo "   • Alert history: $HOME/.macguardian/alerts/history.log"
echo "   • Rules file: $ALERT_RULES_FILE"
echo ""
echo "${green}🎉 Phase 1 features are now active!${normal}"
echo ""
echo "To test:"
echo "  • Generate report: ./MacGuardianSuite/scheduled_reports.sh daily"
echo "  • Process alerts: ./MacGuardianSuite/advanced_alerting.sh process"
echo "  • View rules: ./MacGuardianSuite/advanced_alerting.sh list"

