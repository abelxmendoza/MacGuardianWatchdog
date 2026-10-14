#!/bin/bash
# ===============================
# MacGuardian one-step setup
#
# Run this once after downloading or cloning the project:
#     ./install.sh
#
# A downloaded copy (no .git folder, e.g. the zip from the website) is first
# copied to ~/Library/Application Support/MacGuardian/Suite, so the app keeps
# working after the download is deleted. A git clone stays where it is.
#
# It checks prerequisites, prepares ~/.macguardian, optionally installs the
# scanners (ClamAV, rkhunter) with Homebrew, builds the app, installs it to
# /Applications and opens it. Safe to run again to update.
#
# Options:
#     --yes        answer yes to every optional step (no questions asked)
#     --no-deps    skip installing ClamAV/rkhunter
#     --no-launch  don't open the app at the end
# ===============================

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUITE_DIR="$PROJECT_ROOT/MacGuardianSuite"
UI_DIR="$PROJECT_ROOT/MacGuardianSuiteUI"
DATA_DIR="$HOME/.macguardian"
APP_PATH="/Applications/MacGuardian Suite.app"

STABLE_DIR="$HOME/Library/Application Support/MacGuardian/Suite"
ORIGINAL_ARGS=("$@")

ASSUME_YES=false
INSTALL_DEPS=true
LAUNCH=true
for arg in "$@"; do
    case "$arg" in
        --yes|-y) ASSUME_YES=true ;;
        --no-deps) INSTALL_DEPS=false ;;
        --no-launch) LAUNCH=false ;;
        -h|--help) sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $arg (try --help)"; exit 1 ;;
    esac
done

bold=$'\033[1m'; green=$'\033[32m'; yellow=$'\033[33m'; red=$'\033[31m'; normal=$'\033[0m'
step() { echo ""; echo "${bold}▸ $*${normal}"; }
ok()   { echo "  ${green}✔${normal} $*"; }
warn() { echo "  ${yellow}⚠${normal}  $*"; }
fail() { echo ""; echo "${red}✖ $*${normal}"; exit 1; }

# Ask a yes/no question. Defaults to yes. Without a terminal (and without
# --yes) optional steps are skipped rather than guessed.
confirm() {
    if [ "$ASSUME_YES" = true ]; then return 0; fi
    if [ ! -t 0 ]; then return 1; fi
    local reply
    read -r -p "  $1 [Y/n] " reply
    [[ -z "$reply" || "$reply" =~ ^[Yy] ]]
}

echo "${bold}🛡️  MacGuardian Setup${normal}"
echo "Project: $PROJECT_ROOT"

# --- Prerequisites ------------------------------------------------------------
step "Checking prerequisites"

[ "$(uname)" = "Darwin" ] || fail "MacGuardian only runs on macOS."

macos_major="$(sw_vers -productVersion | cut -d. -f1)"
[ "$macos_major" -ge 14 ] || fail "macOS 14 (Sonoma) or newer is required. This Mac has $(sw_vers -productVersion)."
ok "macOS $(sw_vers -productVersion)"

[ -d "$SUITE_DIR" ] && [ -d "$UI_DIR" ] || fail "Run this from the MacGuardian project folder (MacGuardianSuite/ and MacGuardianSuiteUI/ not found)."

# A downloaded zip usually sits in ~/Downloads. Move to a permanent home so
# the app's scripts don't vanish with the download (and macOS doesn't ask for
# Downloads-folder access every time a scan runs), then continue from there.
if [ ! -d "$PROJECT_ROOT/.git" ] && [ "$PROJECT_ROOT" != "$STABLE_DIR" ]; then
    step "Copying MacGuardian to a permanent location"
    mkdir -p "$STABLE_DIR"
    rsync -a --delete --exclude ".build/" --exclude "__pycache__/" "$PROJECT_ROOT/" "$STABLE_DIR/"
    ok "Copied to $STABLE_DIR"
    echo "  You can delete the downloaded folder after setup finishes."
    exec bash "$STABLE_DIR/install.sh" ${ORIGINAL_ARGS[@]+"${ORIGINAL_ARGS[@]}"}
fi

