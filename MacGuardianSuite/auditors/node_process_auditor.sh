#!/bin/bash

# ===============================
# Node Process Auditor
# Explains every running "node" binary so LuLu-style outbound-firewall
# alerts stop looking like an attack and start looking like dev tooling.
# Event Spec v1.0.0 compliant
# ===============================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUITE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source core modules
source "$SUITE_DIR/core/validators.sh" 2>/dev/null || true
source "$SUITE_DIR/core/logging.sh" 2>/dev/null || true
source "$SUITE_DIR/core/privilege_check.sh" 2>/dev/null || true
source "$SUITE_DIR/daemons/event_writer.sh" 2>/dev/null || true
source "$SUITE_DIR/utils.sh" 2>/dev/null || true

# This is a read-only diagnostic - it should finish and report even when an
# individual probe (codesign/xattr/ps on a process that just exited) fails,
# rather than inheriting -e from the sourced core modules and dying mid-scan.
set +e

# Fallbacks in case a core module failed to source
type success &>/dev/null || success() { echo "[OK] $1"; }
type warning &>/dev/null || warning() { echo "[!] $1" >&2; }
type info &>/dev/null || info() { echo "[i] $1"; }
type log_auditor &>/dev/null || log_auditor() { :; }
type write_event &>/dev/null || write_event() { :; }
type check_privileges &>/dev/null || check_privileges() { return 0; }

AUDIT_DIR="$HOME/.macguardian/audits"
AUDIT_OUTPUT="$AUDIT_DIR/node_process_audit_$(date +%Y%m%d_%H%M%S).json"
mkdir -p "$AUDIT_DIR"

STATE_PREFIX="$AUDIT_DIR/.node_process_auditor.$$"
trap 'rm -f "${STATE_PREFIX}".*' EXIT

MAX_ANCESTRY_DEPTH=8

# ===============================
# Helpers
# ===============================

json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    printf '%s' "$s"
}

# Resolve the parent chain of a pid up to launchd (pid 1) or MAX_ANCESTRY_DEPTH
ancestry_chain() {
    local pid="$1"
    local chain=""
    local depth=0

    while [ -n "$pid" ] && [ "$pid" != "0" ] && [ "$depth" -lt "$MAX_ANCESTRY_DEPTH" ]; do
        local comm
        comm=$(ps -p "$pid" -o comm= 2>/dev/null | sed 's/^[ \t]*//;s/[ \t]*$//')
        if [ -z "$comm" ]; then
            break
        fi

        local base="${comm##*/}"
        if [ -n "$chain" ]; then
            chain="$chain <- $base"
        else
            chain="$base"
        fi

        if [ "$pid" = "1" ]; then
            break
        fi

        local ppid
        ppid=$(ps -p "$pid" -o ppid= 2>/dev/null | tr -d ' \t')
        if [ -z "$ppid" ] || [ "$ppid" = "$pid" ]; then
            break
        fi
        pid="$ppid"
        depth=$((depth + 1))
    done

    echo "$chain"
}

# Inspect a binary's code signature; prints "signed|authority", "unsigned|", or "error|"
codesign_summary() {
    local path="$1"
    local output cs_status

    output=$(codesign -dv --verbose=4 "$path" 2>&1)
    cs_status=$?

    if [ "$cs_status" -ne 0 ]; then
        if echo "$output" | grep -q "code object is not signed at all"; then
            echo "unsigned|"
        else
            echo "error|"
        fi
        return
    fi

    local authority
    authority=$(echo "$output" | grep "^Authority=" | head -1 | cut -d= -f2-)
    echo "signed|${authority:-unknown}"
}

