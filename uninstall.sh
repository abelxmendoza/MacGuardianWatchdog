#!/bin/bash
# ===============================
# Remove MacGuardian from this Mac.
#
# Removes the app, every MacGuardian background job and the private copy of
# the scripts those jobs run. Your scan results, reports and logs in
# ~/.macguardian are kept unless you pass --all (or say yes when asked).
# The project folder itself is left alone; delete it yourself if you like.
#
#     ./uninstall.sh          remove the app and background jobs
#     ./uninstall.sh --all    also delete ~/.macguardian (results, reports, logs)
# ===============================

set -uo pipefail

APP_PATH="/Applications/MacGuardian Suite.app"
RUNTIME_DIR="$HOME/Library/Application Support/MacGuardian"
DATA_DIR="$HOME/.macguardian"
USER_DOMAIN="gui/$(id -u)"

REMOVE_DATA=false
[ "${1:-}" = "--all" ] && REMOVE_DATA=true

echo "Removing MacGuardian..."

pkill -x MacGuardianSuiteUI 2>/dev/null && echo "  ✔ Quit the app"

for plist in "$HOME"/Library/LaunchAgents/com.macguardian.*.plist; do
    [ -f "$plist" ] || continue
    label="$(basename "$plist" .plist)"
    launchctl bootout "$USER_DOMAIN/$label" 2>/dev/null || launchctl unload "$plist" 2>/dev/null || true
    rm -f "$plist"
    echo "  ✔ Removed background job $label"
done

if [ -d "$APP_PATH" ]; then
    rm -rf "$APP_PATH"
    echo "  ✔ Removed $APP_PATH"
fi

# Settings the app saved (repository path, last audit score).
defaults delete com.omegatech.macguardian 2>/dev/null && echo "  ✔ Removed app settings"

if [ -d "$RUNTIME_DIR" ]; then
    # A downloaded copy installed itself under $RUNTIME_DIR/Suite; if this
    # script lives there, the folder is removed on exit after we're done.
    rm -rf "$RUNTIME_DIR"
    echo "  ✔ Removed $RUNTIME_DIR"
fi

if [ -d "$DATA_DIR" ] && [ "$REMOVE_DATA" = false ] && [ -t 0 ]; then
    read -r -p "  Also delete your scan results, reports and logs in ~/.macguardian? [y/N] " reply
    [[ "$reply" =~ ^[Yy] ]] && REMOVE_DATA=true
fi
if [ "$REMOVE_DATA" = true ] && [ -d "$DATA_DIR" ]; then
    rm -rf "$DATA_DIR"
    echo "  ✔ Removed $DATA_DIR"
elif [ -d "$DATA_DIR" ]; then
    echo "  • Kept $DATA_DIR (run with --all to delete it)"
fi

echo ""
echo "MacGuardian has been removed."
echo "ClamAV and rkhunter, if installed with Homebrew, are left in place: brew uninstall clamav rkhunter"
