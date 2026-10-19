#!/bin/bash

# ===============================
# Persistence Watcher
# Detects new, changed and removed startup items (LaunchAgents,
# LaunchDaemons, StartupItems, shell profiles) and checks the code
# signature of whatever each one runs.
# Event Spec v1.0.0 compliant
#
# Usage (standalone):
#   persistence_watcher.sh scan       # list every startup item with its signer
#   persistence_watcher.sh check      # compare against baseline, write events
#   persistence_watcher.sh baseline   # accept the current state as the baseline
# When sourced, exports detect_persistence_changes for the monitor loop.
# ===============================

PERSISTENCE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PERSISTENCE_SUITE_DIR="$(cd "$PERSISTENCE_SCRIPT_DIR/.." && pwd)"

source "$PERSISTENCE_SUITE_DIR/core/validators.sh" 2>/dev/null || true
source "$PERSISTENCE_SUITE_DIR/core/logging.sh" 2>/dev/null || true
source "$PERSISTENCE_SCRIPT_DIR/event_writer.sh" 2>/dev/null || true

# Fall back to a no-op if logging.sh isn't available.
type log_watcher &> /dev/null || log_watcher() { :; }

# Configuration (colon-separated lists, overridable for tests)
PERSISTENCE_DIRS="${MG_PERSISTENCE_DIRS:-$HOME/Library/LaunchAgents:/Library/LaunchAgents:/Library/LaunchDaemons:/Library/StartupItems}"
PERSISTENCE_PROFILES="${MG_PERSISTENCE_PROFILES:-$HOME/.zshrc:$HOME/.zshenv:$HOME/.zprofile:$HOME/.zlogin:$HOME/.bashrc:$HOME/.bash_profile:$HOME/.profile:/etc/zshrc:/etc/zprofile:/etc/profile}"
PERSISTENCE_BASELINE="${MG_PERSISTENCE_BASELINE:-$HOME/.macguardian/baselines/persistence_baseline.tsv}"
PERSISTENCE_CHECK_INTERVAL="${MG_PERSISTENCE_CHECK_INTERVAL:-60}"
PERSISTENCE_LAST_CHECK="$HOME/.macguardian/.persistence_last_check"
PERSISTENCE_FINGERPRINT="$HOME/.macguardian/.persistence_fingerprint"

# Command lines that download, decode or run inline code
PERSISTENCE_SUSPICIOUS_REGEX='curl |wget |base64 (-d|--decode|-D)|osascript -e|python[0-9.]* -c|perl -e|ruby -e|(ba|z)?sh -c|nc -|ncat |/dev/tcp/|eval |chmod \+x'

# Places legitimate software almost never runs from
PERSISTENCE_RISKY_PATH_REGEX='^(/tmp/|/private/tmp/|/var/tmp/|/private/var/tmp/|/Users/Shared/|/var/folders/|/private/var/folders/)|/\.[^/]+/[^/]+$'

# Interpreters whose script argument is the real program
PERSISTENCE_INTERPRETER_REGEX='/(ba|z|k|c|tc|da)?sh$|/(python|python3|perl|ruby|node|osascript|php)[0-9.]*$'

# ===============================
# Helpers
# ===============================

_persistence_json_escape() {
    printf '%s' "$1" | perl -pe 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g; s/\r/\\r/g; s/\n/\\n/g; s/[\x00-\x1f]//g'
}

_persistence_hash() {
    shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'
}

# Full command line of a launchd plist, one string
_persistence_plist_command() {
    local plist="$1"
    local program args
    program=$(plutil -extract Program raw -o - "$plist" 2>/dev/null || true)
    args=$(plutil -extract ProgramArguments json -o - "$plist" 2>/dev/null \
        | perl -MJSON::PP -0777 -ne 'print join(" ", @{decode_json($_)})' 2>/dev/null || true)
    if [ -n "$program" ] && [ -n "$args" ]; then
        printf '%s %s' "$program" "$args"
    else
        printf '%s' "${program:-$args}"
    fi
}

