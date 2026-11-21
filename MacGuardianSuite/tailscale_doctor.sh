#!/bin/bash
# Tailscale doctor: find the common reasons Tailscale "doesn't work" on a Mac.
#
#   tailscale_doctor.sh          human-readable report
#   tailscale_doctor.sh --json   one JSON object (used by checkup.sh and the MCP server)
#
# Read-only. The one fix it knows (stopping a duplicate Homebrew daemon) needs
# your password, so it prints the exact command instead of running it.
# Exit: 0 healthy, 1 problem found, 2 Tailscale not installed.

set -uo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

JSON=false
[ "${1:-}" = "--json" ] && JSON=true

APP_CLI="/Applications/Tailscale.app/Contents/MacOS/Tailscale"
BREW_PLIST="/Library/LaunchDaemons/com.tailscale.tailscaled.plist"
PROBLEMS=()
FIXES=()
NOTES=()

json_escape() { python3 -I -c 'import json,sys; print(json.dumps(sys.stdin.read().rstrip("\n")))'; }

CLI=""
if [ -x "$APP_CLI" ]; then CLI="$APP_CLI"; elif command -v tailscale >/dev/null 2>&1; then CLI="$(command -v tailscale)"; fi

if [ -z "$CLI" ]; then
    if $JSON; then echo '{"installed":false,"healthy":false,"problems":["Tailscale is not installed"],"fixes":[],"notes":[]}'; else echo "Tailscale is not installed."; fi
    exit 2
fi

# 1. Two daemons at once: the App Store/standalone app (IPNExtension) and a
#    Homebrew tailscaled. They register two machines and fight over routes and DNS.
APP_RUNNING=false; BREW_RUNNING=false
pgrep -f "IPNExtension|io.tailscale.ipn.macsys.network-extension" >/dev/null 2>&1 && APP_RUNNING=true
pgrep -f "/opt/homebrew/.*/tailscaled|/usr/local/.*/tailscaled" >/dev/null 2>&1 && BREW_RUNNING=true
if $APP_RUNNING && $BREW_RUNNING; then
    PROBLEMS+=("Two Tailscale daemons are running: the Tailscale app and a Homebrew tailscaled. They register two machines and fight over routes and DNS.")
    if [ -f "$BREW_PLIST" ]; then
        FIXES+=("sudo launchctl bootout system $BREW_PLIST && sudo mv $BREW_PLIST ~/Desktop/com.tailscale.tailscaled.plist.disabled")
    else
        FIXES+=("sudo brew services stop tailscale")
    fi
    FIXES+=("Then delete the stale duplicate machine at https://login.tailscale.com/admin/machines")
fi

# 2. Backend state and health from the daemon itself.
STATUS_JSON="$("$CLI" status --json 2>/dev/null || true)"
read -r STATE SELF_NAME SELF_IP HEALTH <<<"$(printf '%s' "$STATUS_JSON" | python3 -I -c '
import json,sys
try:
    d=json.load(sys.stdin)
except Exception:
    print("Unreachable - - -"); sys.exit()
s=d.get("Self") or {}
ips=s.get("TailscaleIPs") or ["-"]
h=d.get("Health") or []
print(d.get("BackendState","?"), s.get("HostName","-").replace(" ","_"), ips[0], len(h))
')"
case "$STATE" in
    Running) ;;
    NeedsLogin) PROBLEMS+=("Tailscale is logged out."); FIXES+=("Open the Tailscale menu bar app and log in");;
    Stopped) PROBLEMS+=("Tailscale is turned off."); FIXES+=("$CLI up");;
    Unreachable) PROBLEMS+=("The Tailscale daemon is not answering."); FIXES+=("Quit and reopen the Tailscale app");;
    *) PROBLEMS+=("Tailscale state is $STATE.");;
esac
if [ "${HEALTH:-0}" != "0" ] && [ "$HEALTH" != "-" ]; then
    while IFS= read -r line; do [ -n "$line" ] && PROBLEMS+=("Health warning: $line"); done <<<"$(printf '%s' "$STATUS_JSON" | python3 -I -c 'import json,sys; [print(h) for h in (json.load(sys.stdin).get("Health") or [])]' 2>/dev/null)"