# Files from a browser download are flagged as quarantined; clear the flag on
# our own files so the scripts and the built app run without warnings.
xattr -dr com.apple.quarantine "$PROJECT_ROOT" 2>/dev/null || true

# The app is SwiftUI, which needs the full Xcode (Command Line Tools alone
# can't build it).
if ! command -v xcodebuild >/dev/null 2>&1 || ! xcode-select -p >/dev/null 2>&1; then
    fail "Xcode is required to build the app. Install it from the App Store, open it once, then run ./install.sh again."
fi
if [[ "$(xcode-select -p)" == *CommandLineTools* ]]; then
    if [ -d /Applications/Xcode.app ]; then
        fail "Xcode is installed but not selected. Run:
    sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
then run ./install.sh again."
    fi
    fail "Only the Command Line Tools are installed; the app needs the full Xcode. Install Xcode from the App Store, then run ./install.sh again."
fi
if ! xcodebuild -license check >/dev/null 2>&1; then
    fail "The Xcode license hasn't been accepted yet. Run:
    sudo xcodebuild -license accept
then run ./install.sh again."
fi
ok "Xcode $(xcodebuild -version 2>/dev/null | head -1 | awk '{print $2}')"

# --- Scripts and data folder --------------------------------------------------
step "Preparing scripts and data folder"

find "$SUITE_DIR" -name "*.sh" -exec chmod +x {} +
chmod +x "$PROJECT_ROOT/mac_suite.sh" "$UI_DIR/build_app.sh"
ok "Scripts are executable"

mkdir -p "$DATA_DIR"/{logs,reports,baselines,events,audits}
chmod 700 "$DATA_DIR"
ok "Data folder ready at $DATA_DIR"

