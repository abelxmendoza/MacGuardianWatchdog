#!/bin/bash

# ===============================
# Node Panic Kill
# Immediately kills every live node/npm/npx/corepack/node-gyp process
# (the exact set node_process_auditor.sh flags) and records enough detail
# per process - path, args, cwd - to relaunch it later from the review UI.
#
# This is deliberately silent and JSON-only on stdout/stderr: it is meant
# to be invoked by the desktop app's panic button and parsed programmatically.
# Event Spec v1.0.0 compliant.
# ===============================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUITE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SUITE_DIR/core/validators.sh" 2>/dev/null || true
source "$SUITE_DIR/core/logging.sh" 2>/dev/null || true
source "$SUITE_DIR/daemons/event_writer.sh" 2>/dev/null || true

# This must never crash mid-kill and leave half a session unrecorded.
set +e

type log_auditor &>/dev/null || log_auditor() { :; }
type write_event &>/dev/null || write_event() { :; }

SESSION_DIR="$HOME/.macguardian/panic_sessions"
mkdir -p "$SESSION_DIR"
SESSION_ID="panic_$(date +%Y%m%d_%H%M%S)"
SESSION_FILE="$SESSION_DIR/${SESSION_ID}.json"

json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    printf '%s' "$s"
}

get_cwd() {
    local pid="$1"
    # lsof -Fn output is 3 lines: "p<pid>", "fcwd", "n<path>" - we want the last.
    lsof -p "$pid" -a -d cwd -Fn 2>/dev/null | sed -n '3p' | cut -c2-
}

# Sends TERM, gives the process up to ~0.5s to exit cleanly, then KILLs it.
# Prints one of: TERM | TERM,KILL | FAILED
kill_and_wait() {
    local pid="$1"
    kill -TERM "$pid" 2>/dev/null

    local i=0
    while [ $i -lt 5 ]; do
        if ! kill -0 "$pid" 2>/dev/null; then
            echo "TERM"
            return
        fi
        sleep 0.1
        i=$((i + 1))
    done

    kill -KILL "$pid" 2>/dev/null
    sleep 0.1
    if kill -0 "$pid" 2>/dev/null; then
        echo "FAILED"
    else
        echo "TERM,KILL"
    fi
}

main() {
    local all_pids
    all_pids=$(ps -Ao pid= 2>/dev/null)

    local -a entries=()
    local killed_count=0

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

        local ppid full_args cwd
        ppid=$(ps -p "$pid" -o ppid= 2>/dev/null | tr -d ' \t')
        full_args=$(ps -p "$pid" -o args= 2>/dev/null | sed 's/^[ \t]*//;s/[ \t]*$//')
        cwd=$(get_cwd "$pid")

        # Best-effort argv[1:] for relaunching: split on whitespace and drop
        # the first token (argv[0] as invoked, which may differ from the
        # resolved `comm` path). This is lossy for args containing literal
        # spaces, but real node/npm invocations essentially never have any.
        set -f
        local -a arg_tokens=($full_args)
        set +f
        local -a rest_args=("${arg_tokens[@]:1}")

        local args_json="[]"
        if [ "${#rest_args[@]}" -gt 0 ]; then
            local -a parts=()
            for a in "${rest_args[@]}"; do
                parts+=("\"$(json_escape "$a")\"")
            done
            local IFS=,
            args_json="[${parts[*]}]"
            unset IFS
        fi

        local signal_result
        signal_result=$(kill_and_wait "$pid")
        local terminated="true"
        [ "$signal_result" = "FAILED" ] && terminated="false"
        killed_count=$((killed_count + 1))

        entries+=("$(printf '{"pid": %s, "ppid": %s, "path": "%s", "args": %s, "full_command": "%s", "cwd": "%s", "signal_sequence": "%s", "terminated": %s}' \
            "$pid" "${ppid:-0}" "$(json_escape "$comm")" "$args_json" "$(json_escape "$full_args")" "$(json_escape "$cwd")" "$signal_result" "$terminated")")

        log_auditor "node_panic_kill" "WARNING" "killed pid=$pid path=$comm signals=$signal_result"
    done <<< "$all_pids"

    local entries_json="[]"
    if [ "${#entries[@]}" -gt 0 ]; then
        local IFS=,
        entries_json="[${entries[*]}]"
        unset IFS
    fi

    cat > "$SESSION_FILE" <<EOF
{
  "session_id": "$SESSION_ID",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "killed_count": $killed_count,
  "killed": $entries_json
}
EOF

    local event_context
    event_context=$(printf '{"action": "panic_kill", "killed_count": %s, "session_id": "%s"}' "$killed_count" "$(json_escape "$SESSION_ID")")
    write_event "process_anomaly" "low" "node_panic_kill" "$event_context"
    log_auditor "node_panic_kill" "INFO" "panic kill session complete: $killed_count process(es) killed"

    cat "$SESSION_FILE"
}

main