# Classify a node-family binary purely on evidence: signature + filesystem location
classify_binary() {
    local path="$1"
    local sig_status="$2"
    local authority="$3"

    local risk="benign"
    local reasons=()

    case "$path" in
        /tmp/*|/private/tmp/*|/var/tmp/*|/Users/Shared/*|*/Downloads/*)
            risk="suspicious"
            reasons+=("running from a transient/download-style directory ($path)")
            ;;
    esac

    if xattr -p com.apple.quarantine "$path" &>/dev/null; then
        risk="suspicious"
        reasons+=("still carries the macOS quarantine flag (recently downloaded, never explicitly approved)")
    fi

    if [ "$sig_status" = "signed" ] && echo "$authority" | grep -qi "Node.js Foundation"; then
        reasons+=("signed by the official Node.js Foundation Developer ID")
    elif [ "$sig_status" = "signed" ]; then
        reasons+=("signed, but by a party other than Node.js Foundation: $authority")
        [ "$risk" = "benign" ] && risk="unknown"
    elif [ "$sig_status" = "unsigned" ]; then
        reasons+=("binary is not code-signed at all")
        [ "$risk" = "benign" ] && risk="unknown"
    else
        reasons+=("code signature could not be evaluated")
        [ "$risk" = "benign" ] && risk="unknown"
    fi

    local joined
    joined=$(printf '%s; ' "${reasons[@]}")
    echo "${risk}|${joined%; }"
}

severity_for_risk() {
    case "$1" in
        suspicious) echo "high" ;;
        unknown) echo "medium" ;;
        *) echo "low" ;;
    esac
}

# ===============================
# Scan 1: live node-family processes
# Prints directly to the terminal and leaves results in state files
# (never call this via $(...) - that would swallow the live output).
# ===============================

scan_running_processes() {
    local -a entries=()
    local total=0
    local benign_count=0
    local flagged_count=0

    echo ""
    echo "== Running Node-family processes =="
    echo ""

    local all_pids
    all_pids=$(ps -Ao pid= 2>/dev/null)

    while IFS= read -r raw_pid; do
        local pid="${raw_pid// /}"
        [ -z "$pid" ] && continue

        local comm
        comm=$(ps -p "$pid" -o comm= 2>/dev/null | sed 's/^[ \t]*//;s/[ \t]*$//')
        [ -z "$comm" ] && continue

        local base="${comm##*/}"
        case "$base" in
            node|npm|npx|corepack|node-gyp) ;;
            *) continue ;;
        esac

        total=$((total + 1))

        local ppid args chain sig authority risk reasons severity
        ppid=$(ps -p "$pid" -o ppid= 2>/dev/null | tr -d ' \t')
        args=$(ps -p "$pid" -o args= 2>/dev/null | sed 's/^[ \t]*//;s/[ \t]*$//')
        chain=$(ancestry_chain "${ppid:-0}")

        if [ -x "$comm" ]; then
            local sig_line
            sig_line=$(codesign_summary "$comm")
            sig="${sig_line%%|*}"
            authority="${sig_line#*|}"
        else
            sig="error"
            authority=""
        fi

        local class_line
        class_line=$(classify_binary "$comm" "$sig" "$authority")
        risk="${class_line%%|*}"
        reasons="${class_line#*|}"
        severity=$(severity_for_risk "$risk")

        if [ "$risk" = "benign" ]; then
            benign_count=$((benign_count + 1))
            success "pid $pid  $comm"
        elif [ "$risk" = "suspicious" ]; then
            flagged_count=$((flagged_count + 1))
            warning "pid $pid  $comm  [$risk]"
        else
            flagged_count=$((flagged_count + 1))
            info "pid $pid  $comm  [$risk]"
        fi
        echo "    parent chain: $chain"
        echo "    reasons: $reasons"
        echo "    args: ${args:0:160}"
        echo ""

        entries+=("$(printf '{"pid": %s, "ppid": %s, "path": "%s", "args": "%s", "parent_chain": "%s", "signature_status": "%s", "authority": "%s", "risk": "%s", "reasons": "%s"}' \
            "$pid" "${ppid:-0}" "$(json_escape "$comm")" "$(json_escape "${args:0:500}")" "$(json_escape "$chain")" "$sig" "$(json_escape "$authority")" "$risk" "$(json_escape "$reasons")")")

        log_auditor "node_process_auditor" "INFO" "pid=$pid path=$comm risk=$risk"

        if [ "$risk" != "benign" ]; then
            local context_json
            context_json=$(printf '{"pid": %s, "path": "%s", "parent_chain": "%s", "signature_status": "%s", "authority": "%s", "reasons": "%s"}' \
                "$pid" "$(json_escape "$comm")" "$(json_escape "$chain")" "$sig" "$(json_escape "$authority")" "$(json_escape "$reasons")")
            write_event "process_anomaly" "$severity" "node_process_auditor" "$context_json"
        fi
    done <<< "$all_pids"

    local findings_json="[]"
    if [ "${#entries[@]}" -gt 0 ]; then
        local IFS=,
        findings_json="[${entries[*]}]"
    fi

    echo "Summary: $total node-family process(es) found - $benign_count benign, $flagged_count flagged for review."
    echo ""

    echo "$total" > "${STATE_PREFIX}.total"
    echo "$benign_count" > "${STATE_PREFIX}.benign"
    echo "$flagged_count" > "${STATE_PREFIX}.flagged"
    echo "$findings_json" > "${STATE_PREFIX}.findings"
}

