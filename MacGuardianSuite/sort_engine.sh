#!/bin/bash

# ===============================
# Advanced Sorting Engine
# Parallel sorting with optimal algorithms
# ===============================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh" 2>/dev/null || true

# Sort files by various criteria in parallel
sort_files() {
    local target_dir="$1"
    local sort_by="${2:-size}"  # size, name, date, type
    local output_file="${3:-/dev/stdout}"
    local reverse="${4:-false}"
    
    local sort_option=""
    case "$sort_by" in
        size)
            sort_option="-S"  # Sort by size
            ;;
        name)
            sort_option=""  # Default alphabetical
            ;;
        date)
            sort_option="-t"  # Sort by modification time
            ;;
        type)
            sort_option="-X"  # Sort by extension
            ;;
    esac
    
    local reverse_flag=""
    if [ "$reverse" = "true" ]; then
        reverse_flag="-r"
    fi
    
    # Collect file info and sort
    {
        find "$target_dir" -type f -print0 2>/dev/null | while IFS= read -r -d '' file; do
            local size=$(stat -f %z "$file" 2>/dev/null || echo "0")
            local mtime=$(stat -f %m "$file" 2>/dev/null || echo "0")
            local ext="${file##*.}"
            local name=$(basename "$file")
            echo "$size|$mtime|$ext|$name|$file"
        done
    } | sort -t'|' -k1 -n $reverse_flag > "$output_file"
}

# Parallel sort large datasets
parallel_sort_large() {
    local input_file="$1"
    local output_file="$2"
    local sort_key="${3:-1}"
    
    if [ ! -f "$input_file" ]; then
        return 1
    fi
    
    local line_count=$(wc -l < "$input_file" | tr -d ' ')
    
    # Use system sort with parallel optimization
    if command -v gsort &> /dev/null; then
        # GNU sort with parallel support
        gsort --parallel="${MAX_PARALLEL_JOBS:-4}" -t'|' -k"$sort_key" "$input_file" > "$output_file"
    else
        # System sort with memory optimization
        sort -S 50% -T /tmp -t'|' -k"$sort_key" "$input_file" > "$output_file"
    fi
}

# Sort while processing (pipeline optimization)
sort_while_processing() {
    local process_func="$1"
    local sort_key="${2:-1}"
    local input_source="$3"
    
    # Process and pipe directly to sort (no intermediate file)
    eval "$process_func" < "$input_source" | sort -t'|' -k"$sort_key"
}

# Multi-criteria sort
multi_sort() {
    local input_file="$1"
    local output_file="$2"
    shift 2
    local sort_keys=("$@")
    
    # Build sort command with multiple keys
    local sort_cmd="sort"
    for key in "${sort_keys[@]}"; do
        sort_cmd="$sort_cmd -k$key"
    done
    
    $sort_cmd "$input_file" > "$output_file"
}

# Top-K elements (efficient for large datasets)
top_k() {
    local input_file="$1"
    local k="${2:-10}"
    local sort_key="${3:-1}"
    
    # Use heap-based selection for efficiency
    sort -t'|' -k"$sort_key" -r "$input_file" | head -n "$k"
}

# Bottom-K elements
bottom_k() {
    local input_file="$1"
    local k="${2:-10}"
    local sort_key="${3:-1}"
    
    sort -t'|' -k"$sort_key" "$input_file" | head -n "$k"
}

# Median finding (efficient algorithm)
find_median() {
    local input_file="$1"
    local sort_key="${2:-1}"
    
    local total=$(wc -l < "$input_file" | tr -d ' ')
    local median_pos=$((total / 2 + 1))
    
    sort -t'|' -k"$sort_key" -n "$input_file" | sed -n "${median_pos}p"
}

# Percentile calculation
percentile() {
    local input_file="$1"
    local percentile="${2:-50}"
    local sort_key="${3:-1}"
    
    local total=$(wc -l < "$input_file" | tr -d ' ')
    local pos=$((total * percentile / 100))
    
    sort -t'|' -k"$sort_key" -n "$input_file" | sed -n "${pos}p"
}

# CLI entry point. Keep this guarded so callers can source the sorting
# functions without accidentally executing the caller's positional arguments.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    if [ "${1:-}" = "--help" ]; then
        cat <<EOF
Advanced Sorting Engine

Usage: $0 [COMMAND] [ARGS]

Commands:
    sort_files DIR [by] [output] [reverse]
    parallel_sort_large INPUT OUTPUT [key]
    top_k INPUT K [key]
    bottom_k INPUT K [key]
    find_median INPUT [key]
    percentile INPUT PERCENT [key]

EOF
        exit 0
    fi

    # Run command if provided
    if [ $# -gt 0 ]; then
        "$@"
    fi
fi
