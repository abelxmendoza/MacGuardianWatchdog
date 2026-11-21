#!/bin/bash

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TESTS_DIR/../posture_toggles.sh"
CLI="$TESTS_DIR/../../macguardian"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

BIN="$WORK/bin"
LOG="$WORK/calls.log"
STATE="$WORK/state"
mkdir -p "$BIN" "$STATE"
export CALL_LOG="$LOG" STATE_DIR="$STATE"

# Fake system tools. Each records its call; state files decide what probes see.
stub() { printf '#!/bin/bash\necho "%s $*" >> "$CALL_LOG"\n%s\nexit 0\n' "$1" "${2:-}" > "$BIN/$1"; chmod +x "$BIN/$1"; }
stub sudo 'exec "$@"'
stub systemsetup '[ "$3" = off ] && rm -f "$STATE_DIR/ssh"; [ "$3" = on ] && touch "$STATE_DIR/ssh"'
stub nc '[ -f "$STATE_DIR/ssh" ] || exit 1'
stub sysadminctl 'if [ "$1 $2" = "-screenLock status" ]; then [ -f "$STATE_DIR/lock" ] && echo "screenLock delay is immediate" >&2 || echo "screenLock delay is 300 seconds" >&2; elif [ "$2" = immediate ]; then touch "$STATE_DIR/lock"; else rm -f "$STATE_DIR/lock"; fi'
stub lsof '[ -f "$STATE_DIR/airplay" ] && echo "ControlCe 1 u TCP *:7000 (LISTEN)"'
stub pmset 'if [ "$1" = -g ]; then echo " powernap $(cat "$STATE_DIR/powernap" 2>/dev/null || echo 1)"; echo " womp $(cat "$STATE_DIR/womp" 2>/dev/null || echo 1)"; else echo "$3" > "$STATE_DIR/$2"; fi'
stub defaults 'if [ "$1" = read ]; then [ -f "$STATE_DIR/ext" ] && echo 1 || echo 0; elif [ "$3 $4" = "com.apple.controlcenter AirplayRecieverEnabled" ] || [ "$4 $5" = "com.apple.controlcenter AirplayRecieverEnabled" ]; then [ "${@: -1}" = false ] && rm -f "$STATE_DIR/airplay" || touch "$STATE_DIR/airplay"; elif [ "$3" = AppleShowAllExtensions ]; then [ "$5" = true ] && touch "$STATE_DIR/ext" || rm -f "$STATE_DIR/ext"; fi'
stub killall
stub sleep

failures=0
check() {
    if eval "$2"; then echo "✅ $1"; else echo "❌ $1"; failures=$((failures + 1)); fi
}
called() { grep -Fxq "$1" "$LOG"; }
run() { PATH="$BIN:/usr/bin:/bin" bash "$@" < /dev/null; }

# Start in the exposed state: SSH on, AirPlay on, Power Nap/womp on, slow lock, extensions hidden.
touch "$STATE/ssh" "$STATE/airplay"

out="$(run "$SCRIPT" status --json)"
check "status --json reports ssh on and unsafe" 'echo "$out" | grep -q "\"control\":\"ssh\",\"label\":\"Remote Login (SSH)\",\"state\":\"on\",\"safe_state\":\"off\",\"safe\":false"'
check "status --json is a JSON array" 'echo "$out" | python3 -c "import json,sys; assert len(json.load(sys.stdin))==6"'

: > "$LOG"
run "$SCRIPT" off ssh >/dev/null 2>&1
check "refuses to change settings without a terminal or --yes" '! called "systemsetup -f -setremotelogin off"'

: > "$LOG"
run "$SCRIPT" --dry-run harden >/dev/null
check "dry run changes nothing" '! grep -qE "^(systemsetup|pmset -a|sysadminctl -screenLock immediate|defaults write|defaults -currentHost write)" "$LOG"'

: > "$LOG"
run "$CLI" posture harden --yes >/dev/null
check "harden turns SSH off"            'called "systemsetup -f -setremotelogin off"'
check "harden locks immediately"        'called "sysadminctl -screenLock immediate -password -"'
check "harden disables AirPlay Receiver" 'called "defaults -currentHost write com.apple.controlcenter AirplayRecieverEnabled -bool false"'
check "harden disables Power Nap"       'called "pmset -a powernap 0"'
check "harden disables network wake"    'called "pmset -a womp 0"'
check "harden shows file extensions"    'called "defaults write NSGlobalDomain AppleShowAllExtensions -bool true"'
check "sudo used for protected changes" 'called "sudo pmset -a powernap 0"'

out="$(run "$SCRIPT" status --json)"
check "everything reads safe after harden" '! echo "$out" | grep -q "\"safe\":false"'

: > "$LOG"
run "$SCRIPT" --yes harden >/dev/null
check "harden is a no-op when already safe" '! grep -qE "^(systemsetup|pmset -a|sysadminctl -screenLock [^s]|defaults write)" "$LOG"'

: > "$LOG"
run "$SCRIPT" --yes on airplay >/dev/null
check "on airplay re-enables the receiver" 'called "defaults write com.apple.controlcenter AirplayRecieverEnabled -bool true"'

run "$SCRIPT" on bogus >/dev/null 2>&1; rc=$?
check "unknown control exits 2" '[ "$rc" -eq 2 ]'

echo ""
if [ "$failures" -gt 0 ]; then
    echo "$failures posture toggle test(s) failed"
    exit 1
fi
echo "All posture toggle tests passed"
