#!/bin/bash
# Tests for self_check.sh: a clean install passes, and tampering is caught.
# Runs against a throwaway copy of the project and a throwaway $HOME, so it
# never touches the real ~/.macguardian or LaunchAgents.

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$TESTS_DIR/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

export HOME="$WORK/home"
mkdir -p "$HOME"
COPY="$WORK/project"
mkdir -p "$COPY"
rsync -a --exclude .git --exclude .build --exclude __pycache__ \
    "$PROJECT_ROOT/install.sh" "$PROJECT_ROOT/mac_suite.sh" "$PROJECT_ROOT/MacGuardianSuite" "$COPY/"
chmod -R go-w "$COPY"
CHECK="$COPY/MacGuardianSuite/self_check.sh"

failures=0
expect() {  # expect DESCRIPTION EXPECTED_EXIT ACTUAL_EXIT OUTPUT PATTERN
    local desc="$1" want="$2" got="$3" output="$4" pattern="$5"
    if [ "$got" = "$want" ] && grep -qE "$pattern" <<<"$output"; then
        echo "✅ $desc"
    else
        echo "❌ $desc (exit $got, wanted $want; looked for: $pattern)"
        echo "$output" | sed 's/^/     /'
        failures=$((failures + 1))
    fi
}

out="$(bash "$CHECK" 2>&1)"; code=$?
expect "No baseline yet is a warning, not a failure" 0 "$code" "$out" "WARN  No trusted baseline"

bash "$CHECK" --record >/dev/null
[ "$(stat -f '%Lp' "$HOME/.macguardian/install_manifest.sha256")" = "600" ] \
    && echo "✅ Baseline is private (600)" || { echo "❌ Baseline is not mode 600"; failures=$((failures + 1)); }

out="$(bash "$CHECK" 2>&1)"; code=$?
expect "Untouched install passes" 0 "$code" "$out" "PASS  All [0-9]+ scripts match"

echo "# tampered" >> "$COPY/MacGuardianSuite/utils.sh"
out="$(bash "$CHECK" 2>&1)"; code=$?
expect "Modified script is caught" 1 "$code" "$out" "FAIL  Changed since install: MacGuardianSuite/utils.sh"

bash "$CHECK" --record >/dev/null
printf '#!/bin/bash\necho hi\n' > "$COPY/MacGuardianSuite/dropped.sh"
out="$(bash "$CHECK" 2>&1)"; code=$?
expect "Script added after install is caught" 1 "$code" "$out" "FAIL  New script not present at install: MacGuardianSuite/dropped.sh"
rm "$COPY/MacGuardianSuite/dropped.sh"

chmod o+w "$COPY/MacGuardianSuite/config.sh"
out="$(bash "$CHECK" 2>&1)"; code=$?
expect "World-writable script is caught" 1 "$code" "$out" "FAIL  Files other users can modify"
chmod o-w "$COPY/MacGuardianSuite/config.sh"

mkdir -p "$HOME/Library/LaunchAgents"
cat > "$HOME/Library/LaunchAgents/com.macguardian.test.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>com.macguardian.test</string>
<key>ProgramArguments</key><array><string>/bin/bash</string><string>$HOME/Desktop/x/mac_watchdog.sh</string></array>
</dict></plist>
EOF
mkdir -p "$HOME/Desktop/x" && touch "$HOME/Desktop/x/mac_watchdog.sh"
out="$(bash "$CHECK" 2>&1)"; code=$?
expect "Background job running from Desktop is caught" 1 "$code" "$out" "FAIL  com.macguardian.test: runs from a folder macOS blocks"

echo ""
if [ "$failures" -eq 0 ]; then
    echo "All self-check tests passed"
else
    echo "$failures self-check test(s) failed"
    exit 1
fi
