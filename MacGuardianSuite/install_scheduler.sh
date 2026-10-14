#!/bin/bash

# ===============================
# Mac Guardian Scheduler Installer
# Sets up automated daily/weekly runs:
#   com.macguardian.daily   - file integrity check (mac_watchdog.sh), 2:00 AM daily
#   com.macguardian.weekly  - full check (mac_guardian.sh), 3:00 AM Sundays
#   com.macguardian.reports - security report (scheduled_reports.sh), 9:00 AM daily
#
# Usage: install_scheduler.sh                 install all three jobs
#        install_scheduler.sh --jobs reports  install only the listed jobs
#                                             (daily, weekly, reports; comma-separated)
#        install_scheduler.sh --refresh       update only the jobs already installed
#        install_scheduler.sh --uninstall     remove all three
# ===============================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
LOG_DIR="$HOME/.macguardian/logs"
# macOS privacy controls stop background jobs from reading Desktop, Documents
# and Downloads, so jobs run a private copy of the scripts from here (the same
# place install_monitor_daemon.sh uses).
RUNTIME_DIR="$HOME/Library/Application Support/MacGuardian"
USER_DOMAIN="gui/$(id -u)"
LABELS=(com.macguardian.daily com.macguardian.weekly com.macguardian.reports)

# write_plist LABEL "SCHEDULE_XML" SCRIPT [ARGS...]
write_plist() {
    local label="$1" schedule="$2" script="$3"
    shift 3
    local args=""
    for a in "$@"; do args+="        <string>$a</string>"$'\n'; done
    local plist="$LAUNCH_AGENTS_DIR/$label.plist"
    cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$label</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$RUNTIME_DIR/$script</string>
$args    </array>
    <key>StartCalendarInterval</key>
    <dict>
$schedule
    </dict>
    <key>RunAtLoad</key>
    <false/>
    <key>StandardOutPath</key>
    <string>$LOG_DIR/$label.log</string>
    <key>StandardErrorPath</key>
    <string>$LOG_DIR/$label.error.log</string>
</dict>
</plist>
EOF
    chmod 644 "$plist"
}

load_job() {
    local label="$1" plist="$LAUNCH_AGENTS_DIR/$1.plist"
    launchctl bootout "$USER_DOMAIN/$label" 2>/dev/null || true
    if ! launchctl bootstrap "$USER_DOMAIN" "$plist" 2>/dev/null; then
        launchctl load "$plist"
    fi
}

# wants JOB: true if JOB (daily|weekly|reports) is in the selected set
wants() { [[ ",$SELECTED," == *",$1,"* ]]; }

install_scheduler() {
    echo "${bold}📅 Installing Mac Guardian Scheduler...${normal}"
    echo ""
    if [ -z "$SELECTED" ]; then
        info "No scheduled jobs to install"
        return 0
    fi

    mkdir -p "$LAUNCH_AGENTS_DIR" "$LOG_DIR" "$RUNTIME_DIR"
    /usr/bin/ditto "$SCRIPT_DIR" "$RUNTIME_DIR"
    success "Installed job runtime: $RUNTIME_DIR"

    wants daily && write_plist com.macguardian.daily \
        "        <key>Hour</key><integer>2</integer>
        <key>Minute</key><integer>0</integer>" \
        mac_watchdog.sh -q
    wants weekly && write_plist com.macguardian.weekly \
        "        <key>Weekday</key><integer>0</integer>
        <key>Hour</key><integer>3</integer>
        <key>Minute</key><integer>0</integer>" \
        mac_guardian.sh -y --report
    wants reports && write_plist com.macguardian.reports \
        "        <key>Hour</key><integer>9</integer>
        <key>Minute</key><integer>0</integer>" \
        scheduled_reports.sh daily

    for job in daily weekly reports; do
        wants "$job" && load_job "com.macguardian.$job"
    done

    success "Scheduler installed successfully!"
    echo ""
    wants daily && info "File integrity check: 2:00 AM every day"
    wants weekly && info "Full security check:  3:00 AM every Sunday"
    wants reports && info "Security report:      9:00 AM every day"
    info "Logs: $LOG_DIR"
    echo ""
    echo "To uninstall, run: $0 --uninstall"
}

uninstall_scheduler() {
    echo "${bold}🗑️  Uninstalling Mac Guardian Scheduler...${normal}"
    for label in "${LABELS[@]}"; do
        local plist="$LAUNCH_AGENTS_DIR/$label.plist"
        launchctl bootout "$USER_DOMAIN/$label" 2>/dev/null || launchctl unload "$plist" 2>/dev/null || true
        if [ -f "$plist" ]; then
            rm "$plist"
            success "Removed $label"
        fi
    done
    success "Scheduler uninstalled"
}

SELECTED="daily,weekly,reports"
case "${1:-}" in
    --uninstall) uninstall_scheduler; exit 0 ;;
    --jobs) SELECTED="${2:-}" ;;
    --refresh)
        SELECTED=""
        for job in daily weekly reports; do
            [ -f "$LAUNCH_AGENTS_DIR/com.macguardian.$job.plist" ] && SELECTED="${SELECTED:+$SELECTED,}$job"
        done ;;
esac
install_scheduler
