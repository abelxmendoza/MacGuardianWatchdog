#!/bin/bash
# MacGuardian Checkup: one button that repeats a full "is my Mac OK?" pass.
#
#   checkup.sh              everything, quick malware scan (recent downloads + startup folders)
#   checkup.sh --full       same, but scan all of ~/Downloads with ClamAV
#   checkup.sh --quick      skip the malware and threat scans (about 1 minute)
#   checkup.sh --json       print only the final JSON report (for the MCP server / LLMs)
#   checkup.sh --skip STEP  skip a step (repeatable): tailscale posture selfcheck
#                           threats malware browsers updates
#
# Read-only: it reports and suggests, it never deletes or changes settings.
# Reports are saved in ~/.macguardian/checkup/ (latest.json, latest.txt).
# Exit: 0 all clear, 1 something needs attention.

set -uo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
export HOMEBREW_NO_AUTO_UPDATE=1
export MG_NO_EMAIL=1   # automated runs never send report emails

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="$HOME/.macguardian/checkup"
mkdir -p "$OUT_DIR" && chmod 700 "$HOME/.macguardian" "$OUT_DIR" 2>/dev/null

JSON=false; FULL=false; SKIP=" "
while [ "$#" -gt 0 ]; do
    case "$1" in
        --json) JSON=true ;;
        --full) FULL=true ;;
        --quick) SKIP="$SKIP threats malware " ;;
        --skip) shift; SKIP="$SKIP ${1:-} " ;;
        -h|--help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

STAMP="$(date +%Y%m%d_%H%M%S)"
RESULTS="$(mktemp -t mg_checkup)"
WORK="$(mktemp -d -t mg_checkup_work)"
trap 'rm -rf "$RESULTS" "$WORK"' EXIT
START=$(date +%s)

say() { $JSON || printf '%s\n' "$*"; }
skipped() { [[ "$SKIP" == *" $1 "* ]]; }

# record STEP STATUS(pass|warn|fail|skip) SUMMARY [DETAIL_FILE_OR_JSON] [FIX]
record() {
    local icon
    case "$2" in pass) icon="✅";; warn) icon="⚠️ ";; fail) icon="❌";; *) icon="⏭️ ";; esac
    say "$icon $1: $3"
    [ -n "${5:-}" ] && say "   Fix: $5"
    python3 -I -c 'import json,sys; print(json.dumps({"step":sys.argv[1],"status":sys.argv[2],"summary":sys.argv[3],"detail":sys.argv[4],"fix":sys.argv[5]}))' \
        "$1" "$2" "$3" "${4:-}" "${5:-}" >> "$RESULTS"
}

say "🛡️  MacGuardian Checkup  ($(date '+%Y-%m-%d %H:%M'))"
say "========================================"

# 1. Tailscale -----------------------------------------------------------------
if skipped tailscale; then record tailscale skip "Skipped"
else
    say "… Checking Tailscale"
    ts="$(bash "$SCRIPT_DIR/tailscale_doctor.sh" --json 2>/dev/null)"; rc=$?
    if [ "$rc" = 2 ]; then record tailscale skip "Tailscale is not installed"
    else
        summary="$(printf '%s' "$ts" | python3 -I -c '
import json,sys
d=json.load(sys.stdin)
s="%s as %s, %s peer connection" % (d.get("state"), d.get("self"), d.get("connection"))
if d.get("problems"): s += " | " + " ".join(d["problems"])
elif d.get("notes"): s += " | " + d["notes"][0]
print(s)')"
        fix="$(printf '%s' "$ts" | python3 -I -c 'import json,sys; print(" ; ".join(json.load(sys.stdin).get("fixes",[])))')"
        if [ "$rc" = 0 ]; then
            notes="$(printf '%s' "$ts" | python3 -I -c 'import json,sys; print(len(json.load(sys.stdin).get("notes",[])))')"
            [ "$notes" = 0 ] && record tailscale pass "$summary" "$ts" || record tailscale warn "$summary" "$ts"
        else
            record tailscale fail "$summary" "$ts" "$fix"
        fi
    fi
fi

# 2. Security posture ------------------------------------------------------------
if skipped posture; then record posture skip "Skipped"
else
    say "… Checking security settings"
    audit="$(bash "$SCRIPT_DIR/mac_security_audit.sh" --json 2>/dev/null)"
    read -r fails warns names <<<"$(printf '%s' "$audit" | python3 -I -c '
import json,sys
try: c=json.load(sys.stdin).get("checks",[])
except Exception: print("? ? -"); sys.exit()
bad=[x["name"] for x in c if x.get("status")!="pass"]
print(sum(x.get("status")=="fail" for x in c), sum(x.get("status")=="warning" for x in c), "|".join(bad).replace(" ","_") or "-")')"
    if [ "$fails" = "?" ]; then record posture fail "The security audit did not produce a result"
    elif [ "$fails" = 0 ] && [ "$warns" = 0 ]; then record posture pass "FileVault, SIP, Gatekeeper, firewall, auto security updates on; Remote Login off" "$audit"
    else record posture "$([ "$fails" = 0 ] && echo warn || echo fail)" "Needs attention: ${names//[_|]/ }" "$audit" "Open MacGuardian > Audit > Posture for one-click fixes"
    fi
