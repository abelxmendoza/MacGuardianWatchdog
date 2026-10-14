#!/bin/bash

# ===============================
# MacGuardian Test Runner
# Runs all tests in the test suite
# ===============================

set -euo pipefail

# Tests write and read ~/.macguardian; keep them away from the real one.
export HOME="$(mktemp -d)"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SUITE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Test results
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0

# ===============================
# Test Functions
# ===============================

run_test_file() {
    local test_file="$1"
    local test_name=$(basename "$test_file")
    
    echo -e "${YELLOW}Running: $test_name${NC}"
    
    # Check if it's a BATS test file
    if grep -q "^#!/usr/bin/env bats\|^@test\|^load" "$test_file" 2>/dev/null; then
        if command -v bats &> /dev/null; then
            # Set up test environment
            export PROJECT_ROOT="$PROJECT_ROOT"
            export TEST_DIR=$(mktemp -d)
            export SUITE_DIR="$SUITE_DIR"
            
            if bats "$test_file" 2>&1; then
                echo -e "${GREEN}✅ PASSED: $test_name${NC}"
                PASSED_TESTS=$((PASSED_TESTS + 1))
            else
                echo -e "${RED}❌ FAILED: $test_name${NC}"
                FAILED_TESTS=$((FAILED_TESTS + 1))
            fi
            TOTAL_TESTS=$((TOTAL_TESTS + 1))
            rm -rf "$TEST_DIR" 2>/dev/null || true
        else
            echo -e "${YELLOW}⚠️  SKIPPED: $test_name (BATS not installed)${NC}"
            SKIPPED_TESTS=$((SKIPPED_TESTS + 1))
            TOTAL_TESTS=$((TOTAL_TESTS + 1))
        fi
    else
        # Regular bash test file
        export PROJECT_ROOT="$PROJECT_ROOT"
        export TEST_DIR=$(mktemp -d)
        export SUITE_DIR="$SUITE_DIR"
        
        if bash -n "$test_file" 2>/dev/null; then
            if bash "$test_file" 2>&1; then
                echo -e "${GREEN}✅ PASSED: $test_name${NC}"
                PASSED_TESTS=$((PASSED_TESTS + 1))
            else
                echo -e "${RED}❌ FAILED: $test_name${NC}"
                FAILED_TESTS=$((FAILED_TESTS + 1))
            fi
        else
            echo -e "${RED}❌ SYNTAX ERROR: $test_name${NC}"
            FAILED_TESTS=$((FAILED_TESTS + 1))
        fi
        
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
        rm -rf "$TEST_DIR" 2>/dev/null || true
    fi
    
    echo ""
}

run_manual_test() {
    local test_name="$1"
    local test_command="$2"
    
    echo -e "${YELLOW}Running: $test_name${NC}"
    
    export PROJECT_ROOT="$PROJECT_ROOT"
    export TEST_DIR=$(mktemp -d)
    export SUITE_DIR="$SUITE_DIR"
    
    local result
    result=$(eval "$test_command" 2>&1)
    local exit_code=$?
    
    if echo "$result" | grep -q "PASS" || [ $exit_code -eq 0 ]; then
        echo -e "${GREEN}✅ PASSED: $test_name${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}❌ FAILED: $test_name${NC}"
        echo "  Output: $result"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    rm -rf "$TEST_DIR" 2>/dev/null || true
    echo ""
}

# ===============================
# Unit Tests
# ===============================

