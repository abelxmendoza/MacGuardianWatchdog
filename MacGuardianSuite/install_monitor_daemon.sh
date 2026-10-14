#!/bin/bash

# ===============================
# MacGuardian Monitor Daemon Installer
# Installs the real-time monitoring daemon as a LaunchAgent
# ===============================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh" 2>/dev/null || true

LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
INSTALL_ROOT="$HOME/Library/Application Support/MacGuardian"
# Try new enhanced monitor first, fallback to original
MONITOR_SOURCE="$SCRIPT_DIR/daemons/mg_monitor.sh"
MONITOR_RELATIVE_PATH="daemons/mg_monitor.sh"
if [ ! -f "$MONITOR_SOURCE" ]; then
    MONITOR_SOURCE="$SCRIPT_DIR/daemons/macguardian_monitor.sh"
    MONITOR_RELATIVE_PATH="daemons/macguardian_monitor.sh"
fi
MONITOR_SCRIPT="$INSTALL_ROOT/$MONITOR_RELATIVE_PATH"
PLIST_TEMPLATE="$SCRIPT_DIR/launchd/com.macguardian.monitor.plist"
PLIST_FILE="$LAUNCH_AGENTS_DIR/com.macguardian.monitor.plist"
LOG_DIR="$HOME/.macguardian/logs"

# Install function
install_monitor() {
    echo "${bold}📅 Installing MacGuardian Monitor Daemon...${normal}"
    echo ""
    
    # Verify monitor script exists
    if [ ! -f "$MONITOR_SOURCE" ]; then
        error_exit "Monitor script not found: $MONITOR_SOURCE"
    fi
    
    # Create directories
    mkdir -p "$LAUNCH_AGENTS_DIR" "$LOG_DIR" "$(dirname "$INSTALL_ROOT")"

    # LaunchAgents cannot reliably execute project files from Desktop because
    # of macOS privacy controls. Install a private runtime copy in Application
    # Support and point launchd there instead.
    /usr/bin/ditto "$SCRIPT_DIR" "$INSTALL_ROOT"
    chmod +x "$MONITOR_SCRIPT"
    success "Installed monitor runtime: $INSTALL_ROOT"
    
    # Create plist from template
    if [ ! -f "$PLIST_TEMPLATE" ]; then
        error_exit "Plist template not found: $PLIST_TEMPLATE"
    fi
    
    # Replace placeholders in plist template
    sed "s|PLACEHOLDER_SCRIPT_PATH|$MONITOR_SCRIPT|g; s|PLACEHOLDER_LOG_PATH|$LOG_DIR|g" "$PLIST_TEMPLATE" > "$PLIST_FILE"
    
    chmod 644 "$PLIST_FILE"
    success "Created LaunchAgent plist: $PLIST_FILE"
    
    local user_domain="gui/$(id -u)"
    launchctl bootout "$user_domain/com.macguardian.monitor" 2>/dev/null || true
    rm -f "$HOME/.macguardian/.monitor.pid"

    # bootout returns before the old instance is fully gone, so retry briefly.
    local loaded=false
    for _ in 1 2 3 4 5; do
        if launchctl bootstrap "$user_domain" "$PLIST_FILE" 2>/dev/null; then loaded=true; break; fi
        sleep 1
    done
    if [ "$loaded" != true ]; then
        # `load` remains necessary on some macOS versions/configurations.
        launchctl load "$PLIST_FILE"
    fi
    
    success "Monitor daemon installed successfully!"
    echo ""
    info "Monitor daemon will start automatically on login"
    info "Event directory: $HOME/.macguardian/events"
    info "Log directory: $LOG_DIR"
    echo ""
    info "To check status: launchctl print $user_domain/com.macguardian.monitor"
    info "To stop: launchctl bootout $user_domain/com.macguardian.monitor"
    info "To start: launchctl bootstrap $user_domain $PLIST_FILE"
    info "To uninstall: $0 --uninstall"
    echo ""
}

# Uninstall function
uninstall_monitor() {
    echo "${bold}🗑️  Uninstalling MacGuardian Monitor Daemon...${normal}"
    echo ""
    
    if [ -f "$PLIST_FILE" ]; then
        launchctl unload "$PLIST_FILE" 2>/dev/null || true
        rm -f "$PLIST_FILE"
        success "Removed LaunchAgent plist"
    fi
    
    # Optionally remove event files (ask first)
    if [ -d "$HOME/.macguardian/events" ]; then
        read -p "Remove event files? (y/N): " remove_events
        if [[ "$remove_events" =~ ^[Yy]$ ]]; then
            rm -rf "$HOME/.macguardian/events"
            success "Removed event files"
        fi
    fi
    
    echo ""
    success "Monitor daemon uninstalled successfully!"
}

# Main execution
if [ "${1:-}" = "--uninstall" ]; then
    uninstall_monitor
else
    install_monitor
fi