fi

# 3. MacGuardian self-check ------------------------------------------------------
if skipped selfcheck; then record selfcheck skip "Skipped"
else
    say "… Verifying MacGuardian itself"
    sc="$(bash "$SCRIPT_DIR/self_check.sh" 2>&1 | sed 's/\x1b\[[0-9;]*m//g')"
    line="$(printf '%s\n' "$sc" | grep -E '^Summary:' | tail -1)"
    failed="$(printf '%s' "$line" | sed -nE 's/.* ([0-9]+) failed.*/\1/p')"
    warned="$(printf '%s' "$line" | sed -nE 's/.* ([0-9]+) warnings.*/\1/p')"
    detail="$(printf '%s\n' "$sc" | grep -E '^(FAIL|WARN)' | head -10)"
    if [ -z "$line" ]; then record selfcheck fail "Self-check did not finish" "$sc"
    elif [ "${failed:-0}" != 0 ]; then record selfcheck fail "${line#Summary: }" "$detail" "If you changed MacGuardian's scripts yourself, run: bash $SCRIPT_DIR/self_check.sh --record"
    elif [ "${warned:-0}" != 0 ]; then record selfcheck warn "${line#Summary: }" "$detail"
    else record selfcheck pass "${line#Summary: }"
    fi
fi

# 4. Threat hunt (processes, network, odd files) ---------------------------------
if skipped threats; then record threats skip "Skipped"
else
    say "… Hunting for threats (processes, network, odd files)"
    TO=""; command -v timeout >/dev/null 2>&1 && TO="timeout 300"
    bt="$(cd "$SCRIPT_DIR" && $TO bash ./mac_blueteam.sh 2>&1 < /dev/null | sed 's/\x1b\[[0-9;]*m//g')"
    issues="$(printf '%s\n' "$bt" | sed -nE 's/.*Complete - ([0-9]+) Issue.*/\1/p' | tail -1)"
    findings="$(printf '%s\n' "$bt" | grep -E '^⚠️' | sed 's/^⚠️ *//' | head -20)"
    if [ -z "$issues" ] || [ "$issues" = 0 ]; then record threats pass "No suspicious processes, connections or files"
    else record threats warn "$issues finding(s) to review" "$findings" "Review in MacGuardian > Threats, or ask your assistant to explain each finding"
    fi
fi

# 5. Malware scan (ClamAV) ---------------------------------------------------------
if skipped malware; then record malware skip "Skipped"
elif ! command -v clamscan >/dev/null 2>&1; then
    record malware skip "ClamAV is not installed" "" "brew install clamav"
else
    DB="$(grep -hE '^DatabaseDirectory' /opt/homebrew/etc/clamav/freshclam.conf /usr/local/etc/clamav/freshclam.conf 2>/dev/null | awk '{print $2}' | head -1)"
    DB="${DB:-/opt/homebrew/var/clamav}"
    if [ -z "$(find "$DB" -name 'daily.c[lv]d' -mtime -1 2>/dev/null)" ]; then
        say "… Updating virus definitions"
        freshclam --quiet >/dev/null 2>&1 || say "   (could not update virus definitions; scanning with the ones on disk)"
    fi
    LIST="$WORK/scan_list"
    for d in "$HOME/Library/LaunchAgents" /Library/LaunchAgents /Library/LaunchDaemons /Users/Shared; do
        [ -d "$d" ] && find "$d" -type f -size -200M 2>/dev/null
    done | sort -u > "$LIST"
    if $FULL; then
        find "$HOME/Downloads" -type f -size -200M 2>/dev/null >> "$LIST"; scope="all of Downloads + startup folders"
    else
        find "$HOME/Downloads" -type f -mtime -14 -size -200M 2>/dev/null >> "$LIST"; scope="last 14 days of Downloads + startup folders"
    fi
    n="$(wc -l < "$LIST" | tr -d ' ')"
    say "… Scanning $n files for malware ($scope)"
    clam="$(clamscan --infected --no-summary --file-list="$LIST" 2>/dev/null)"; rc=$?
    infected="$(printf '%s\n' "$clam" | grep -c ' FOUND$' || true)"
    if [ "$rc" = 1 ] || [ "$infected" != 0 ]; then
        record malware fail "$infected infected file(s) found ($scope)" "$clam" "Open MacGuardian > Fix to quarantine them (nothing is deleted automatically)"
    elif [ "$rc" = 0 ]; then
        record malware pass "$n files clean ($scope)"
    else
        record malware warn "ClamAV reported an error while scanning" "$clam"
    fi
