#!/bin/bash

# ===============================
# Advanced Algorithms & Optimizations
# High-performance utilities for Mac Guardian Suite
# ===============================

# Check bash version for associative array support (bash 4.0+)
BASH_MAJOR_VERSION=${BASH_VERSION%%.*}
BASH_MINOR_VERSION=${BASH_VERSION#*.}
BASH_MINOR_VERSION=${BASH_MINOR_VERSION%%.*}
HAS_ASSOC_ARRAYS=false

if [ "$BASH_MAJOR_VERSION" -ge 4 ] 2>/dev/null; then
    # Test if associative arrays actually work
    if declare -A test_array 2>/dev/null; then
        HAS_ASSOC_ARRAYS=true
    fi
fi

# Bloom filter for fast file existence checking
if [ "$HAS_ASSOC_ARRAYS" = true ]; then
    declare -A BLOOM_FILTER=()
else
    # Fallback: use file-based storage for older bash
    BLOOM_FILTER_FILE="${BLOOM_FILTER_FILE:-$HOME/.macguardian/bloom_filter.tmp}"
    touch "$BLOOM_FILTER_FILE" 2>/dev/null || true
fi
BLOOM_SIZE=10000

# Hash function for bloom filter
bloom_hash() {
    local key="$1"
    echo "$key" | shasum -a 256 | cut -d' ' -f1 | head -c 8
}

# Add to bloom filter
bloom_add() {
    local key="$1"
    local hash=$(bloom_hash "$key")
    if [ "$HAS_ASSOC_ARRAYS" = true ]; then
        BLOOM_FILTER["$hash"]=1
    else
        # Fallback: append to file
        echo "$hash" >> "$BLOOM_FILTER_FILE" 2>/dev/null || true
    fi
}

# Check bloom filter
bloom_check() {
    local key="$1"
    local hash=$(bloom_hash "$key")
    if [ "$HAS_ASSOC_ARRAYS" = true ]; then
        [ "${BLOOM_FILTER[$hash]:-0}" = "1" ]
    else
        # Fallback: grep file
        grep -q "^$hash$" "$BLOOM_FILTER_FILE" 2>/dev/null
    fi
}

# Advanced file metadata cache
if [ "$HAS_ASSOC_ARRAYS" = true ]; then
    declare -A FILE_CACHE=()
else
    # Fallback: FILE_CACHE will use file-based storage
    FILE_CACHE_ENABLED=false
fi
CACHE_FILE="${CACHE_FILE:-$HOME/.macguardian/file_cache.db}"

# Load cache
load_file_cache() {
    # Cache file is always used, regardless of associative array support
    # This function is a no-op for file-based cache (loaded on-demand)
    return 0
}

# Save cache
save_file_cache() {
    # For file-based cache, no action needed (always written immediately)
    if [ "$HAS_ASSOC_ARRAYS" = true ]; then
        > "$CACHE_FILE"
        for path in "${!FILE_CACHE[@]}"; do
            echo "$path|${FILE_CACHE[$path]}" >> "$CACHE_FILE"
        done
    fi
}

# Get cached file info or compute
get_file_info() {
    local file="$1"
    local cached=""
    
    if [ "$HAS_ASSOC_ARRAYS" = true ]; then
        cached="${FILE_CACHE[$file]:-}"
    else
        # Fallback: grep cache file
        cached=$(grep "^$file|" "$CACHE_FILE" 2>/dev/null | cut -d'|' -f2- || echo "")
    fi
    
    if [ -n "$cached" ]; then
        local mtime=$(stat -f %m "$file" 2>/dev/null || echo "0")
        local cached_mtime=$(echo "$cached" | cut -d'|' -f1)
        
        # Use cache if mtime matches
        if [ "$mtime" = "$cached_mtime" ]; then
            echo "$cached"
            return 0
        fi
    fi
    
    # Compute and cache
    local mtime=$(stat -f %m "$file" 2>/dev/null || echo "0")
    local size=$(stat -f %z "$file" 2>/dev/null || echo "0")
    local hash=$(shasum -a 256 "$file" 2>/dev/null | cut -d' ' -f1 || echo "")
    local cache_entry="$mtime|$size|$hash"
    
    if [ "$HAS_ASSOC_ARRAYS" = true ]; then
        FILE_CACHE["$file"]="$cache_entry"
    else
        # Fallback: append to cache file
        echo "$file|$cache_entry" >> "$CACHE_FILE" 2>/dev/null || true
    fi
    
    echo "$cache_entry"
}

# Incremental file hashing (only changed files)
incremental_hash() {
    local target_dir="$1"
    local baseline_file="$2"
    local output_file="$3"
    local exclude_dir="${4:-}"
    
    # Load baseline for lookup
    if [ "$HAS_ASSOC_ARRAYS" = true ]; then
        declare -A baseline_hashes=()
        if [ -f "$baseline_file" ]; then
            while IFS=' ' read -r hash filepath; do
                [ -n "$hash" ] && [ -n "$filepath" ] && baseline_hashes["$filepath"]="$hash"
            done < "$baseline_file"
        fi
    fi
    
    local changed=0
    local new=0
    local unchanged=0
    
    # Process files with optimized find
    while IFS= read -r -d '' file; do
        if [ ! -f "$file" ] || [ ! -r "$file" ]; then
            continue
        fi
        if [ -n "$exclude_dir" ] && [[ "$file" == "$exclude_dir"/* ]]; then
            continue
        fi
        
        local cached_info=$(get_file_info "$file")
        local current_mtime=$(echo "$cached_info" | cut -d'|' -f1)
        local current_hash=$(echo "$cached_info" | cut -d'|' -f3)
        
        local baseline_hash=""
        if [ "$HAS_ASSOC_ARRAYS" = true ]; then
            baseline_hash="${baseline_hashes[$file]:-}"
        else
            # Fallback: grep baseline file
            baseline_hash=$(grep "  $file$" "$baseline_file" 2>/dev/null | awk '{print $1}' || echo "")
        fi
        
        if [ -z "$baseline_hash" ]; then
            # New file
            echo "$current_hash  $file" >> "$output_file"
            new=$((new + 1))
        elif [ "$current_hash" != "$baseline_hash" ]; then
            # Changed file
            echo "$current_hash  $file" >> "$output_file"
            changed=$((changed + 1))
        else
            # Unchanged - reuse baseline hash
            echo "$baseline_hash  $file" >> "$output_file"
            unchanged=$((unchanged + 1))
        fi
    done < <(find "$target_dir" -type f -print0 2>/dev/null | sort -z)
    
    echo "$changed|$new|$unchanged"
}

# Optimized diff using hash comparison
fast_diff() {
    local file1="$1"
    local file2="$2"
    
    if [ "$HAS_ASSOC_ARRAYS" = true ]; then
        # Use associative arrays for O(1) lookup
        declare -A file1_hashes=()
        declare -A file2_hashes=()
        
        # Load file1
        while IFS=' ' read -r hash filepath; do
            [ -n "$hash" ] && [ -n "$filepath" ] && file1_hashes["$filepath"]="$hash"
        done < "$file1" 2>/dev/null
        
        # Load file2
        while IFS=' ' read -r hash filepath; do
            [ -n "$hash" ] && [ -n "$filepath" ] && file2_hashes["$filepath"]="$hash"
        done < "$file2" 2>/dev/null
        
        local added=()
        local removed=()
        local modified=()
        
        # Find added and modified files
        for filepath in "${!file2_hashes[@]}"; do
            if [ -z "${file1_hashes[$filepath]:-}" ]; then
                added+=("+ $filepath")
            elif [ "${file2_hashes[$filepath]}" != "${file1_hashes[$filepath]}" ]; then
                modified+=("~ $filepath")
            fi
        done
        
        # Find removed files
        for filepath in "${!file1_hashes[@]}"; do
            if [ -z "${file2_hashes[$filepath]:-}" ]; then
                removed+=("- $filepath")
            fi
        done
        
        # Output diff
        if [ ${#added[@]} -gt 0 ] || [ ${#removed[@]} -gt 0 ] || [ ${#modified[@]} -gt 0 ]; then
            printf '%s\n' "${added[@]}"
            printf '%s\n' "${removed[@]}"
            printf '%s\n' "${modified[@]}"
            return 1
        fi
    else
        # Fallback: use comm for diff (slower but compatible)
        local temp1=$(mktemp)
        local temp2=$(mktemp)
        sort "$file1" > "$temp1" 2>/dev/null || true
        sort "$file2" > "$temp2" 2>/dev/null || true
        comm -13 "$temp1" "$temp2" 2>/dev/null | sed 's/^/+ /' || true
        comm -23 "$temp1" "$temp2" 2>/dev/null | sed 's/^/- /' || true
        rm -f "$temp1" "$temp2"
        return 1
    fi
    
    return 0
}

# Aho-Corasick-like pattern matching (simplified for bash)
multi_pattern_match() {
    local text="$1"
    shift
    local patterns=("$@")
    
    # Build combined pattern for single pass
    local combined_pattern=$(IFS='|'; echo "${patterns[*]}")
    
    if echo "$text" | grep -qiE "$combined_pattern"; then
        return 0
    fi
    
    return 1
}

# Boyer-Moore-like string search (simplified)
fast_string_search() {
    local pattern="$1"
    local text="$2"
    
    # Use grep with optimized options
    echo "$text" | grep -F "$pattern" > /dev/null
}

# Optimized process search using pgrep
fast_process_search() {
    local pattern="$1"
    
    # Use pgrep for faster process matching
    if command -v pgrep &> /dev/null; then
        pgrep -fli "$pattern" 2>/dev/null | grep -v "pgrep\|grep" || true
    else
        # Fallback to ps
        ps aux | grep -iE "$pattern" | grep -v grep || true
    fi
}

# Binary search in sorted array (for large datasets)
binary_search() {
    local target="$1"
    shift
    local arr=("$@")
    
    local left=0
    local right=$((${#arr[@]} - 1))
    
    while [ $left -le $right ]; do
        local mid=$(((left + right) / 2))
        local mid_val="${arr[$mid]}"
        
        if [ "$mid_val" = "$target" ]; then
            return 0
        elif [ "$mid_val" \< "$target" ]; then
            left=$((mid + 1))
        else
            right=$((mid - 1))
        fi
    done
    
    return 1
}

# Optimized file find with exclusions
smart_find() {
    local target_dir="$1"
    shift
    local exclude_patterns=("$@")
    
    # Build find command with exclusions
    local find_cmd="find \"$target_dir\" -type f"
    
    for pattern in "${exclude_patterns[@]}"; do
        find_cmd="$find_cmd -not -path \"$pattern\""
    done
    
    # Use -print0 for null-separated output (more efficient)
    find_cmd="$find_cmd -print0"
    
    eval "$find_cmd" 2>/dev/null
}

# Batch file operations
batch_file_ops() {
    local operation="$1"
    local file_list="$2"
    local batch_size="${3:-100}"
    
    local count=0
    local batch=()
    
    while IFS= read -r file; do
        batch+=("$file")
        count=$((count + 1))
        
        if [ $count -ge $batch_size ]; then
            # Process batch
            for f in "${batch[@]}"; do
                eval "$operation \"$f\""
            done
            batch=()
            count=0
        fi
    done < "$file_list"
    
    # Process remaining
    for f in "${batch[@]}"; do
        eval "$operation \"$f\""
    done
}

# Memory-efficient large file processing
process_large_file() {
    local file="$1"
    local operation="$2"
    local chunk_size="${3:-8192}"
    
    # Process in chunks to avoid loading entire file
    local offset=0
    while true; do
        local chunk=$(dd if="$file" bs="$chunk_size" skip=$((offset / chunk_size)) count=1 2>/dev/null)
        [ -z "$chunk" ] && break
        
        eval "$operation \"$chunk\""
        offset=$((offset + chunk_size))
    done
}

# Optimized sorting for large datasets
external_sort() {
    local input_file="$1"
    local output_file="$2"
    local sort_key="${3:-1}"
    
    # Use system sort with optimized options
    sort -t'|' -k"$sort_key" -S 50% -T /tmp "$input_file" > "$output_file" 2>/dev/null || \
    sort -t'|' -k"$sort_key" "$input_file" > "$output_file"
}

# Hash table for O(1) lookups
if [ "$HAS_ASSOC_ARRAYS" = true ]; then
    declare -A HASH_TABLE=()
fi

hash_table_set() {
    local key="$1"
    local value="$2"
    if [ "$HAS_ASSOC_ARRAYS" = true ]; then
        HASH_TABLE["$key"]="$value"
    else
        # Fallback: use file-based storage
        local hash_file="${HASH_TABLE_FILE:-$HOME/.macguardian/hash_table.tmp}"
        echo "$key|$value" >> "$hash_file" 2>/dev/null || true
    fi
}

hash_table_get() {
    local key="$1"
    if [ "$HAS_ASSOC_ARRAYS" = true ]; then
        echo "${HASH_TABLE[$key]:-}"
    else
        # Fallback: grep file
        local hash_file="${HASH_TABLE_FILE:-$HOME/.macguardian/hash_table.tmp}"
        grep "^$key|" "$hash_file" 2>/dev/null | cut -d'|' -f2- || echo ""
    fi
}

hash_table_exists() {
    local key="$1"
    if [ "$HAS_ASSOC_ARRAYS" = true ]; then
        [ -n "${HASH_TABLE[$key]:-}" ]
    else
        # Fallback: grep file
        local hash_file="${HASH_TABLE_FILE:-$HOME/.macguardian/hash_table.tmp}"
        grep -q "^$key|" "$hash_file" 2>/dev/null
    fi
}

# LRU Cache implementation
if [ "$HAS_ASSOC_ARRAYS" = true ]; then
    declare -A LRU_CACHE=()
fi
declare -a LRU_ORDER=()
LRU_MAX_SIZE="${LRU_MAX_SIZE:-1000}"

lru_cache_get() {
    local key="$1"
    local value=""
    
    if [ "$HAS_ASSOC_ARRAYS" = true ]; then
        value="${LRU_CACHE[$key]:-}"
    else
        # Fallback: use file-based cache
        local lru_file="${LRU_CACHE_FILE:-$HOME/.macguardian/lru_cache.tmp}"
        value=$(grep "^$key|" "$lru_file" 2>/dev/null | cut -d'|' -f2- || echo "")
    fi
    
    if [ -n "$value" ]; then
        # Move to end (most recently used)
        if [ "$HAS_ASSOC_ARRAYS" = true ]; then
            LRU_ORDER=("${LRU_ORDER[@]/$key}")
            LRU_ORDER+=("$key")
        fi
        echo "$value"
        return 0
    fi
    
    return 1
}

lru_cache_set() {
    local key="$1"
    local value="$2"
    
    if [ "$HAS_ASSOC_ARRAYS" = true ]; then
        # Remove if exists
        LRU_ORDER=("${LRU_ORDER[@]/$key}")
        
        # Add to end
        LRU_ORDER+=("$key")
        LRU_CACHE["$key"]="$value"
        
        # Evict if over limit
        if [ ${#LRU_ORDER[@]} -gt $LRU_MAX_SIZE ]; then
            local oldest="${LRU_ORDER[0]}"
            unset LRU_CACHE["$oldest"]
            LRU_ORDER=("${LRU_ORDER[@]:1}")
        fi
    fi
}

# Optimized string operations
fast_string_replace() {
    local string="$1"
    local pattern="$2"
    local replacement="$3"
    
    # Use parameter expansion for simple cases
    echo "${string//$pattern/$replacement}"
}

# Efficient array operations
array_contains() {
    local target="$1"
    shift
    local arr=("$@")
    
    # Use pattern matching for O(n) but optimized
    local pattern=$(IFS='|'; echo "${arr[*]}")
    [[ "$target" =~ ^($pattern)$ ]]
}

# Set operations (union, intersection, difference)
array_union() {
    local -A seen=()
    local result=()
    
    for item in "$@"; do
        if [ -z "${seen[$item]:-}" ]; then
            seen["$item"]=1
            result+=("$item")
        fi
    done
    
    printf '%s\n' "${result[@]}"
}

array_intersection() {
    local arr1=("$@")
    local arr2_start=$(( ${#arr1[@]} + 1 ))
    local arr2=("${@:$arr2_start}")
    
    local -A seen1=()
    local result=()
    
    for item in "${arr1[@]}"; do
        seen1["$item"]=1
    done
    
    for item in "${arr2[@]}"; do
        if [ -n "${seen1[$item]:-}" ]; then
            result+=("$item")
        fi
    done
    
    printf '%s\n' "${result[@]}"
}

# ===============================
# Advanced Sorting Algorithms
# ===============================

# Parallel merge sort for large datasets
parallel_merge_sort() {
    local input_file="$1"
    local output_file="$2"
    local sort_key="${3:-1}"
    local max_parallel="${4:-${MAX_PARALLEL_JOBS:-4}}"
    
    if [ ! -f "$input_file" ]; then
        return 1
    fi
    
    local file_count=$(wc -l < "$input_file" | tr -d ' ')
    
    # For small files, use standard sort
    if [ "$file_count" -lt 10000 ]; then
        sort -t'|' -k"$sort_key" "$input_file" > "$output_file"
        return $?
    fi
    
    # For large files, use parallel sort
    if command -v gsort &> /dev/null; then
        gsort -t'|' -k"$sort_key" -S 50% --parallel="$max_parallel" "$input_file" > "$output_file" 2>/dev/null || \
        sort -t'|' -k"$sort_key" -S 50% "$input_file" > "$output_file"
    else
        sort -t'|' -k"$sort_key" -S 50% -T /tmp "$input_file" > "$output_file" 2>/dev/null || \
        sort -t'|' -k"$sort_key" "$input_file" > "$output_file"
    fi
}

# Process and sort files in parallel
process_and_sort_parallel() {
    local target_dir="$1"
    local process_func="$2"
    local sort_key="${3:-1}"
    local output_file="${4:-/dev/stdout}"
    
    local temp_dir=$(mktemp -d)
    local chunk_files=()
    local chunk_count=0
    
    # Process files in parallel chunks
    local chunk_size=1000
    local file_count=0
    local current_chunk="$temp_dir/chunk_0.txt"
    chunk_files+=("$current_chunk")
    > "$current_chunk"
    
    if [ "${QUIET:-false}" != true ]; then
        echo "Processing and sorting files in parallel..."
    fi
    
    # Process files and write to chunks
    while IFS= read -r -d '' file; do
        if [ -z "$file" ]; then continue; fi
        
        # Process file
        local result=$(eval "$process_func \"$file\"")
        
        if [ -n "$result" ]; then
            echo "$result" >> "$current_chunk"
            file_count=$((file_count + 1))
            
            # Start new chunk when size reached
            if [ $((file_count % chunk_size)) -eq 0 ]; then
                chunk_count=$((chunk_count + 1))
                current_chunk="$temp_dir/chunk_${chunk_count}.txt"
                chunk_files+=("$current_chunk")
                > "$current_chunk"
            fi
        fi
    done < <(find "$target_dir" -type f -print0 2>/dev/null)
    
    # Sort chunks in parallel
    local sorted_chunks=()
    for chunk_file in "${chunk_files[@]}"; do
        if [ -f "$chunk_file" ] && [ -s "$chunk_file" ]; then
            local sorted_chunk="${chunk_file}.sorted"
            (
                sort -t'|' -k"$sort_key" "$chunk_file" > "$sorted_chunk"
            ) &
            sorted_chunks+=("$sorted_chunk")
        fi
    done
    
    # Wait for all sorts to complete
    wait
    
    # Merge sorted chunks
    if [ ${#sorted_chunks[@]} -gt 0 ]; then
        sort -t'|' -k"$sort_key" -m "${sorted_chunks[@]}" > "$output_file"
    fi
    
    # Cleanup
    rm -rf "$temp_dir"
    
    if [ "${QUIET:-false}" != true ]; then
        echo "✅ Processed and sorted $file_count files"
    fi
}

# Parallel sort with progress
parallel_sort_with_progress() {
    local input_file="$1"
    local output_file="$2"
    local sort_key="${3:-1}"
    
    local total_lines=$(wc -l < "$input_file" | tr -d ' ')
    
    if [ "$total_lines" -lt 1000 ]; then
        sort -t'|' -k"$sort_key" "$input_file" > "$output_file"
        return $?
    fi
    
    # Large file - split, sort in parallel, merge
    local temp_dir=$(mktemp -d)
    local chunk_size=$((total_lines / ${MAX_PARALLEL_JOBS:-4} + 1))
    local chunk_num=0
    local line_count=0
    local current_chunk="$temp_dir/chunk_${chunk_num}.txt"
    > "$current_chunk"
    
    # Split into chunks
    while IFS= read -r line; do
        echo "$line" >> "$current_chunk"
        line_count=$((line_count + 1))
        
        if [ $line_count -ge $chunk_size ]; then
            chunk_num=$((chunk_num + 1))
            current_chunk="$temp_dir/chunk_${chunk_num}.txt"
            > "$current_chunk"
            line_count=0
        fi
    done < "$input_file"
    
    # Sort chunks in parallel
    local sorted_chunks=()
    for chunk_file in "$temp_dir"/chunk_*.txt; do
        if [ -f "$chunk_file" ] && [ -s "$chunk_file" ]; then
            local sorted_chunk="${chunk_file}.sorted"
            (
                sort -t'|' -k"$sort_key" "$chunk_file" > "$sorted_chunk"
            ) &
            sorted_chunks+=("$sorted_chunk")
        fi
    done
    
    wait
    
    # Merge sorted chunks
    if [ ${#sorted_chunks[@]} -gt 0 ]; then
        sort -t'|' -k"$sort_key" -m "${sorted_chunks[@]}" > "$output_file"
    fi
    
    rm -rf "$temp_dir"
}

# Memoization Cache
if [ "$HAS_ASSOC_ARRAYS" = true ]; then
    declare -A MEMO_CACHE=()
fi

memoize() {
    local func_name="$1"
    local key="$2"
    local cache_key="${func_name}_${key}"
    local cached=""
    
    if [ "$HAS_ASSOC_ARRAYS" = true ]; then
        cached="${MEMO_CACHE[$cache_key]:-}"
    else
        # Fallback: use file-based cache
        local memo_file="${MEMO_CACHE_FILE:-$HOME/.macguardian/memo_cache.tmp}"
        cached=$(grep "^$cache_key|" "$memo_file" 2>/dev/null | cut -d'|' -f2- || echo "")
    fi
    
    if [ -n "$cached" ]; then
        echo "$cached"
        return 0
    fi
    
    local result=$(eval "$func_name \"$key\"")
    
    if [ "$HAS_ASSOC_ARRAYS" = true ]; then
        MEMO_CACHE["$cache_key"]="$result"
    else
        # Fallback: append to file
        local memo_file="${MEMO_CACHE_FILE:-$HOME/.macguardian/memo_cache.tmp}"
        echo "$cache_key|$result" >> "$memo_file" 2>/dev/null || true
    fi
    
    echo "$result"
}

clear_memo_cache() {
    if [ "$HAS_ASSOC_ARRAYS" = true ]; then
        MEMO_CACHE=()
    else
        # Fallback: clear file
        local memo_file="${MEMO_CACHE_FILE:-$HOME/.macguardian/memo_cache.tmp}"
        > "$memo_file" 2>/dev/null || true
    fi
}

# Buffered writes
declare -a WRITE_BUFFER=()
WRITE_BUFFER_SIZE=1000

buffered_write() {
    local line="$1"
    local output_file="$2"
    
    WRITE_BUFFER+=("$line")
    
    if [ ${#WRITE_BUFFER[@]} -ge $WRITE_BUFFER_SIZE ]; then
        printf '%s\n' "${WRITE_BUFFER[@]}" >> "$output_file"
        WRITE_BUFFER=()
    fi
}

flush_buffer() {
    local output_file="$1"
    
    if [ ${#WRITE_BUFFER[@]} -gt 0 ]; then
        printf '%s\n' "${WRITE_BUFFER[@]}" >> "$output_file"
        WRITE_BUFFER=()
    fi
}

# Initialize algorithms
init_algorithms() {
    load_file_cache
    clear_memo_cache
}

# Cleanup algorithms
cleanup_algorithms() {
    save_file_cache
    flush_buffer ""
    clear_memo_cache
}
