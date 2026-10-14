#!/bin/bash
# ===============================
# MacGuardian self-check
#
# Checks MacGuardian's own security posture: are its scripts the ones that
# were installed, can anyone else modify them, is the installed app intact,
# and do its background jobs run what they should.
#
#   self_check.sh            run all checks (exit 1 if anything failed)
#   self_check.sh --record   record fingerprints of the current scripts as
#                            the trusted baseline (install.sh does this)
#
# The baseline lives in ~/.macguardian, outside the project folder, so
# whoever can change the scripts can't quietly update their fingerprints in
# the same place.
# ===============================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DATA_DIR="$HOME/.macguardian"
BASELINE="$DATA_DIR/install_manifest.sha256"
RUNTIME_DIR="$HOME/Library/Application Support/MacGuardian"
APP_PATH="/Applications/MacGuardian Suite.app"

passed=0; warned=0; failed=0
pass() { echo "PASS  $*"; passed=$((passed + 1)); }
warn() { echo "WARN  $*"; warned=$((warned + 1)); }
fail() { echo "FAIL  $*"; failed=$((failed + 1)); }
hint() { echo "      → $*"; }
section() { echo ""; echo "== $* =="; }

# Every file MacGuardian executes, relative to the project root.
list_code_files() {
    (
        cd "$PROJECT_ROOT" || exit 1
        for f in install.sh mac_suite.sh; do [ -f "$f" ] && echo "$f"; done
        find MacGuardianSuite -type f \( -name "*.sh" -o -name "*.py" \) \
            -not -path "*/__pycache__/*" -not -path "MacGuardianSuite/tests/*" | sort
    )
}

record_baseline() {
    mkdir -p "$DATA_DIR"
    chmod 700 "$DATA_DIR"
    local tmp
    tmp="$(mktemp)"
    (cd "$PROJECT_ROOT" && list_code_files | while IFS= read -r f; do shasum -a 256 "$f"; done) > "$tmp"
    mv "$tmp" "$BASELINE"
    chmod 600 "$BASELINE"
    echo "Recorded $(wc -l < "$BASELINE" | tr -d ' ') script fingerprints in $BASELINE"
}

if [ "${1:-}" = "--record" ]; then
    record_baseline
    exit 0
fi

echo "MacGuardian self-check  ($(date '+%Y-%m-%d %H:%M'))"
echo "Project: $PROJECT_ROOT"

# --- 1. Scripts match what was installed ---------------------------------------
section "Script integrity"
if [ ! -f "$BASELINE" ]; then
    warn "No trusted baseline recorded yet"
    hint "Run install.sh (or: $SCRIPT_DIR/self_check.sh --record) to record one"
