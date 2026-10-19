#!/bin/bash

# ===============================
# Input Validation Module
# Production-grade input sanitization and validation
# ===============================

set -euo pipefail

# Validation result codes
VALIDATION_SUCCESS=0
VALIDATION_FAILURE=1

# ===============================
# Path Validation
# ===============================

validate_path() {
    local path="$1"
    local allow_relative="${2:-false}"
    
    # Check if path is empty
    if [ -z "$path" ]; then
        return $VALIDATION_FAILURE
    fi
    
    # Check for null bytes (injection attempt)
    if echo "$path" | grep -q $'\0'; then
        return $VALIDATION_FAILURE
    fi
    
    # Check for command injection patterns
    if echo "$path" | grep -qE '[;&|`$()]'; then
        return $VALIDATION_FAILURE
    fi
    
    # Check for path traversal attempts
    if echo "$path" | grep -qE '\.\./|\.\.\\'; then
        return $VALIDATION_FAILURE
    fi
    
    # If relative paths not allowed, check for absolute path
    if [ "$allow_relative" = "false" ] && [[ ! "$path" = /* ]]; then
        return $VALIDATION_FAILURE
    fi
    
    return $VALIDATION_SUCCESS
}

# ===============================
# Email Validation
# ===============================

validate_email() {
    local email="$1"
    
    if [ -z "$email" ]; then
        return $VALIDATION_FAILURE
    fi
    
    # Basic email regex (RFC 5322 simplified)
    if echo "$email" | grep -qE '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'; then
        return $VALIDATION_SUCCESS
    fi
    
    return $VALIDATION_FAILURE
}

# ===============================
# Integer Validation
# ===============================

validate_int() {
    local value="$1"
    local min="${2:-}"
    local max="${3:-}"
    
    if [ -z "$value" ]; then
        return $VALIDATION_FAILURE
    fi
    
    # Check if it's a valid integer
    if ! echo "$value" | grep -qE '^-?[0-9]+$'; then
        return $VALIDATION_FAILURE
    fi
    
    # Check min if provided
    if [ -n "$min" ] && [ "$value" -lt "$min" ]; then
        return $VALIDATION_FAILURE
    fi
    
    # Check max if provided
    if [ -n "$max" ] && [ "$value" -gt "$max" ]; then
        return $VALIDATION_FAILURE
    fi
    
    return $VALIDATION_SUCCESS
}

# ===============================
# Enum Validation
# ===============================

validate_enum() {
    local value="$1"
    local valid_values="$2"
    
    if [ -z "$value" ] || [ -z "$valid_values" ]; then
        return $VALIDATION_FAILURE
    fi
    
    # Check if value is in the valid set
    IFS='|' read -ra VALUES <<< "$valid_values"
    for valid_value in "${VALUES[@]}"; do
        if [ "$value" = "$valid_value" ]; then
            return $VALIDATION_SUCCESS
        fi
    done
    
    return $VALIDATION_FAILURE
}

# ===============================
# UUID Validation
# ===============================

validate_uuid() {
    local uuid="$1"
    
    if [ -z "$uuid" ]; then
        return $VALIDATION_FAILURE
    fi
    
    # UUID v4 format
    if echo "$uuid" | grep -qE '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'; then
        return $VALIDATION_SUCCESS
    fi
    
    return $VALIDATION_FAILURE
}

# ===============================
# ISO8601 Timestamp Validation
# ===============================

validate_timestamp() {
    local timestamp="$1"
    
    if [ -z "$timestamp" ]; then
        return $VALIDATION_FAILURE
    fi
    
    # ISO8601 format: YYYY-MM-DDTHH:MM:SSZ or with milliseconds
    if echo "$timestamp" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]{1,3})?Z?$'; then
        return $VALIDATION_SUCCESS
    fi
    
    return $VALIDATION_FAILURE
}

# ===============================
# Severity Validation
# ===============================

validate_severity() {
    local severity="$1"
    validate_enum "$severity" "low|medium|high|critical"
}

# ===============================
# Event Type Validation
# ===============================

validate_event_type() {
    local event_type="$1"
    local valid_types="process_anomaly|network_connection|dns_request|file_integrity_change|cron_modification|ssh_key_change|tcc_permission_change|user_account_change|signature_hit|ids_alert|privacy_event|ransomware_activity|persistence_change|config_change"
    
    validate_enum "$event_type" "$valid_types"
}

# ===============================
# Safe Temporary File Creation
# ===============================

safe_tempfile() {
    local prefix="${1:-macguardian}"
    local suffix="${2:-tmp}"
    local temp_dir="${TMPDIR:-/tmp}"
    
    # Validate temp directory
    if ! validate_path "$temp_dir" false; then
        temp_dir="/tmp"
    fi
    
    # Create secure temp file
    local temp_file
    temp_file=$(mktemp -t "${prefix}.XXXXXX.${suffix}" 2>/dev/null || mktemp "${temp_dir}/${prefix}.XXXXXX.${suffix}")
    
    # Set secure permissions (read/write for owner only)
    chmod 600 "$temp_file" 2>/dev/null || true
    
    echo "$temp_file"
}

# ===============================
# Safe Command Array Construction
# ===============================

# Example usage:
# cmd_array=()
# cmd_array+=("command")
# cmd_array+=("--flag")
# cmd_array+=("$validated_value")
# safe_execute "${cmd_array[@]}"

safe_execute() {
    local cmd=("$@")
    
    if [ ${#cmd[@]} -eq 0 ]; then
        return $VALIDATION_FAILURE
    fi
    
    # Validate first element is a valid command path
    if ! validate_path "${cmd[0]}" false; then
        return $VALIDATION_FAILURE
    fi
    
    # Execute command
    "${cmd[@]}"
}

# Export functions for use in other scripts
export -f validate_path
export -f validate_email
export -f validate_int
export -f validate_enum
export -f validate_uuid
export -f validate_timestamp
export -f validate_severity
export -f validate_event_type
export -f safe_tempfile
export -f safe_execute

