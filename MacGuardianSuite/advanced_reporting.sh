#!/bin/bash

# ===============================
# Advanced Reporting System
# Custom templates, comparisons, PDF exports
# ===============================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"
source "$SCRIPT_DIR/config.sh"

REPORT_DIR="${REPORT_DIR:-$HOME/.macguardian/reports}"
TEMPLATE_DIR="${TEMPLATE_DIR:-$HOME/.macguardian/reports/templates}"
mkdir -p "$REPORT_DIR" "$TEMPLATE_DIR"

# Generate comparison report (week-over-week)
generate_comparison_report() {
    local current_report="$1"
    local previous_report="${2:-}"
    local output_file="${3:-$REPORT_DIR/comparison_$(date +%Y%m%d).html}"
    
    if [ -z "$previous_report" ]; then
        # Find most recent report
        previous_report=$(ls -t "$REPORT_DIR"/*.html 2>/dev/null | head -2 | tail -1)
    fi
    
    if [ ! -f "$previous_report" ]; then
        warning "No previous report found for comparison"
        return 1
    fi
    
    # Extract key metrics (simplified - would need proper parsing)
    local current_issues=$(grep -o "Issues Found: [0-9]*" "$current_report" 2>/dev/null | grep -o "[0-9]*" | head -1 || echo "0")
    local previous_issues=$(grep -o "Issues Found: [0-9]*" "$previous_report" 2>/dev/null | grep -o "[0-9]*" | head -1 || echo "0")
    
    local change=$((current_issues - previous_issues))
    local change_percent=0
    if [ "$previous_issues" -gt 0 ]; then
        change_percent=$((change * 100 / previous_issues))
    fi
    
    # Generate comparison HTML
    cat > "$output_file" <<EOF
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Security Report Comparison</title>
    <style>
        body { font-family: -apple-system, sans-serif; padding: 20px; }
        .comparison { display: flex; gap: 20px; margin: 20px 0; }
        .metric { flex: 1; padding: 15px; background: #f5f5f5; border-radius: 8px; }
        .improved { color: #28a745; }
        .worsened { color: #dc3545; }
        .stable { color: #ffc107; }
    </style>
</head>
<body>
    <h1>📊 Security Report Comparison</h1>
    <p>Generated: $(date '+%Y-%m-%d %H:%M:%S')</p>
    
    <div class="comparison">
        <div class="metric">
            <h3>Current Report</h3>
            <p>Issues: <strong>$current_issues</strong></p>
            <p>Date: $(date '+%Y-%m-%d')</p>
        </div>
        <div class="metric">
            <h3>Previous Report</h3>
            <p>Issues: <strong>$previous_issues</strong></p>
            <p>Date: $(basename "$previous_report" | cut -d'_' -f2-3 | sed 's/.html//')</p>
        </div>
        <div class="metric">
            <h3>Change</h3>
            <p>Difference: <strong class="$([ $change -lt 0 ] && echo 'improved' || [ $change -gt 0 ] && echo 'worsened' || echo 'stable')">$change</strong></p>
            <p>Change: <strong>${change_percent}%</strong></p>
        </div>
    </div>
    
    <h2>Trend Analysis</h2>
    <p>$([ $change -lt 0 ] && echo "✅ Security improved!" || [ $change -gt 0 ] && echo "⚠️ Security issues increased." || echo "📊 Security status stable.")</p>
</body>
</html>
EOF
    
    success "Comparison report generated: $output_file"
    echo "$output_file"
}

# Export to PDF (requires wkhtmltopdf or similar)
export_to_pdf() {
    local html_file="$1"
    local pdf_file="${2:-${html_file%.html}.pdf}"
    
    # Try different PDF conversion tools
    if command -v wkhtmltopdf &> /dev/null; then
        wkhtmltopdf "$html_file" "$pdf_file" 2>/dev/null && {
            success "PDF exported: $pdf_file"
            return 0
        }
    fi
    
    # Fallback: Use macOS built-in (if available)
    if command -v cupsfilter &> /dev/null; then
        cupsfilter "$html_file" > "$pdf_file" 2>/dev/null && {
            success "PDF exported: $pdf_file"
            return 0
        }
    fi
    
    # Last resort: Use Python if available
    if command -v python3 &> /dev/null; then
        python3 <<PYTHON
import sys
try:
    from weasyprint import HTML
    HTML(filename='$html_file').write_pdf('$pdf_file')
    print("PDF exported successfully")
    sys.exit(0)
except ImportError:
    print("Install weasyprint: pip3 install weasyprint")
    sys.exit(1)
except Exception as e:
    print(f"Error: {e}")
    sys.exit(1)
PYTHON
        if [ $? -eq 0 ]; then
            success "PDF exported: $pdf_file"
            return 0
        fi
    fi
    
    warning "PDF export not available. Install: brew install wkhtmltopdf or pip3 install weasyprint"
    return 1
}

# Generate custom template report
generate_custom_report() {
    local template_name="${1:-default}"
    local template_file="$TEMPLATE_DIR/${template_name}.html"
    local output_file="$REPORT_DIR/custom_${template_name}_$(date +%Y%m%d_%H%M%S).html"
    
    if [ ! -f "$template_file" ]; then
        # Create default template
        create_default_template "$template_file"
    fi
    
    # Load template and replace placeholders
    local report_content=$(cat "$template_file")
    
    # Replace placeholders with actual data
    report_content=$(echo "$report_content" | sed "s|{{DATE}}|$(date '+%Y-%m-%d %H:%M:%S')|g")
    report_content=$(echo "$report_content" | sed "s|{{HOSTNAME}}|$(hostname)|g")
    report_content=$(echo "$report_content" | sed "s|{{USER}}|$(whoami)|g")
    
    # Get security metrics
    local security_score=$(get_security_score 2>/dev/null || echo "N/A")
    local total_issues=$(get_total_issues 2>/dev/null || echo "0")
    
    report_content=$(echo "$report_content" | sed "s|{{SECURITY_SCORE}}|$security_score|g")
    report_content=$(echo "$report_content" | sed "s|{{TOTAL_ISSUES}}|$total_issues|g")
    
    echo "$report_content" > "$output_file"
    success "Custom report generated: $output_file"
    echo "$output_file"
}

# Create default template
create_default_template() {
    local template_file="$1"
    
    cat > "$template_file" <<'EOF'
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>MacGuardian Security Report - {{DATE}}</title>
    <style>
        body { font-family: -apple-system, sans-serif; padding: 20px; }
        .header { background: #007aff; color: white; padding: 20px; border-radius: 8px; }
        .metric { display: inline-block; margin: 10px; padding: 15px; background: #f5f5f5; border-radius: 5px; }
    </style>
</head>
<body>
    <div class="header">
        <h1>🛡️ MacGuardian Security Report</h1>
        <p>Generated: {{DATE}}</p>
        <p>System: {{HOSTNAME}} | User: {{USER}}</p>
    </div>
    
    <h2>Security Metrics</h2>
    <div class="metric">
        <strong>Security Score:</strong> {{SECURITY_SCORE}}%
    </div>
    <div class="metric">
        <strong>Total Issues:</strong> {{TOTAL_ISSUES}}
    </div>
</body>
</html>
EOF
    
    success "Default template created: $template_file"
}

# Generate executive summary
generate_executive_summary() {
    local output_file="${1:-$REPORT_DIR/executive_summary_$(date +%Y%m%d).txt}"
    
    local security_score=$(get_security_score 2>/dev/null || echo "N/A")
    local total_issues=$(get_total_issues 2>/dev/null || echo "0")
    local fixed_issues=$(get_fixed_issues 2>/dev/null || echo "0")
    
    cat > "$output_file" <<EOF
========================================
EXECUTIVE SECURITY SUMMARY
Generated: $(date '+%Y-%m-%d %H:%M:%S')
========================================

SECURITY POSTURE
----------------
Security Score: $security_score%
Total Issues: $total_issues
Issues Fixed: $fixed_issues

KEY FINDINGS
------------
$(generate_key_findings)

RECOMMENDATIONS
---------------
$(generate_recommendations)

NEXT STEPS
----------
1. Review detailed report: $REPORT_DIR
2. Address critical issues immediately
3. Schedule follow-up assessment

========================================
EOF
    
    success "Executive summary generated: $output_file"
    echo "$output_file"
}

# Helper functions
get_security_score() {
    # Calculate from hardening assessment if available
    if [ -f "$HOME/.macguardian/hardening_score.txt" ]; then
        cat "$HOME/.macguardian/hardening_score.txt" 2>/dev/null || echo "N/A"
    else
        echo "N/A"
    fi
}

get_total_issues() {
    # Count from error database
    if [ -f "$HOME/.macguardian/errors.jsonl" ]; then
        { grep -c '"status": "unresolved"' "$HOME/.macguardian/errors.jsonl" 2>/dev/null || echo "0"; } | head -1
    else
        echo "0"
    fi
}

get_fixed_issues() {
    # Count resolved issues
    if [ -f "$HOME/.macguardian/errors.jsonl" ]; then
        { grep -c '"status": "resolved"' "$HOME/.macguardian/errors.jsonl" 2>/dev/null || echo "0"; } | head -1
    else
        echo "0"
    fi
}

generate_key_findings() {
    echo "• Review security scan results for details"
    echo "• Check hardening assessment for improvements"
    echo "• Monitor error database for recurring issues"
}

generate_recommendations() {
    echo "• Run full security suite weekly"
    echo "• Enable automated scheduling"
    echo "• Review and fix critical issues promptly"
    echo "• Keep system and tools updated"
}

# Main function
main() {
    case "${1:-}" in
        compare)
            generate_comparison_report "$2" "${3:-}" "${4:-}"
            ;;
        pdf)
            export_to_pdf "$2" "${3:-}"
            ;;
        custom)
            generate_custom_report "$2"
            ;;
        executive)
            generate_executive_summary "${2:-}"
            ;;
        template)
            create_default_template "${2:-$TEMPLATE_DIR/default.html}"
            ;;
        *)
            echo "Usage: advanced_reporting.sh [compare|pdf|custom|executive|template] [args...]"
            ;;
    esac
}

# If run directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi

