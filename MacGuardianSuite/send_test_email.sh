#!/bin/bash

# Send test email with Omega Technologies branded report

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

REPORT_EMAIL="${REPORT_EMAIL:-$(sed -n 's/^REPORT_EMAIL="\([^"]*\)".*/\1/p' "$HOME/.macguardian/config.conf" 2>/dev/null | tail -1)}"
if [ -z "$REPORT_EMAIL" ]; then
    echo "No report address set. Add REPORT_EMAIL=\"you@example.com\" to ~/.macguardian/config.conf." >&2
    exit 1
fi
REPORT_DIR="${REPORT_DIR:-$HOME/.macguardian/reports}"
mkdir -p "$REPORT_DIR"

echo "🛡️ Generating Omega Technologies Branded Security Report..."
echo "=============================================================="
echo ""

# Generate a fresh report
report_file="$REPORT_DIR/test_omega_design_$(date +%Y%m%d_%H%M%S).html"

# Generate the report using scheduled_reports.sh function
if [ -f "$SCRIPT_DIR/scheduled_reports.sh" ]; then
    source "$SCRIPT_DIR/scheduled_reports.sh"
    main daily html
    # Get the latest report
    report_file=$(ls -t "$REPORT_DIR"/security_report_*.html 2>/dev/null | head -1)
else
    # Fallback: create a simple test report
    cat > "$report_file" <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>🛡️ MacGuardian Security Report</title>
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
        .footer { margin-top: 40px; padding: 30px; border-top: 2px solid #8A29F0; background: #0D0D12; text-align: center; color: #888; font-size: 12px; }
        .footer-brand { color: #8A29F0; font-weight: bold; font-size: 14px; margin-top: 10px; }
    </style>
</head>
<body>
    <div class="container">
        <div class="omega-header">
            <div class="omega-header-content">
                <div class="omega-logo">🛡️ MacGuardian Security Report</div>
                <div class="omega-title">Omega Technologies Design Preview</div>
                <p style="color: #888; margin-top: 10px;"><strong>Generated:</strong> $(date '+%Y-%m-%d %H:%M:%S')</p>
                <p style="color: #888;"><strong>System:</strong> $(sw_vers -productName) $(sw_vers -productVersion)</p>
                <div class="omega-subtitle">OMEGA TECHNOLOGIES</div>
            </div>
        </div>
        <div class="content">
            <h1>Security Assessment Summary</h1>
            
            <div class="summary">
                <h2>Executive Summary</h2>
                <div class="metric">
                    <div class="metric-value">92</div>
                    <div class="metric-label">Security Score</div>
                </div>
                <div class="metric">
                    <div class="metric-value">3</div>
                    <div class="metric-label">Issues Found</div>
                </div>
                <div class="metric">
                    <div class="metric-value">2</div>
                    <div class="metric-label">Issues Fixed</div>
                </div>
                <div class="metric">
                    <div class="metric-value">15</div>
                    <div class="metric-label">Scans Completed</div>
                </div>
            </div>
            
            <h2>New Features</h2>
            <ul style="line-height: 1.8;">
                <li>✅ Omega Technologies Branding</li>
                <li>✅ MacGuardian Logo Integration</li>
                <li>✅ Dark Theme Styling</li>
                <li>✅ Terminal Launcher for Rootkit Scans</li>
                <li>✅ Enhanced Security Dashboards</li>
                <li>✅ Blue Team Monitoring</li>
                <li>✅ Security Audit Dashboard</li>
                <li>✅ Remediation Center</li>
                <li>✅ Omega Guardian Alert System</li>
            </ul>
            
            <h2>Design Elements</h2>
            <p>This report showcases the new Omega Technologies branding with:</p>
            <ul style="line-height: 1.8;">
                <li><strong style="color: #8A29F0;">Omega Purple (#8A29F0)</strong> - Primary accent color</li>
                <li><strong style="color: #0D0D12;">Jet Black Background</strong> - Professional dark theme</li>
                <li><strong style="color: #FF2E63;">Critical Red-Pink</strong> - For high-severity alerts</li>
                <li>Gradient headers and purple accent borders</li>
                <li>MacGuardian logo integration</li>
            </ul>
        </div>
        <div class="footer">
            <div style="font-size: 18px; margin-bottom: 10px;">🛡️ MacGuardian Security Suite</div>
            <div class="footer-brand">Powered by OMEGA TECHNOLOGIES</div>
            <p style="margin-top: 10px;">Security Intelligence Platform</p>
            <p style="margin-top: 15px; font-size: 11px;">This is a test email showcasing the new Omega Technologies design.</p>
        </div>
    </div>
</body>
</html>
EOF
fi

if [ ! -f "$report_file" ] || [ ! -s "$report_file" ]; then
    error "Failed to generate report"
    exit 1
fi

echo "✅ Report generated: $report_file"
echo ""

# Create email body
subject="🛡️ MacGuardian Security Report - Omega Technologies Design Preview"
text_body="MacGuardian Security Report with Omega Technologies Branding

This email showcases the new design featuring:
- Omega Technologies branding
- MacGuardian logo integration  
- Dark theme styling
- Professional security report layout

See attached HTML report for full design preview.

Generated: $(date)
System: $(hostname)

Powered by OMEGA TECHNOLOGIES"

echo "📧 Sending email to: $REPORT_EMAIL"
echo ""

# Send email using Python SMTP
if command -v python3 &> /dev/null && [ -f "$SCRIPT_DIR/send_email.py" ]; then
    if [ -n "${SMTP_USERNAME:-}" ] && [ -n "${SMTP_PASSWORD:-}" ]; then
        # Convert HTML to email-compatible format with inline styles
        email_html_file="${report_file}.email.html"
        
        if [ -f "$SCRIPT_DIR/create_email_html.py" ]; then
            python3 "$SCRIPT_DIR/create_email_html.py" "$report_file" > "$email_html_file"
        elif [ -f "$SCRIPT_DIR/convert_html_for_email.py" ]; then
            python3 "$SCRIPT_DIR/convert_html_for_email.py" "$report_file" > "$email_html_file"
        else
            # Fallback: use original HTML
            cp "$report_file" "$email_html_file"
        fi
        
        # Read HTML content and pass via stdin or use file
        # Create a Python script that reads the file
        python3 <<PYTHON_SCRIPT
import sys
sys.path.insert(0, "$SCRIPT_DIR")
from send_email import send_email

# Read HTML content
with open("$email_html_file", "r") as f:
    html_content = f.read()

# Send email
smtp_config = {
    "username": "${SMTP_USERNAME}",
    "password": "${SMTP_PASSWORD}",
    "smtp_server": "smtp.gmail.com",
    "smtp_port": 587,
    "use_tls": True
}

success = send_email(
    "$REPORT_EMAIL",
    "$subject",
    """$text_body""",
    html_body=html_content,
    attachment_path="$report_file",
    smtp_config=smtp_config
)

sys.exit(0 if success else 1)
PYTHON_SCRIPT
        
        # Clean up temp file
        rm -f "$email_html_file"

        if [ $? -eq 0 ]; then
            success "✅ Email sent successfully to $REPORT_EMAIL"
            echo ""
            echo "📋 Email Details:"
            echo "   To: $REPORT_EMAIL"
            echo "   Subject: $subject"
            echo "   Attachment: $(basename "$report_file")"
            echo ""
            echo "💡 Check your inbox to see the new Omega Technologies design!"
            exit 0
        else
            error "❌ Failed to send email via SMTP"
            echo ""
            echo "💡 Troubleshooting:"
            echo "   1. Check SMTP_USERNAME and SMTP_PASSWORD are set"
            echo "   2. For Gmail, use an App Password (not your regular password)"
            echo "   3. Ensure 2FA is enabled on your Google account"
            exit 1
        fi
    else
        warning "⚠️  SMTP credentials not configured"
        echo ""
        echo "To send emails, set:"
        echo "  export SMTP_USERNAME='your-email@gmail.com'"
        echo "  export SMTP_PASSWORD='your-app-password'"
        echo ""
        echo "Report saved to: $report_file"
        echo "You can open it manually to see the design:"
        echo "  open '$report_file'"
        exit 1
    fi
else
    error "❌ Python3 or send_email.py not found"
    echo ""
    echo "Report saved to: $report_file"
    echo "You can open it manually to see the design:"
    echo "  open '$report_file'"
    exit 1
fi