# The executable a plist actually runs. For interpreters, the script they run.
_persistence_plist_executable() {
    local plist="$1"
    local program arg0 arg1
    program=$(plutil -extract Program raw -o - "$plist" 2>/dev/null || true)
    arg0=$(plutil -extract ProgramArguments.0 raw -o - "$plist" 2>/dev/null || true)
    [ -z "$program" ] && program="$arg0"
    # launchd looks bare names up in its default PATH
    if [ -n "$program" ] && [[ "$program" != /* ]]; then
        program=$(PATH=/usr/bin:/bin:/usr/sbin:/sbin command -v "$program" 2>/dev/null || printf '%s' "$program")
    fi

    if [[ "$program" =~ $PERSISTENCE_INTERPRETER_REGEX ]]; then
        # First argument after the interpreter that isn't a flag
        local i=1
        while arg1=$(plutil -extract "ProgramArguments.$i" raw -o - "$plist" 2>/dev/null); do
            if [[ "$arg1" != -* ]]; then
                printf '%s' "$arg1"
                return 0
            fi
            # An inline script (-c / -e) has no file to check
            if [[ "$arg1" =~ ^-(c|e)$ ]]; then
                printf '%s' "$program"
                return 0
            fi
            i=$((i + 1))
        done
    fi
    printf '%s' "$program"
}

# Prints "status<TAB>signer" for an executable.
# status: apple | developer_id | app_store | adhoc | unsigned | invalid | missing | script | none
_persistence_signature() {
    local target="$1"

    if [ -z "$target" ]; then
        printf 'none\t-'
        return 0
    fi
    if [ ! -e "$target" ]; then
        printf 'missing\t-'
        return 0
    fi

    # Use the enclosing .app bundle if there is one
    local bundle="$target"
    if [[ "$target" == *.app/Contents/* ]]; then
        bundle="${target%.app/Contents/*}.app"
    fi

    local info
    info=$(codesign -dvv "$bundle" 2>&1 || true)

    if [[ "$info" == *"not signed at all"* ]]; then
        # Plain-text scripts are normally unsigned
        if file -b "$target" 2>/dev/null | grep -qiE 'text|script'; then
            printf 'script\t-'
        else
            printf 'unsigned\t-'
        fi
        return 0
    fi

    # Not --strict: it rejects Finder metadata that doesn't affect the code
    if ! codesign --verify "$bundle" &> /dev/null; then
        printf 'invalid\t-'
        return 0
    fi

    # Here-strings, not pipes: awk exiting early would SIGPIPE the writer,
    # which fails the assignment when the caller has set -e and pipefail.
    local authority team
    authority=$(awk -F= '/^Authority=/{print $2; exit}' <<< "$info")
    team=$(awk -F= '/^TeamIdentifier=/{print $2; exit}' <<< "$info")

    if [[ "$info" == *"Signature=adhoc"* ]]; then
        printf 'adhoc\t-'
    elif [[ "$authority" == "Software Signing" || "$authority" == "macOS Software Signing" ]]; then
        printf 'apple\tApple'
    elif [[ "$authority" == Developer\ ID\ Application:* ]]; then
        # Authority already ends with the team ID
        printf 'developer_id\t%s' "${authority#Developer ID Application: }"
    elif [[ "$authority" == "Apple Mac OS Application Signing" ]]; then
        printf 'app_store\t%s' "${team:-App Store}"
    else
        printf 'developer_id\t%s' "${authority:-unknown}${team:+ ($team)}"
    fi
}

# ===============================
# Inventory
# One TSV row per item: kind, path, sha256, executable, sig_status, signer, command
# ===============================

get_persistence_items() {
    local IFS=':'
    local dirs=($PERSISTENCE_DIRS)
    local profiles=($PERSISTENCE_PROFILES)
    unset IFS

    local dir plist
    for dir in "${dirs[@]}"; do
        [ -d "$dir" ] || continue
        # fd 4 so the commands below can't eat the file list
        while IFS= read -r plist <&4; do
            [ -n "$plist" ] || continue
            local kind="launchd" hash exe cmd sig
            if [ "$(basename "$plist")" = "StartupParameters.plist" ]; then
                # Legacy StartupItem: the script named after its folder runs at boot
                kind="startupitem"
                exe="$(dirname "$plist")/$(basename "$(dirname "$plist")")"
                cmd="$exe"
                hash=$(cat "$plist" "$exe" 2>/dev/null | shasum -a 256 | awk '{print $1}')
            else
                hash=$(_persistence_hash "$plist")
                exe=$(_persistence_plist_executable "$plist")
                cmd=$(_persistence_plist_command "$plist" | tr '\t\n' '  ')
            fi
            sig=$(_persistence_signature "$exe")
            printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$kind" "$plist" "${hash:--}" "${exe:--}" "$sig" "${cmd:--}"
        done 4< <(find "$dir" -maxdepth 2 -name '*.plist' -type f 2>/dev/null | sort)
    done

    local profile
    for profile in "${profiles[@]}"; do
        [ -f "$profile" ] || continue
        printf 'profile\t%s\t%s\t-\tscript\t-\t-\n' "$profile" "$(_persistence_hash "$profile")"
    done
}

# Severity for an item that just appeared or changed. Prints "severity<TAB>reasons".
_persistence_assess() {
    local kind="$1" path="$2" exe="$3" status="$4" cmd="$5"
    local severity="low"
    local reasons=()

    _raise() {
        case "$1:$severity" in
            critical:*|high:low|high:medium|medium:low) severity="$1" ;;
        esac
    }

    if [ "$kind" = "profile" ]; then
        _raise medium
        reasons+=("shell profile changed")
        if grep -qE "$PERSISTENCE_SUSPICIOUS_REGEX" "$path" 2>/dev/null; then
            _raise high
            reasons+=("profile downloads or runs inline code")
        fi
    else
        case "$status" in
            unsigned) _raise high;   reasons+=("program is unsigned") ;;
            invalid)  _raise high;   reasons+=("program signature is invalid") ;;
            adhoc)
                if [[ "$exe" == /opt/homebrew/* || "$exe" == /usr/local/* ]]; then
                    _raise medium; reasons+=("ad-hoc signed Homebrew program")
                else
                    _raise high;   reasons+=("program is ad-hoc signed")
                fi ;;
            missing)  _raise medium; reasons+=("program does not exist") ;;
            script)   _raise medium; reasons+=("runs an unsigned script") ;;
        esac
        if [[ "$exe" =~ $PERSISTENCE_RISKY_PATH_REGEX ]]; then
            _raise high
            reasons+=("runs from a temporary, shared or hidden location")
        fi
        if [[ "$cmd" =~ $PERSISTENCE_SUSPICIOUS_REGEX ]]; then
            _raise high
            reasons+=("command downloads, decodes or runs inline code")
        fi
        if [[ "$path" == /Library/LaunchDaemons/* ]] && [ "$severity" = "high" ]; then
            # Runs as root
            _raise critical
            reasons+=("runs as root")
        fi
    fi

    local joined=""
    local r
    for r in "${reasons[@]+"${reasons[@]}"}"; do
        joined="${joined:+$joined; }$r"
    done
    printf '%s\t%s' "$severity" "${joined:-signed by a known developer}"
}

_persistence_emit() {
    local change="$1" severity="$2" kind="$3" path="$4" exe="$5" status="$6" signer="$7" cmd="$8" reasons="$9"
    local context
    context=$(printf '{"change_type": "%s", "item_kind": "%s", "path": "%s", "executable": "%s", "signature_status": "%s", "signer": "%s", "command": "%s", "reasons": "%s"}' \
        "$change" "$kind" \
        "$(_persistence_json_escape "$path")" \
        "$(_persistence_json_escape "$exe")" \
        "$status" \
        "$(_persistence_json_escape "$signer")" \
        "$(_persistence_json_escape "$cmd")" \
        "$(_persistence_json_escape "$reasons")")

    if type write_event &> /dev/null; then
        write_event "persistence_change" "$severity" "persistence_watcher" "$context" || true
    fi
    log_watcher "persistence_watcher" "WARNING" "Startup item $change ($severity): $path — $reasons"
    echo "[$severity] $change: $path ($reasons)"
}

# ===============================
# Baseline and detection
# ===============================

create_persistence_baseline() {
    mkdir -p "$(dirname "$PERSISTENCE_BASELINE")"
    local tmp="$PERSISTENCE_BASELINE.tmp.$$"
    get_persistence_items > "$tmp"
    mv "$tmp" "$PERSISTENCE_BASELINE"
    chmod 600 "$PERSISTENCE_BASELINE" 2>/dev/null || true
    log_watcher "persistence_watcher" "INFO" "Persistence baseline created with $(wc -l < "$PERSISTENCE_BASELINE" | tr -d ' ') items"
}

# Compares the current state against the baseline, writes an event per
# change, then makes the current state the new baseline.
check_persistence_changes() {
    if [ ! -f "$PERSISTENCE_BASELINE" ]; then
        create_persistence_baseline
        return 0
    fi

    local current="$PERSISTENCE_BASELINE.current.$$"
    get_persistence_items > "$current"

    local kind path hash exe status signer cmd
    local old_hash old_status

    # Loops read on fd 3 so nothing they call (write_event) can eat their input.
    # Added and modified
    while IFS=$'\t' read -r kind path hash exe status signer cmd <&3; do
        [ -n "$path" ] || continue
        local old
        old=$(awk -F'\t' -v p="$path" '$2 == p {print $3 "\t" $5; exit}' "$PERSISTENCE_BASELINE")
        if [ -z "$old" ]; then
            local assessed
            assessed=$(_persistence_assess "$kind" "$path" "$exe" "$status" "$cmd")
            _persistence_emit added "${assessed%%$'\t'*}" "$kind" "$path" "$exe" "$status" "$signer" "$cmd" "${assessed#*$'\t'}"
            continue
        fi
        old_hash="${old%%$'\t'*}"
        old_status="${old#*$'\t'}"
        if [ "$hash" != "$old_hash" ]; then
            local assessed reasons
            assessed=$(_persistence_assess "$kind" "$path" "$exe" "$status" "$cmd")
            reasons="${assessed#*$'\t'}"
            if [ "$status" != "$old_status" ]; then
                reasons="signature went from $old_status to $status; $reasons"
            fi
            local sev="${assessed%%$'\t'*}"
            [ "$sev" = "low" ] && sev="medium"
            _persistence_emit modified "$sev" "$kind" "$path" "$exe" "$status" "$signer" "$cmd" "$reasons"
        fi
    done 3< "$current"

    # Removed
    while IFS=$'\t' read -r kind path hash exe status signer cmd <&3; do
        [ -n "$path" ] || continue
        if ! awk -F'\t' -v p="$path" '$2 == p {found=1; exit} END {exit !found}' "$current"; then
            _persistence_emit removed low "$kind" "$path" "$exe" "$status" "$signer" "$cmd" "startup item removed"
        fi
    done 3< "$PERSISTENCE_BASELINE"

    mv "$current" "$PERSISTENCE_BASELINE"
    chmod 600 "$PERSISTENCE_BASELINE" 2>/dev/null || true
}

# Rate-limited entry point for the monitor loop
detect_persistence_changes() {
    local now last
    now=$(date +%s)
    last=$(cat "$PERSISTENCE_LAST_CHECK" 2>/dev/null || echo 0)
    if [ $((now - last)) -lt "$PERSISTENCE_CHECK_INTERVAL" ]; then
        return 0
    fi
    mkdir -p "$(dirname "$PERSISTENCE_LAST_CHECK")"
    echo "$now" > "$PERSISTENCE_LAST_CHECK"

    # Full checks run codesign on every item, so only do one when a watched
    # file, or a program the baseline says an item runs, has changed.
    local fingerprint previous
    fingerprint=$(_persistence_fingerprint)
    previous=$(cat "$PERSISTENCE_FINGERPRINT" 2>/dev/null || true)
    if [ -f "$PERSISTENCE_BASELINE" ] && [ "$fingerprint" = "$previous" ]; then
        return 0
    fi
    check_persistence_changes
    _persistence_fingerprint > "$PERSISTENCE_FINGERPRINT"
}

# Cheap summary of everything a full check looks at: names, sizes and
# modification times of watched files and of the programs they run.
_persistence_fingerprint() {
    local IFS=':'
    local paths=($PERSISTENCE_DIRS $PERSISTENCE_PROFILES)
    unset IFS
    {
        local p
        for p in "${paths[@]}"; do
            if [ -d "$p" ]; then
                find "$p" -maxdepth 2 -type f -exec stat -f '%N %m %z' {} + 2>/dev/null
            elif [ -e "$p" ]; then
                stat -f '%N %m %z' "$p" 2>/dev/null
            fi
        done
        if [ -f "$PERSISTENCE_BASELINE" ]; then
            awk -F'\t' '$4 != "-" {print $4}' "$PERSISTENCE_BASELINE" | sort -u | while IFS= read -r exe; do
                stat -f '%N %m %z' "$exe" 2>/dev/null || echo "$exe absent"
            done
        fi
    } | shasum -a 256 | awk '{print $1}'
}

# Human-readable inventory, KnockKnock style
print_persistence_inventory() {
    local kind path hash exe status signer cmd
    local flagged=0 total=0
    while IFS=$'\t' read -r kind path hash exe status signer cmd <&3; do
        [ -n "$path" ] || continue
        total=$((total + 1))
        local mark="  "
        case "$status" in
            unsigned|invalid|adhoc|missing) mark="⚠️"; flagged=$((flagged + 1)) ;;
        esac
        if [ "$kind" = "profile" ]; then
            printf '%s %-12s %s\n' "$mark" "profile" "$path"
        else
            printf '%s %-12s %s\n' "$mark" "$status" "$path"
            local who=""
            [ "$signer" != "-" ] && who="  [$signer]"
            printf '     runs: %s%s\n' "$exe" "$who"
        fi
    done 3< <(get_persistence_items)
    echo
    echo "$total startup items, $flagged need a look (unsigned, ad-hoc, invalid or missing program)."
}

export -f detect_persistence_changes check_persistence_changes _persistence_fingerprint create_persistence_baseline get_persistence_items \
    _persistence_assess _persistence_emit _persistence_signature _persistence_plist_executable \
    _persistence_plist_command _persistence_hash _persistence_json_escape > /dev/null 2>&1 || true

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    set -uo pipefail
    case "${1:-scan}" in
        scan)     print_persistence_inventory ;;
        check)    check_persistence_changes ;;
        baseline) create_persistence_baseline; echo "Baseline saved to $PERSISTENCE_BASELINE" ;;
        *)        echo "Usage: $0 [scan|check|baseline]" >&2; exit 2 ;;
    esac
fi