# ===============================
# Scan 2: persistence (LaunchAgents / LaunchDaemons)
# ===============================

scan_persistence() {
    echo "== LaunchAgents / LaunchDaemons that auto-run node/npm/npx =="
    echo ""

    local dirs=(
        "$HOME/Library/LaunchAgents"
        "/Library/LaunchAgents"
        "/Library/LaunchDaemons"
    )
    local hits=0

    for dir in "${dirs[@]}"; do
        [ -d "$dir" ] || continue
        while IFS= read -r plist; do
            [ -z "$plist" ] && continue
            local prog
            prog=$(/usr/libexec/PlistBuddy -c "Print :Program" "$plist" 2>/dev/null)
            if [ -z "$prog" ]; then
                prog=$(/usr/libexec/PlistBuddy -c "Print :ProgramArguments:0" "$plist" 2>/dev/null)
            fi
            [ -z "$prog" ] && continue

            local base="${prog##*/}"
            case "$base" in
                node|npm|npx|corepack) ;;
                *) continue ;;
            esac

            hits=$((hits + 1))
            warning "$plist -> $prog"
            log_auditor "node_process_auditor" "WARNING" "persistence item $plist runs $prog"
        done < <(find "$dir" -maxdepth 1 -name "*.plist" 2>/dev/null)
    done

    if [ "$hits" -eq 0 ]; then
        success "No launch agents/daemons found that auto-run node/npm/npx at login or boot."
    fi
    echo ""

    echo "$hits" > "${STATE_PREFIX}.persistence"
}

# ===============================
# Main
# ===============================

main() {
    echo "MacGuardian Node Process Auditor"
    echo "Explains what is actually invoking 'node' so LuLu-style firewall alerts can be judged calmly."

    check_privileges "watch"

    scan_running_processes
    scan_persistence

    local total benign flagged persistence_hits findings_json
    total=$(cat "${STATE_PREFIX}.total" 2>/dev/null || echo 0)
    benign=$(cat "${STATE_PREFIX}.benign" 2>/dev/null || echo 0)
    flagged=$(cat "${STATE_PREFIX}.flagged" 2>/dev/null || echo 0)
    persistence_hits=$(cat "${STATE_PREFIX}.persistence" 2>/dev/null || echo 0)
    findings_json=$(cat "${STATE_PREFIX}.findings" 2>/dev/null || echo "[]")

    cat > "$AUDIT_OUTPUT" <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "audit_type": "node_process",
  "processes_scanned": $total,
  "benign_count": $benign,
  "flagged_count": $flagged,
  "persistence_hits": $persistence_hits,
  "findings": $findings_json
}
EOF

    echo "Full report written to: $AUDIT_OUTPUT"

    if [ "$flagged" -gt 0 ] || [ "$persistence_hits" -gt 0 ]; then
        log_auditor "node_process_auditor" "WARNING" "audit complete - $flagged flagged process(es), $persistence_hits persistence hit(s)"
        return 1
    else
        log_auditor "node_process_auditor" "INFO" "audit complete - all node-family processes look benign"
        return 0
    fi
}

main