run_unit_tests() {
    echo "=========================================="
    echo "Unit Tests"
    echo "=========================================="
    echo ""
    
    # Validators tests
    if [ -f "$SCRIPT_DIR/unit/test_validators.sh" ]; then
        run_test_file "$SCRIPT_DIR/unit/test_validators.sh"
    fi
    
    # System state tests
    if [ -f "$SCRIPT_DIR/unit/test_system_state.sh" ]; then
        run_test_file "$SCRIPT_DIR/unit/test_system_state.sh"
    fi
    
    # Hashing tests
    if [ -f "$SCRIPT_DIR/unit/test_hashing.sh" ]; then
        run_test_file "$SCRIPT_DIR/unit/test_hashing.sh"
    fi

    # Homebrew, cask, and Mac App Store update command coverage
    if [ -f "$SCRIPT_DIR/test_package_updates.sh" ]; then
        run_test_file "$SCRIPT_DIR/test_package_updates.sh"
    fi
    
    # Manual validator tests (if bats not available)
    echo "Running manual validator tests..."
    run_manual_test "validate_path - valid path" "source '$SUITE_DIR/core/validators.sh' 2>/dev/null && validate_path '/usr/bin/test' 2>/dev/null && echo 'PASS' || echo 'FAIL'"
    run_manual_test "validate_path - injection attempt" "source '$SUITE_DIR/core/validators.sh' 2>/dev/null && (validate_path '/path; rm -rf /' 2>/dev/null && echo 'FAIL' || echo 'PASS')"
    run_manual_test "validate_email - valid email" "source '$SUITE_DIR/core/validators.sh' 2>/dev/null && validate_email 'test@example.com' 2>/dev/null && echo 'PASS' || echo 'FAIL'"
    run_manual_test "validate_int - valid integer" "source '$SUITE_DIR/core/validators.sh' 2>/dev/null && validate_int '42' 2>/dev/null && echo 'PASS' || echo 'FAIL'"
    run_manual_test "validate_severity - valid severity" "source '$SUITE_DIR/core/validators.sh' 2>/dev/null && validate_severity 'high' 2>/dev/null && echo 'PASS' || echo 'FAIL'"
    run_manual_test "validate_event_type - valid event type" "source '$SUITE_DIR/core/validators.sh' 2>/dev/null && validate_event_type 'process_anomaly' 2>/dev/null && echo 'PASS' || echo 'FAIL'"
}

# ===============================
# Integration Tests
# ===============================

run_integration_tests() {
    echo "=========================================="
    echo "Integration Tests"
    echo "=========================================="
    echo ""
    
    # Event pipeline tests
    if [ -f "$SCRIPT_DIR/integration/test_event_pipeline.sh" ]; then
        run_test_file "$SCRIPT_DIR/integration/test_event_pipeline.sh"
    fi
    
    # Watcher output tests
    if [ -f "$SCRIPT_DIR/integration/test_watcher_output.sh" ]; then
        run_test_file "$SCRIPT_DIR/integration/test_watcher_output.sh"
    fi
    
    # Manual event writer test
    echo "Testing event_writer.sh..."
    mkdir -p "$HOME/.macguardian/events" 2>/dev/null || true
    run_manual_test "event_writer - Event Spec v1.0.0" "source '$SUITE_DIR/daemons/event_writer.sh' 2>/dev/null && write_event 'process_anomaly' 'medium' 'test_module' '{\"test\": true}' 2>/dev/null && sleep 1 && ls \"\$HOME/.macguardian/events/event_\"*.json 2>/dev/null | head -1 | grep -q event_ && echo 'PASS' || echo 'FAIL'"
    
    # Test Event Spec v1.0.0 validation
    run_manual_test "Event Spec - required fields" "source '$SUITE_DIR/core/validators.sh' 2>/dev/null && source '$SUITE_DIR/daemons/event_writer.sh' 2>/dev/null && write_event 'network_connection' 'high' 'test_module' '{}' 2>/dev/null && sleep 1 && event_file=\$(ls -t \"\$HOME/.macguardian/events/event_\"*.json 2>/dev/null | head -1) && [ -n \"\$event_file\" ] && grep -q '\"event_id\"' \"\$event_file\" && grep -q '\"event_type\"' \"\$event_file\" && grep -q '\"severity\"' \"\$event_file\" && grep -q '\"timestamp\"' \"\$event_file\" && grep -q '\"source\"' \"\$event_file\" && grep -q '\"context\"' \"\$event_file\" && echo 'PASS' || echo 'FAIL'"
}