# --- Optional scanners --------------------------------------------------------
if [ "$INSTALL_DEPS" = true ]; then
    step "Scanners (ClamAV antivirus, rkhunter rootkit checker)"
    if ! command -v brew >/dev/null 2>&1; then
        warn "Homebrew not found, skipping. Scans that need these tools will say so."
        warn "To add them later: install Homebrew (https://brew.sh), then run ./install.sh again."
    else
        missing=()
        command -v clamscan >/dev/null 2>&1 || missing+=(clamav)
        command -v rkhunter >/dev/null 2>&1 || missing+=(rkhunter)
        if [ ${#missing[@]} -eq 0 ]; then
            ok "ClamAV and rkhunter already installed"
        elif confirm "Install ${missing[*]} with Homebrew?"; then
            brew install "${missing[@]}"
            ok "Installed ${missing[*]}"
        else
            warn "Skipped ${missing[*]}"
        fi

        # Homebrew's ClamAV ships without an active updater config.
        if command -v freshclam >/dev/null 2>&1; then
            clam_etc="$(brew --prefix)/etc/clamav"
            if [ ! -f "$clam_etc/freshclam.conf" ] && [ -f "$clam_etc/freshclam.conf.sample" ]; then
                sed '/^Example/d' "$clam_etc/freshclam.conf.sample" > "$clam_etc/freshclam.conf"
                ok "Created ClamAV updater config"
            fi
            db_dir="$(awk '/^DatabaseDirectory/ {print $2}' "$clam_etc/freshclam.conf" 2>/dev/null)"
            db_dir="${db_dir:-$(brew --prefix)/var/lib/clamav}"
            if [ -z "$(ls "$db_dir"/*.c[vl]d 2>/dev/null)" ]; then
                if confirm "Download the virus definitions now (about 300 MB)?"; then
                    freshclam || warn "Definition download failed; run 'freshclam' later."
                else
                    warn "No virus definitions yet. Run 'freshclam' before your first antivirus scan."
                fi
            else
                ok "Virus definitions present"
            fi
        fi
    fi
fi

# --- Build and install the app ------------------------------------------------
step "Building and installing the app (first build takes a few minutes)"
BUILD_LOG="$DATA_DIR/logs/install-build.log"
if ! "$UI_DIR/build_app.sh" > "$BUILD_LOG" 2>&1; then
    echo ""
    grep -E "error:" "$BUILD_LOG" | sed 's/\x1b\[[0-9;]*m//g' | sort -u | head -10 || true
    fail "The build failed. Full output: $BUILD_LOG"
fi
if [ "${SKIP_INSTALL:-0}" = "1" ]; then
    ok "Built (not installed, SKIP_INSTALL=1)"
else
    # Confirm /Applications now holds this build, not an older copy.
    installed_from="$(/usr/libexec/PlistBuddy -c "Print :MGRepositoryPath" "$APP_PATH/Contents/Info.plist" 2>/dev/null || true)"
    [ "$installed_from" = "$PROJECT_ROOT" ] || fail "The app didn't install correctly. Full output: $BUILD_LOG"
    ok "Installed to $APP_PATH"
fi

# --- Trusted baseline -----------------------------------------------------------
step "Recording trusted fingerprints of MacGuardian's scripts"
"$SUITE_DIR/self_check.sh" --record | sed 's/^/  /'
ok "The self-check (Audit → Self-Check in the app) will flag any script that changes after this point"

# --- Background jobs --------------------------------------------------------------
# Jobs run a private copy of the scripts; reinstalling refreshes that copy so
# they never run an outdated version after an update.
LA="$HOME/Library/LaunchAgents"
step "Background monitoring"
if [ -f "$LA/com.macguardian.monitor.plist" ]; then
    "$SUITE_DIR/install_monitor_daemon.sh" >/dev/null
    ok "Real-time monitor updated"
elif confirm "Run the real-time monitor in the background (feeds the Incidents, Timeline, SSH, User Accounts and Privacy screens)?"; then
    "$SUITE_DIR/install_monitor_daemon.sh" >/dev/null
    ok "Real-time monitor running (remove with MacGuardianSuite/install_monitor_daemon.sh --uninstall)"
else
    warn "Real-time monitor not installed. Live screens will stay empty until it is."
fi

has_jobs=false
for job in daily weekly reports; do
    [ -f "$LA/com.macguardian.$job.plist" ] && has_jobs=true
done
if [ "$has_jobs" = true ]; then
    "$SUITE_DIR/install_scheduler.sh" --refresh >/dev/null
    ok "Scheduled jobs updated (only the ones you already had)"
elif confirm "Schedule a file check every night (2 AM), a full check on Sundays (3 AM) and a daily report (9 AM)?"; then
    "$SUITE_DIR/install_scheduler.sh" >/dev/null
    ok "Scheduled (remove with MacGuardianSuite/install_scheduler.sh --uninstall)"
else
    warn "Not scheduled. You can run scans from the app any time."
fi

# --- Self-check -----------------------------------------------------------------
step "Self-check"
# Give a just-restarted monitor a moment to come up before checking on it.
if [ -f "$LA/com.macguardian.monitor.plist" ]; then
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        pid="$(cat "$DATA_DIR/.monitor.pid" 2>/dev/null || true)"
        [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && break
        sleep 1
    done
fi
self_check_ok=true
if "$SUITE_DIR/self_check.sh" > "$DATA_DIR/logs/self_check.log" 2>&1; then
    ok "$(tail -1 "$DATA_DIR/logs/self_check.log")"
    grep -E "^WARN|^      →" "$DATA_DIR/logs/self_check.log" | sed 's/^/  /' || true
else
    self_check_ok=false
    grep -E "^(FAIL|WARN)|^      →" "$DATA_DIR/logs/self_check.log" | sed 's/^/  /'
    warn "$(tail -1 "$DATA_DIR/logs/self_check.log") - see above"
fi

# --- Done ---------------------------------------------------------------------
echo ""
if [ "$self_check_ok" = true ]; then
    echo "${green}${bold}✅ MacGuardian is set up.${normal}"
else
    echo "${yellow}${bold}⚠  MacGuardian is installed, but the self-check found problems (listed above).${normal}"
fi
echo "   Open it from Applications, Spotlight or the Dock."
if [ -d "$PROJECT_ROOT/.git" ]; then
    echo "   To update later: git pull && ./install.sh"
else
    echo "   To update later: download the new version and run its installer again."
fi
echo "   To remove everything: $PROJECT_ROOT/uninstall.sh"
if [ "$LAUNCH" = true ]; then
    open "$APP_PATH"
fi
