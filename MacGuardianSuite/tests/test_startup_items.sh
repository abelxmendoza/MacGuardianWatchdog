#!/bin/bash

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TESTS_DIR/../startup_items.sh"
CLI="$TESTS_DIR/../../macguardian"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

BIN="$WORK/bin"; LOG="$WORK/calls.log"; STATE="$WORK/state"
mkdir -p "$BIN" "$STATE" "$WORK/user" "$WORK/agents" "$WORK/daemons"
export CALL_LOG="$LOG" STATE_DIR="$STATE"
export MG_USER_AGENTS="$WORK/user" MG_GLOBAL_AGENTS="$WORK/agents" MG_GLOBAL_DAEMONS="$WORK/daemons"

plist() { printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict><key>Label</key><string>%s</string></dict></plist>\n' "$2" > "$1/$2.plist"; }
plist "$WORK/user"    com.google.keystone.agent
plist "$WORK/agents"  com.adobe.ccxprocess
plist "$WORK/daemons" com.adobe.ARMDC.Communicator
plist "$WORK/daemons" us.zoom.ZoomDaemon
plist "$WORK/daemons" com.objective-see.blockblock
plist "$WORK/user"    com.example.devtool
ln -s "$WORK/gone/com.oracle.java.Helper-Tool.plist" "$WORK/daemons/com.oracle.java.Helper-Tool.plist"
echo "OpenVPN Connect, Alfred 4, LuLu" > "$STATE/login"

stub() { printf '#!/bin/bash\necho "%s $*" >> "$CALL_LOG"\n%s\nexit 0\n' "$1" "${2:-}" > "$BIN/$1"; chmod +x "$BIN/$1"; }
stub sudo 'exec "$@"'
# launchctl: disabled labels live in $STATE_DIR/disabled-<domain>
stub launchctl 'd() { echo "$STATE_DIR/disabled-$(echo "$1" | tr "/" "_")"; }
case "$1" in
  print-disabled) f="$(d "$2")"; [ -f "$f" ] && sed "s/.*/\t\"&\" => disabled/" "$f" ;;
  disable) dom="${2%/*}"; echo "${2##*/}" >> "$(d "$dom")" ;;
  enable)  dom="${2%/*}"; f="$(d "$dom")"; [ -f "$f" ] && grep -vx "${2##*/}" "$f" > "$f.tmp"; mv -f "$f.tmp" "$f" 2>/dev/null ;;
esac'
stub osascript 'case "$2" in
  *"get the name of every login item"*) cat "$STATE_DIR/login" ;;
  *"delete login item"*) sed -i "" "s/OpenVPN Connect, //" "$STATE_DIR/login" ;;
esac'

failures=0
check() { if eval "$2"; then echo "✅ $1"; else echo "❌ $1"; failures=$((failures + 1)); fi; }
called() { grep -Fxq "$1" "$LOG"; }
run() { PATH="$BIN:/usr/bin:/bin" /bin/bash "$@" < /dev/null; }
UIDN="$(id -u)"

out="$(run "$SCRIPT" list)"
check "list shows optional helpers"           'echo "$out" | grep -q "com.adobe.ccxprocess"'
check "list hides unrelated items by default" '! echo "$out" | grep -q "com.example.devtool"'
check "list flags the broken Java link"       'echo "$out" | grep -q "com.oracle.java.Helper-Tool.plist"'
check "list shows OpenVPN login item"         'echo "$out" | grep -q "OpenVPN Connect"'

out="$(run "$SCRIPT" list --all --json)"
check "--all --json is valid JSON with every item" 'echo "$out" | python3 -c "import json,sys; d=json.load(sys.stdin); assert len(d)==7, len(d)"'
check "security tools are marked protected"   'echo "$out" | grep -q "\"label\":\"com.objective-see.blockblock\",\"group\":\"\",\"scope\":\"daemon\",\"state\":\"on\",\"protected\":true"'

: > "$LOG"
run "$SCRIPT" off adobe >/dev/null 2>&1
check "refuses without a terminal or --yes"   '! grep -q "launchctl disable" "$LOG"'

: > "$LOG"
run "$SCRIPT" --dry-run trim >/dev/null
check "dry run changes nothing"               '! grep -qE "^launchctl (disable|enable)|delete login item" "$LOG"'

: > "$LOG"
run "$CLI" startup trim --yes >/dev/null
check "user agent disabled in the gui domain" 'called "launchctl disable gui/$UIDN/com.google.keystone.agent"'
check "global agent disabled in the gui domain" 'called "launchctl disable gui/$UIDN/com.adobe.ccxprocess"'
check "daemon disabled with sudo"             'called "sudo launchctl disable system/us.zoom.ZoomDaemon"'
check "running jobs are stopped"              'called "launchctl bootout system/com.adobe.ARMDC.Communicator"'
check "OpenVPN removed from login items"      'grep -q "delete login item \\\"OpenVPN Connect\\\"" "$LOG"'
check "security tools untouched"              '! grep -q "objective-see" "$LOG"'
check "unrelated items untouched"             '! grep -q "com.example.devtool" "$LOG"'

out="$(run "$SCRIPT" list --json)"
check "everything optional reads off after trim" '! echo "$out" | grep -q "\"state\":\"on\""'

: > "$LOG"
run "$SCRIPT" --yes trim >/dev/null
check "trim is a no-op the second time"       '! grep -qE "^launchctl (disable|bootout)" "$LOG"'

: > "$LOG"
run "$SCRIPT" --yes on zoom >/dev/null
check "on zoom re-enables the daemon"         'called "sudo launchctl enable system/us.zoom.ZoomDaemon"'
check "on zoom reloads it"                    'grep -q "launchctl bootstrap system .*us.zoom.ZoomDaemon.plist" "$LOG"'

run "$SCRIPT" --yes off com.objective-see.blockblock >/dev/null 2>&1; rc=$?
check "refuses to switch a protected label"  '[ "$rc" -eq 2 ]'
run "$SCRIPT" --yes off com.nope.missing >/dev/null 2>&1; rc=$?
check "unknown label exits 2"                '[ "$rc" -eq 2 ]'

echo ""
if [ "$failures" -gt 0 ]; then echo "$failures startup item test(s) failed"; exit 1; fi
echo "All startup item tests passed"