# ===============================
# Syntax Validation Tests
# ===============================

run_syntax_tests() {
    echo "=========================================="
    echo "Syntax Validation Tests"
    echo "=========================================="
    echo ""
    
    local syntax_errors=0
    
    # Test core modules
    for script in "$SUITE_DIR/core"/*.sh; do
        if [ -f "$script" ]; then
            if bash -n "$script" 2>&1; then
                echo -e "${GREEN}✅ $(basename "$script")${NC}"
            else
                echo -e "${RED}❌ $(basename "$script")${NC}"
                syntax_errors=$((syntax_errors + 1))
            fi
        fi
    done
    
    # Test daemons
    for script in "$SUITE_DIR/daemons"/*.sh; do
        if [ -f "$script" ]; then
            if bash -n "$script" 2>&1; then
                echo -e "${GREEN}✅ $(basename "$script")${NC}"
            else
                echo -e "${RED}❌ $(basename "$script")${NC}"
                syntax_errors=$((syntax_errors + 1))
            fi
        fi
    done
    
    # Test auditors
    for script in "$SUITE_DIR/auditors"/*.sh; do
        if [ -f "$script" ]; then
            if bash -n "$script" 2>&1; then
                echo -e "${GREEN}✅ $(basename "$script")${NC}"
            else
                echo -e "${RED}❌ $(basename "$script")${NC}"
                syntax_errors=$((syntax_errors + 1))
            fi
        fi
    done
    
    echo ""
    if [ $syntax_errors -eq 0 ]; then
        echo -e "${GREEN}✅ All scripts passed syntax validation${NC}"
    else
        echo -e "${RED}❌ $syntax_errors script(s) failed syntax validation${NC}"
        FAILED_TESTS=$((FAILED_TESTS + syntax_errors))
    fi
    
    TOTAL_TESTS=$((TOTAL_TESTS + syntax_errors))
    echo ""
}

# ===============================
# Python Tests
# ===============================

run_python_tests() {
    echo "=========================================="
    echo "Python Tests"
    echo "=========================================="
    echo ""
    
    if command -v python3 &> /dev/null; then
        # Test event_bus.py syntax
        if python3 -m py_compile "$SUITE_DIR/outputs/event_bus.py" 2>&1; then
            echo -e "${GREEN}✅ event_bus.py syntax valid${NC}"
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            echo -e "${RED}❌ event_bus.py syntax error${NC}"
            FAILED_TESTS=$((FAILED_TESTS + 1))
        fi
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
        
        # Test Python imports
        if python3 -c "import sys; sys.path.insert(0, '$SUITE_DIR/outputs'); from event_bus import EventBus" 2>&1; then
            echo -e "${GREEN}✅ event_bus.py imports successfully${NC}"
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            echo -e "${RED}❌ event_bus.py import failed${NC}"
            FAILED_TESTS=$((FAILED_TESTS + 1))
        fi
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
        
        echo ""
    else
        echo -e "${YELLOW}⚠️  Python3 not found, skipping Python tests${NC}"
        echo ""
    fi
}

# ===============================
# Main
# ===============================

main() {
    echo "=========================================="
    echo "MacGuardian Watchdog Test Suite"
    echo "=========================================="
    echo ""
    
    run_syntax_tests
    run_unit_tests
    run_integration_tests
    run_python_tests
    
    echo "=========================================="
    echo "Test Summary"
    echo "=========================================="
    echo ""
    echo "Total Tests: $TOTAL_TESTS"
    echo -e "${GREEN}Passed: $PASSED_TESTS${NC}"
    echo -e "${RED}Failed: $FAILED_TESTS${NC}"
    echo -e "${YELLOW}Skipped: $SKIPPED_TESTS${NC}"
    echo ""
    
    if [ $FAILED_TESTS -eq 0 ]; then
        echo -e "${GREEN}✅ All tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}❌ Some tests failed${NC}"
        exit 1
    fi
}

main "$@"