fi

# 3. Duplicate machine names for this Mac (e.g. ryuk and ryuk-1).
DUPES="$(printf '%s' "$STATUS_JSON" | python3 -I -c '
import json,sys,re
try: d=json.load(sys.stdin)
except Exception: sys.exit()
label=lambda n: (n.get("DNSName") or n.get("HostName") or "").split(".")[0].lower()
me=label(d.get("Self") or {})
for p in (d.get("Peer") or {}).values():
    n=label(p)
    if me and n != me and re.sub(r"-\d+$","",n) == re.sub(r"-\d+$","",me):
        print(n, "(online)" if p.get("Online") else "(offline)")
' 2>/dev/null)"
if [ -n "$DUPES" ]; then
    NOTES+=("Another machine in your tailnet looks like a duplicate of this Mac: $DUPES. Remove it at https://login.tailscale.com/admin/machines if it is stale.")
fi

# 4. CLI version mismatch (old Homebrew CLI talking to a newer app daemon).
if command -v tailscale >/dev/null 2>&1 && [ "$(command -v tailscale)" != "$APP_CLI" ]; then
    if tailscale status 2>&1 | grep -q "client version"; then
        NOTES+=("The Homebrew 'tailscale' command is older than the app. Use the app's CLI ($APP_CLI) or run 'brew upgrade tailscale'.")
    fi
fi

# 5. Can we reach a peer directly, or only via relay (DERP)?
CONN=""
if [ "$STATE" = "Running" ]; then
    PEER="$(printf '%s' "$STATUS_JSON" | python3 -I -c '
import json,sys
d=json.load(sys.stdin)
for p in (d.get("Peer") or {}).values():
    if p.get("Online") and p.get("TailscaleIPs"): print(p["TailscaleIPs"][0]); break
' 2>/dev/null)"
    if [ -n "$PEER" ]; then
        PING="$("$CLI" ping -c 3 --timeout 3s "$PEER" 2>&1 | tail -2)"
        if echo "$PING" | grep -q "via DERP" && ! echo "$PING" | grep -qE "via \[|via [0-9]+\.[0-9]"; then
            CONN="relay"
            NOTES+=("Connections to peers go through a relay (slower). A firewall such as LuLu blocking Tailscale's UDP traffic is a common cause.")
        elif echo "$PING" | grep -q "pong"; then
            CONN="direct"
        else
            CONN="unreachable"
            NOTES+=("No online peer answered a ping.")
        fi
    fi
fi

HEALTHY=true
[ "${#PROBLEMS[@]}" -gt 0 ] && HEALTHY=false

if $JSON; then
    arr() { python3 -I -c 'import json,sys; print(json.dumps([l for l in sys.stdin.read().split("\x1e") if l]))'; }
    printf '{"installed":true,"healthy":%s,"state":"%s","self":"%s","ip":"%s","connection":"%s","app_daemon":%s,"homebrew_daemon":%s,"problems":%s,"fixes":%s,"notes":%s}\n' \
        "$HEALTHY" "$STATE" "$SELF_NAME" "$SELF_IP" "${CONN:-unknown}" "$APP_RUNNING" "$BREW_RUNNING" \
        "$(printf '%s\x1e' "${PROBLEMS[@]+"${PROBLEMS[@]}"}" | arr)" \
        "$(printf '%s\x1e' "${FIXES[@]+"${FIXES[@]}"}" | arr)" \
        "$(printf '%s\x1e' "${NOTES[@]+"${NOTES[@]}"}" | arr)"
else
    echo "Tailscale: $STATE as $SELF_NAME ($SELF_IP), peer connection: ${CONN:-unknown}"
    for p in "${PROBLEMS[@]+"${PROBLEMS[@]}"}"; do echo "PROBLEM  $p"; done
    for f in "${FIXES[@]+"${FIXES[@]}"}"; do echo "FIX      $f"; done
    for n in "${NOTES[@]+"${NOTES[@]}"}"; do echo "NOTE     $n"; done
    $HEALTHY && echo "Tailscale looks healthy."
fi
$HEALTHY && exit 0 || exit 1