fi

# 6. Browser extensions ----------------------------------------------------------
if skipped browsers; then record browsers skip "Skipped"
else
    say "… Auditing Chrome, Brave, Edge and Firefox extensions"
    br="$(python3 -I "$SCRIPT_DIR/browser_audit.py" --json 2>/dev/null)"
    read -r total nrem nrev nhij <<<"$(printf '%s' "$br" | python3 -I -c '
import json,sys
d=json.load(sys.stdin); print(d["total"], len(d["remove"]), len(d["review"]), len(d["hijack_issues"]))' 2>/dev/null || echo "? ? ? ?")"
    names="$(printf '%s' "$br" | python3 -I -c '
import json,sys
d=json.load(sys.stdin); print(", ".join("%s (%s)" % (e["name"], e["browser"]) for e in d["remove"]))' 2>/dev/null)"
    if [ "$total" = "?" ]; then record browsers warn "Could not read browser profiles"
    elif [ "$nrem" != 0 ] || [ "$nhij" != 0 ]; then
        record browsers fail "$nrem risky extension(s) to remove: $names" "$br" "Remove them at chrome://extensions or about:addons (links in the report), then sign out of all sessions on important accounts"
    elif [ "$nrev" != 0 ]; then record browsers warn "$total extensions, $nrev worth a look" "$br"
    else record browsers pass "$total extensions, none risky"
    fi
fi

# 7. Software updates ------------------------------------------------------------
if skipped updates; then record updates skip "Skipped"
else
    say "… Checking for software updates"
    parts=(); total=0
    if command -v brew >/dev/null 2>&1; then
        f="$(brew outdated --formula --quiet 2>/dev/null | grep -c . || true)"
        c="$(brew outdated --cask --greedy --quiet 2>/dev/null | grep -c . || true)"
        parts+=("$f Homebrew tools" "$c Homebrew apps"); total=$((total + f + c))
    fi
    if command -v mas >/dev/null 2>&1; then
        m="$(mas outdated 2>/dev/null | grep -cE '^ *[0-9]+ ' || true)"
        parts+=("$m App Store apps"); total=$((total + m))
    fi
    os="$(softwareupdate -l 2>&1 | grep -c '^\* Label' || true)"
    parts+=("$os macOS updates"); total=$((total + os))
    summary="$(IFS=,; echo "${parts[*]}" | sed 's/,/, /g')"
    if [ "$total" = 0 ]; then record updates pass "Everything is up to date"
    else record updates warn "$summary" "" "bash $SCRIPT_DIR/package_updates.sh upgrade --batch -y   (allow /opt/homebrew/opt/curl/bin/curl in LuLu first)"
    fi
fi

# Report --------------------------------------------------------------------------
ELAPSED=$(( $(date +%s) - START ))
REPORT="$OUT_DIR/checkup_$STAMP.json"
python3 -I - "$RESULTS" "$ELAPSED" > "$REPORT" <<'PY'
import json, sys, socket, datetime
steps = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
for s in steps:
    try: s["detail"] = json.loads(s["detail"])
    except Exception: pass
worst = "fail" if any(s["status"] == "fail" for s in steps) else "warn" if any(s["status"] == "warn" for s in steps) else "pass"
print(json.dumps({
    "tool": "macguardian-checkup",
    "host": socket.gethostname(),
    "finished": datetime.datetime.now().isoformat(timespec="seconds"),
    "seconds": int(sys.argv[2]),
    "overall": worst,
    "needs_attention": [s["step"] for s in steps if s["status"] in ("fail", "warn")],
    "steps": steps,
}, indent=2))
PY
cp "$REPORT" "$OUT_DIR/latest.json"
python3 -I -c '
import json,sys
d=json.load(open(sys.argv[1]))
icon={"pass":"OK  ","warn":"WARN","fail":"FAIL","skip":"SKIP"}
print("MacGuardian Checkup %s - overall: %s" % (d["finished"], d["overall"].upper()))
for s in d["steps"]:
    print("%s  %-10s %s" % (icon[s["status"]], s["step"], s["summary"]))
    if s["fix"]: print("            fix: " + s["fix"])
' "$REPORT" > "$OUT_DIR/latest.txt"
ls -t "$OUT_DIR"/checkup_*.json 2>/dev/null | tail -n +31 | xargs rm -f 2>/dev/null  # keep the last 30

OVERALL="$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["overall"])' "$REPORT")"
if $JSON; then
    cat "$REPORT"
else
    echo "========================================"
    case "$OVERALL" in
        pass) echo "✅ All clear (${ELAPSED}s)";;
        warn) echo "⚠️  Some things are worth a look (${ELAPSED}s)";;
        fail) echo "❌ Action needed (${ELAPSED}s)";;
    esac
    echo "Report: $REPORT"
fi
[ "$OVERALL" = pass ] && exit 0 || exit 1
