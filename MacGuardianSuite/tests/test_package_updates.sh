#!/bin/bash

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TESTS_DIR/../package_updates.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

BIN="$WORK/bin"
LOG="$WORK/calls.log"
mkdir -p "$BIN"

cat > "$BIN/brew" <<'EOF'
#!/bin/bash
echo "brew $*" >> "$CALL_LOG"
case "$*" in
    "outdated --formula --quiet") printf 'alpha\nbeta\n' ;;
    "outdated --cask --greedy --quiet") printf 'app-one\napp-two\n' ;;
esac
exit 0
EOF

cat > "$BIN/mas" <<'EOF'
#!/bin/bash
echo "mas $*" >> "$CALL_LOG"
case "$1" in
    outdated) echo "123 Example App (1.0 -> 2.0)" ;;
esac
exit 0
EOF
chmod +x "$BIN/brew" "$BIN/mas"

failures=0
expect_call() {
    local expected="$1"
    if grep -Fxq "$expected" "$LOG"; then
        echo "✅ $expected"
    else
        echo "❌ missing call: $expected"
        failures=$((failures + 1))
    fi
}

export CALL_LOG="$LOG"
PATH="$BIN:/usr/bin:/bin" bash "$SCRIPT" all --yes >/dev/null

expect_call "brew update"
expect_call "brew outdated --formula --quiet"
expect_call "brew outdated --cask --greedy --quiet"
expect_call "brew upgrade --formula --no-ask alpha"
expect_call "brew upgrade --formula --no-ask beta"
expect_call "brew upgrade --cask --greedy --no-ask app-one"
expect_call "brew upgrade --cask --greedy --no-ask app-two"
expect_call "mas outdated"
expect_call "mas upgrade"
expect_call "brew cleanup"

echo ""
if [ "$failures" -gt 0 ]; then
    echo "$failures package update test(s) failed"
    exit 1
fi
echo "All package update tests passed"