else
    changed=(); missing=()
    while IFS= read -r line; do
        expected="${line%%  *}"; file="${line#*  }"
        if [ ! -f "$PROJECT_ROOT/$file" ]; then
            missing+=("$file")
        elif [ "$(shasum -a 256 "$PROJECT_ROOT/$file" | awk '{print $1}')" != "$expected" ]; then
            changed+=("$file")
        fi
    done < "$BASELINE"
    added=()
    while IFS= read -r f; do
        grep -qF "  $f" "$BASELINE" || added+=("$f")
    done < <(list_code_files)

    total="$(wc -l < "$BASELINE" | tr -d ' ')"
    if [ ${#changed[@]} -eq 0 ] && [ ${#missing[@]} -eq 0 ] && [ ${#added[@]} -eq 0 ]; then
        pass "All $total scripts match the fingerprints recorded at install"
    else
        for f in ${changed[@]+"${changed[@]}"}; do fail "Changed since install: $f"; done
        for f in ${added[@]+"${added[@]}"}; do fail "New script not present at install: $f"; done
        for f in ${missing[@]+"${missing[@]}"}; do warn "Missing since install: $f"; done
        hint "If you changed or updated these yourself, run install.sh again to trust the new versions."
        hint "If you didn't, treat them as tampered with and re-download MacGuardian."
    fi
fi

# --- 2. Nobody else can modify the scripts --------------------------------------
section "File permissions"
me="$(id -un)"
not_mine="$(find "$PROJECT_ROOT/MacGuardianSuite" "$PROJECT_ROOT/install.sh" -not -user "$me" -print 2>/dev/null | head -5)"
if [ -n "$not_mine" ]; then
    fail "Files owned by another user (they could change what MacGuardian runs):"
    echo "$not_mine" | sed 's/^/      /'
    hint "sudo chown -R $me \"$PROJECT_ROOT\""
else
    pass "All MacGuardian files are owned by $me"
fi
writable="$(find "$PROJECT_ROOT/MacGuardianSuite" "$PROJECT_ROOT/install.sh" \( -perm -g+w -o -perm -o+w \) -not -type l -print 2>/dev/null | head -5)"
if [ -n "$writable" ]; then
    fail "Files other users can modify:"
    echo "$writable" | sed 's/^/      /'
    hint "chmod -R go-w \"$PROJECT_ROOT\""
else
    pass "No MacGuardian file is writable by other users"
fi
if [ -d "$DATA_DIR" ]; then
    mode="$(stat -f '%Lp' "$DATA_DIR")"
    if [ "$mode" = "700" ]; then
        pass "Data folder ~/.macguardian is private (700)"
    else
        warn "Data folder ~/.macguardian is readable by others (mode $mode); it holds scan results and logs"
        hint "chmod 700 ~/.macguardian"
    fi
fi
if [ -f "$DATA_DIR/config.conf" ] && grep -qiE '^[A-Z_]*PASSWORD="[^"]+"' "$DATA_DIR/config.conf"; then
    fail "A password is stored in plain text in ~/.macguardian/config.conf"
    hint "Remove it; the app keeps the SMTP password in your Keychain"
fi
if xattr -r "$PROJECT_ROOT/MacGuardianSuite" 2>/dev/null | grep -q com.apple.quarantine; then
    warn "Some scripts still carry the download quarantine flag"
    hint "Run install.sh to clear it"
fi

# --- 3. Installed app is intact and uses these scripts -------------------------
section "Installed app"
if [ ! -d "$APP_PATH" ]; then
    warn "MacGuardian Suite.app is not in /Applications"
    hint "Run install.sh"
else
    if codesign --verify --deep --strict "$APP_PATH" 2>/dev/null; then
        pass "App code signature is intact (nothing inside the app was modified after it was built)"
    else
        fail "App code signature is broken: files inside MacGuardian Suite.app changed after it was built"
        hint "Run install.sh to rebuild it"
    fi
    linked="$(/usr/libexec/PlistBuddy -c 'Print :MGRepositoryPath' "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "")"
    if [ "$linked" = "$PROJECT_ROOT" ]; then
        pass "App runs the scripts in this folder"
    elif [ -n "$linked" ]; then
        warn "App was built from a different folder: $linked"
        hint "Run install.sh from the copy you want the app to use"
    fi
fi

# --- 4. Background jobs ----------------------------------------------------------
section "Background jobs"
found_jobs=false
for plist in "$HOME"/Library/LaunchAgents/com.macguardian.*.plist; do
    [ -f "$plist" ] || continue
    found_jobs=true
    label="$(basename "$plist" .plist)"
    if [ "$(stat -f '%Su' "$plist")" != "$me" ] || [ -n "$(find "$plist" \( -perm -g+w -o -perm -o+w \) 2>/dev/null)" ]; then
        fail "$label: job definition can be modified by another user"
        hint "chmod 644 \"$plist\""
    fi
    # The script the job runs is the first argument that isn't a shell.
    program=""
    i=0
    while arg="$(/usr/libexec/PlistBuddy -c "Print :ProgramArguments:$i" "$plist" 2>/dev/null)"; do
        case "$arg" in /bin/bash|/bin/zsh|/bin/sh|/usr/bin/env) ;; *) program="$arg"; break ;; esac
        i=$((i + 1))
    done
    if [ -z "$program" ] || [ ! -f "$program" ]; then
        fail "$label: runs a script that doesn't exist (${program:-none})"
        hint "Run install.sh to reinstall background jobs"
        continue
    fi
    case "$program" in
        "$HOME/Desktop/"*|"$HOME/Documents/"*|"$HOME/Downloads/"*)
            fail "$label: runs from a folder macOS blocks for background jobs, so it never actually runs ($program)"
            hint "Run install.sh to move it to $RUNTIME_DIR"
            continue ;;
    esac
    [[ "$program" == "$RUNTIME_DIR/"* ]] && uses_runtime=true
    pass "$label runs $(basename "$program")"
done
$found_jobs || echo "INFO  No background jobs installed (optional)"
# Background jobs run a private copy of the scripts (macOS won't let them run
# from Desktop/Documents/Downloads). Make sure that copy isn't out of date.
if ${uses_runtime:-false}; then
    stale=()
    while IFS= read -r f; do
        rel="${f#MacGuardianSuite/}"
        if [ ! -f "$RUNTIME_DIR/$rel" ] || ! cmp -s "$PROJECT_ROOT/$f" "$RUNTIME_DIR/$rel"; then
            stale+=("$rel")
        fi
    done < <(list_code_files | grep '^MacGuardianSuite/')
    if [ ${#stale[@]} -eq 0 ]; then
        pass "Background jobs run an up-to-date copy of the scripts"
    else
        warn "Background jobs run an older copy of ${#stale[@]} script(s), e.g. ${stale[0]}"
        hint "Run install.sh to refresh background jobs"
    fi
fi
if [ -f "$HOME/Library/LaunchAgents/com.macguardian.monitor.plist" ]; then
    pid="$(cat "$DATA_DIR/.monitor.pid" 2>/dev/null || echo "")"
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        pass "Real-time monitor is running (PID $pid)"
    else
        warn "Real-time monitor is installed but not running"
        hint "launchctl kickstart -k gui/$(id -u)/com.macguardian.monitor"
    fi
fi

# --- Summary -------------------------------------------------------------------
echo ""
echo "Summary: $passed passed, $warned warnings, $failed failed"
[ "$failed" -eq 0 ]
