#!/bin/bash

# ===============================
# Mac Guardian Suite Configuration
# Centralized configuration file
# ===============================

# Configuration file location
CONFIG_DIR="$HOME/.macguardian"
MAIN_CONFIG="$CONFIG_DIR/config.conf"

THEME_PROFILE_DEFAULT="omega_tech_black_ops"
THEME_DIR="$CONFIG_DIR/themes/$THEME_PROFILE_DEFAULT"
THEME_PROFILE_FILE="$THEME_DIR/profile.conf"
THEME_TEMPLATE_FILE="$THEME_DIR/alert_template.html"

# Default settings
DEFAULT_ALERT_EMAIL=""  # set your own address in ~/.macguardian/config.conf
DEFAULT_MONITOR_PATHS=("$HOME/Documents" "$HOME/Desktop")
DEFAULT_SCAN_DIR="$HOME/Documents"
DEFAULT_HONEYPOT_DIR="$HOME/Documents/Passwords_DO_NOT_OPEN"
DEFAULT_LOG_DIR="$CONFIG_DIR/logs"

# Initialize configuration if it doesn't exist
init_config() {
    if [ ! -d "$CONFIG_DIR" ]; then
        mkdir -p "$CONFIG_DIR"
        mkdir -p "$DEFAULT_LOG_DIR"
    fi
    
    if [ ! -f "$MAIN_CONFIG" ]; then
        cat > "$MAIN_CONFIG" <<EOF
# Mac Guardian Suite Configuration
# Edit this file to customize settings

ALERT_EMAIL="$DEFAULT_ALERT_EMAIL"
MONITOR_PATHS=($(printf '"%s" ' "${DEFAULT_MONITOR_PATHS[@]}"))
SCAN_DIR="$DEFAULT_SCAN_DIR"
HONEYPOT_DIR="$DEFAULT_HONEYPOT_DIR"
LOG_DIR="$DEFAULT_LOG_DIR"

# Theme settings
THEME_PROFILE="omega_tech_black_ops"
THEME_SUBJECT_PREFIX="[Ω-OPS]"
THEME_HEADLINE="OMEGA TECH // BLACK-OPS ALERT"
THEME_STATUS_LINE="Automation Wing // Active Oversight"
THEME_TAGLINE="Omega Technologies // Watchdog Division"

# Notification settings
ENABLE_NOTIFICATIONS=true
NOTIFICATION_SOUND=true
NOTIFICATION_COOLDOWN=300  # Seconds between notifications (5 minutes default, prevents spam)

# Scan settings
ENABLE_CLAMAV=true
ENABLE_RKHUNTER=true
ENABLE_FULL_SCAN=false

# Watchdog settings
WATCHDOG_ENABLED=true
CHECK_INTERVAL_HOURS=24

# Report settings
GENERATE_REPORTS=true
REPORT_DIR="$CONFIG_DIR/reports"

# Parallel processing settings
ENABLE_PARALLEL=true
PARALLEL_JOBS=""  # Auto-detect if empty

# ClamAV scan settings
FAST_SCAN_DEFAULT=true
CLAMAV_MAX_FILESIZE=100M
CLAMAV_MAX_FILES=50000

# Report settings
REPORT_EMAIL=""  # Set to enable email reports
REPORT_SCHEDULE="daily"  # daily, weekly, monthly
REPORT_FORMAT="html"  # html, text, json

# Alerting settings
ALERT_EMAIL=""  # Set to enable email alerts
ALERT_ENABLED=true
ALERT_RULES_FILE="$CONFIG_DIR/alerts/rules.conf"
EOF
        echo "✅ Configuration initialized at $MAIN_CONFIG"
    fi

    mkdir -p "$THEME_DIR"

    if [ ! -f "$THEME_PROFILE_FILE" ]; then
        cat > "$THEME_PROFILE_FILE" <<'EOF'
THEME_NAME="Omega Tech Black-Ops"
THEME_ID="omega_tech_black_ops"
THEME_SUBJECT_PREFIX="[Ω-OPS]"
THEME_HEADLINE="OMEGA TECH // BLACK-OPS ALERT"
THEME_STATUS_LINE="Automation Wing // Active Oversight"
THEME_TAGLINE="Omega Technologies // Watchdog Division"
THEME_PRIMARY_COLOR="#0D0D0D"
THEME_ACCENT_PURPLE="#8C00FF"
THEME_ACCENT_RED="#FF1100"
THEME_HIGHLIGHT="#FFE600"
THEME_TEXT="#E5E5E5"
THEME_MUTED_TEXT="#666666"
EOF
    fi

    if [ ! -f "$THEME_TEMPLATE_FILE" ]; then
        cat > "$THEME_TEMPLATE_FILE" <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>{{headline}}</title>
    <style>
        body { background-color: #0D0D0D; color: #E5E5E5; font-family: 'Courier New', Menlo, monospace; margin: 0; padding: 0; }
        .container { max-width: 640px; margin: 0 auto; padding: 32px 24px; background-color: #111111; border: 1px solid #1F1F1F; }
        .headline { color: #8C00FF; text-transform: uppercase; letter-spacing: 0.15em; font-size: 20px; }
        .status { color: #FFE600; font-size: 13px; text-transform: uppercase; letter-spacing: 0.25em; margin-bottom: 24px; }
        .body { line-height: 1.6; font-size: 14px; }
        .body strong { color: #FF1100; }
        .footer { margin-top: 32px; font-size: 12px; color: #666666; letter-spacing: 0.12em; text-transform: uppercase; }
        .tagline { margin-top: 16px; font-size: 12px; color: #8C00FF; letter-spacing: 0.18em; }
    </style>
</head>
<body>
    <div class="container">
        <div class="headline">{{headline}}</div>
        <div class="status">{{status_line}}</div>
        <div class="body">{{body}}</div>
        <div class="tagline">{{tagline}}</div>
        <div class="footer">Omega Technologies &bull; Black-Ops Watchdog</div>
    </div>
</body>
</html>
EOF
    fi
}

# Load configuration
load_config() {
    if [ -f "$MAIN_CONFIG" ]; then
        source "$MAIN_CONFIG"
    else
        # Use defaults
        ALERT_EMAIL="$DEFAULT_ALERT_EMAIL"
        REPORT_EMAIL="$DEFAULT_ALERT_EMAIL"  # Use same email for reports
        MONITOR_PATHS=("${DEFAULT_MONITOR_PATHS[@]}")
        SCAN_DIR="$DEFAULT_SCAN_DIR"
        HONEYPOT_DIR="$DEFAULT_HONEYPOT_DIR"
        LOG_DIR="$DEFAULT_LOG_DIR"
        ENABLE_NOTIFICATIONS=true
        NOTIFICATION_SOUND=true
        ENABLE_CLAMAV=true
        ENABLE_RKHUNTER=true
        ENABLE_FULL_SCAN=false
        WATCHDOG_ENABLED=true
        CHECK_INTERVAL_HOURS=24
        GENERATE_REPORTS=true
        REPORT_DIR="$CONFIG_DIR/reports"
        ENABLE_PARALLEL=true
        PARALLEL_JOBS=""
        FAST_SCAN_DEFAULT=true
        CLAMAV_MAX_FILESIZE=100M
        CLAMAV_MAX_FILES=50000
    fi
    
    # Ensure REPORT_EMAIL is set (fallback to ALERT_EMAIL if not set)
    REPORT_EMAIL="${REPORT_EMAIL:-${ALERT_EMAIL:-$DEFAULT_ALERT_EMAIL}}"

    if [ -f "$THEME_PROFILE_FILE" ]; then
        # shellcheck disable=SC1090
        source "$THEME_PROFILE_FILE"
    fi

    THEME_SUBJECT_PREFIX=${THEME_SUBJECT_PREFIX:-"[Ω-OPS]"}
    THEME_HEADLINE=${THEME_HEADLINE:-"OMEGA TECH // BLACK-OPS ALERT"}
    THEME_STATUS_LINE=${THEME_STATUS_LINE:-"Automation Wing // Active Oversight"}
    THEME_TAGLINE=${THEME_TAGLINE:-"Omega Technologies // Watchdog Division"}

    # Ensure directories exist
    mkdir -p "$LOG_DIR"
    mkdir -p "${REPORT_DIR:-$CONFIG_DIR/reports}"
}

# Initialize on source
init_config
load_config

