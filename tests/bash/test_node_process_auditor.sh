#!/bin/bash

# ===============================
# Node Process Auditor Test Suite
# ===============================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
AUDITOR_SCRIPT="$PROJECT_ROOT/MacGuardianSuite/auditors/node_process_auditor.sh"

# Test colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Test counter
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

test_runs_without_crashing() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Test: Auditor runs to completion... "

    # Exit code 0 (all benign) or 1 (something flagged) are both valid outcomes;
    # anything else (crash, signal) is a failure. The exit code must be
    # captured in the else-branch: `$?` after a bodyless `if` with no matching
    # branch taken reflects the if-statement itself (always 0), not the
    # condition command's real status.
    local exit_code
    if bash "$AUDITOR_SCRIPT" > /dev/null 2>&1; then
        exit_code=0
    else
        exit_code=$?
    fi

    if [ "$exit_code" -eq 0 ] || [ "$exit_code" -eq 1 ]; then
        echo -e "${GREEN}PASS${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    fi

    echo -e "${RED}FAIL (exit code: $exit_code)${NC}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    return 1
}

test_audit_output_written() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Test: Audit output file written... "

    local audit_files
    audit_files=$(find "$HOME/.macguardian/audits" -name "node_process_audit_*.json" -type f 2>/dev/null | wc -l | tr -d ' ')

    if [ "$audit_files" -gt 0 ]; then
        echo -e "${GREEN}PASS${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    fi

    echo -e "${RED}FAIL${NC}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    return 1
}

test_json_output_valid() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Test: JSON output is well-formed... "

    local latest_audit
    latest_audit=$(find "$HOME/.macguardian/audits" -name "node_process_audit_*.json" -type f -print0 2>/dev/null \
        | xargs -0 ls -t 2>/dev/null | head -1)

    if [ -n "$latest_audit" ] && python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$latest_audit" 2>/dev/null; then
        echo -e "${GREEN}PASS${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    fi

    echo -e "${RED}FAIL${NC}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    return 1
}

test_no_stray_state_files() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Test: No leftover temp state files... "

    local strays
    strays=$(find "$HOME/.macguardian/audits" -name ".node_process_auditor.*" -type f 2>/dev/null | wc -l | tr -d ' ')

    if [ "$strays" -eq 0 ]; then
        echo -e "${GREEN}PASS${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    fi

    echo -e "${RED}FAIL (found $strays stray file(s))${NC}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    return 1
}

echo "=========================================="
echo "Node Process Auditor Test Suite"
echo "=========================================="
echo ""

test_runs_without_crashing
test_audit_output_written
test_json_output_valid
test_no_stray_state_files

echo ""
echo "=========================================="
echo "Test Summary"
echo "=========================================="
echo "Tests run: $TESTS_RUN"
echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failed: ${RED}$TESTS_FAILED${NC}"

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed${NC}"
    exit 1
fi
