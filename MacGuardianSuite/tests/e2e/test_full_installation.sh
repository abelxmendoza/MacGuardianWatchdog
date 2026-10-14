#!/bin/bash

# ===============================
# End-to-End Test: Full Installation
# Tests complete installation flow
# ===============================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUITE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEST_INSTALL_ROOT="$(mktemp -d)/macguardian_test_install"

# Run against a throwaway home folder: this test creates and deletes
# ~/.macguardian, which must never be the user's real data.
export HOME="$(mktemp -d)"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Cleanup function
cleanup() {
    echo "Cleaning up test installation..."
    rm -rf "$(dirname "$TEST_INSTALL_ROOT")" 2>/dev/null || true
    case "$HOME" in
        "${TMPDIR:-/tmp}"*|/tmp/*|/private/*) rm -rf "$HOME" 2>/dev/null || true ;;
    esac
}

trap cleanup EXIT

# Test installation
test_installation() {
    echo "Testing installation flow..."
    
    # Mock installer (simplified)
    mkdir -p "$TEST_INSTALL_ROOT"/{core,daemons,auditors}
    
    # Copy core files
    cp -r "$SUITE_DIR/core"/* "$TEST_INSTALL_ROOT/core/" 2>/dev/null || true
    
    # Verify installation
    if [ -d "$TEST_INSTALL_ROOT/core" ] && [ -f "$TEST_INSTALL_ROOT/core/validators.sh" ]; then
        echo -e "${GREEN}✅ Installation test passed${NC}"
        return 0
    else
        echo -e "${RED}❌ Installation test failed${NC}"
        return 1
    fi
}

# Test event generation
test_event_generation() {
    echo "Testing event generation..."
    
    mkdir -p "$HOME/.macguardian/events"
    
    # Source event writer
    source "$SUITE_DIR/daemons/event_writer.sh" 2>/dev/null || true
    
    # Generate test event
    write_event "process_anomaly" "medium" "test_module" '{"test": true}' 2>/dev/null || true
    
    sleep 1
    
    # Check if event was created
    if ls "$HOME/.macguardian/events/event_"*.json 2>/dev/null | head -1 | grep -q event_; then
        echo -e "${GREEN}✅ Event generation test passed${NC}"
        return 0
    else
        echo -e "${RED}❌ Event generation test failed${NC}"
        return 1
    fi
}

# Test event bus
test_event_bus() {
    echo "Testing event bus..."
    
    if python3 -c "import sys; sys.path.insert(0, '$SUITE_DIR/outputs'); from event_bus import EventBus" 2>/dev/null; then
        echo -e "${GREEN}✅ Event bus test passed${NC}"
        return 0
    else
        echo -e "${RED}❌ Event bus test failed${NC}"
        return 1
    fi
}

# Main
main() {
    echo "=========================================="
    echo "End-to-End Test: Full Installation"
    echo "=========================================="
    echo ""
    
    local passed=0
    local failed=0
    
    if test_installation; then
        passed=$((passed + 1))
    else
        failed=$((failed + 1))
    fi
    
    if test_event_generation; then
        passed=$((passed + 1))
    else
        failed=$((failed + 1))
    fi
    
    if test_event_bus; then
        passed=$((passed + 1))
    else
        failed=$((failed + 1))
    fi
    
    echo ""
    echo "=========================================="
    echo "E2E Test Summary"
    echo "=========================================="
    echo "Passed: $passed"
    echo "Failed: $failed"
    echo ""
    
    if [ $failed -eq 0 ]; then
        echo -e "${GREEN}✅ All E2E tests passed!${NC}"
        return 0
    else
        echo -e "${RED}❌ Some E2E tests failed${NC}"
        return 1
    fi
}

main "$@"

