#!/bin/bash

# MacGuardian startup items: see and switch background helpers that start with your Mac.
#
#   startup_items.sh list [--all] [--json]   Optional helpers (every item with --all)
#   startup_items.sh off|on <group|label>    Switch a group or one launchd label
#   startup_items.sh trim                    Turn off every optional helper group
#   startup_items.sh groups                  List group names
#
# Options: -y/--yes skip confirmation · -n/--dry-run print commands only
# Groups: adobe edge google zoom java xquartz openvpn
# Apple, security tools, MacGuardian, Homebrew, Docker, VPN and Tailscale items are never switched.
# System-wide daemons need your password (sudo); everything else runs as you.

set -uo pipefail

DRY_RUN=false
ASSUME_YES=false
JSON=false
SHOW_ALL=false
SUDO="${MG_SUDO:-sudo}"
UID_NUM="$(id -u)"
USER_AGENTS="${MG_USER_AGENTS:-$HOME/Library/LaunchAgents}"
GLOBAL_AGENTS="${MG_GLOBAL_AGENTS:-/Library/LaunchAgents}"
GLOBAL_DAEMONS="${MG_GLOBAL_DAEMONS:-/Library/LaunchDaemons}"
STARTUP_GROUPS=(adobe edge google zoom java xquartz openvpn)
PROTECTED='^(com\.apple\.|com\.objective-see\.|com\.malwarebytes\.|com\.macguardian\.|com\.abel\.|sh\.brew\.|homebrew\.|com\.docker\.|com\.tailscale\.|io\.tailscale\.|ch\.protonvpn\.|com\.protonvpn\.)'

group_pattern() {
    case "$1" in
        adobe)   echo '^com\.adobe\.' ;;
        edge)    echo '^com\.microsoft\.EdgeUpdater' ;;
        google)  echo '^com\.google\.(keystone|GoogleUpdater)' ;;
        zoom)    echo '^us\.zoom\.' ;;
        java)    echo '^com\.oracle\.java\.' ;;
        xquartz) echo '^org\.xquartz\.' ;;
    esac
}

group_title() {
    case "$1" in
        adobe)   echo "Adobe Creative Cloud helpers" ;;
        edge)    echo "Microsoft Edge updater" ;;
        google)  echo "Google updater" ;;
        zoom)    echo "Zoom updater and daemon" ;;
        java)    echo "Oracle Java helper" ;;
        xquartz) echo "XQuartz (X11) launcher" ;;
        openvpn) echo "OpenVPN Connect (login item)" ;;
    esac
}

# Groups that are login items rather than launchd jobs: "<name>|<app path>"
login_item_for() {
    case "$1" in
        openvpn) echo "OpenVPN Connect|/Applications/OpenVPN Connect.app" ;;
    esac
}

is_group() {
    local g
    for g in "${STARTUP_GROUPS[@]}"; do [ "$g" = "$1" ] && return 0; done
    return 1
}

group_of() {
    local g p
    for g in "${STARTUP_GROUPS[@]}"; do
        p="$(group_pattern "$g")"
        [ -n "$p" ] && echo "$1" | grep -Eq "$p" && { echo "$g"; return 0; }
    done
    echo ""
}

# Every launchd item, one per line: scope|label|plist
items() {
    local pair scope dir f label
    for pair in "user:$USER_AGENTS" "agent:$GLOBAL_AGENTS" "daemon:$GLOBAL_DAEMONS"; do
        scope="${pair%%:*}"; dir="${pair#*:}"
        [ -d "$dir" ] || continue
        for f in "$dir"/*.plist; do
            [ -f "$f" ] || continue
            label=""
            command -v plutil >/dev/null 2>&1 && label="$(plutil -extract Label raw -o - "$f" 2>/dev/null)"
            [ -n "$label" ] || label="$(basename "$f" .plist)"
            echo "$scope|$label|$f"
        done
    done
}

domain_for() { [ "$1" = daemon ] && echo system || echo "gui/$UID_NUM"; }

refresh_disabled() {
    DISABLED_GUI="$(launchctl print-disabled "gui/$UID_NUM" 2>/dev/null)"
    DISABLED_SYS="$(launchctl print-disabled system 2>/dev/null)"
}

item_state() {
    local scope="$1" label="$2" text
    [ "$scope" = daemon ] && text="$DISABLED_SYS" || text="$DISABLED_GUI"
    if echo "$text" | grep -Eq "\"$label\" => (disabled|true)"; then echo off; else echo on; fi
}

login_items() { osascript -e 'tell application "System Events" to get the name of every login item' 2>/dev/null; }

login_item_state() {
    login_items | tr ',' '\n' | sed 's/^ *//' | grep -Fxq "$1" && echo on || echo off
}

run() {
    echo "  \$ $*"
    [ "$DRY_RUN" = true ] && return 0
    "$@"
}

confirm() {
    [ "$ASSUME_YES" = true ] || [ "$DRY_RUN" = true ] && return 0
    if [ ! -t 0 ]; then
        echo "Refusing to change startup items without a terminal. Re-run with --yes to confirm." >&2
        return 1
    fi
    local reply
    read -r -p "$1 [y/N] " reply
    [[ "$reply" =~ ^[Yy]$ ]]
}

apply_item() {
    local scope="$1" label="$2" plist="$3" want="$4" domain prefix=()
    domain="$(domain_for "$scope")"
    [ "$scope" = daemon ] && prefix=("$SUDO")
    if [ "$want" = off ]; then
        run ${prefix[@]+"${prefix[@]}"} launchctl disable "$domain/$label" || return 1
        run ${prefix[@]+"${prefix[@]}"} launchctl bootout "$domain/$label" 2>/dev/null || true
    else
        run ${prefix[@]+"${prefix[@]}"} launchctl enable "$domain/$label" || return 1
        run ${prefix[@]+"${prefix[@]}"} launchctl bootstrap "$domain" "$plist" 2>/dev/null || true
    fi
}

set_login_item() {
    local group="$1" want="$2" spec name app
    spec="$(login_item_for "$group")"; name="${spec%%|*}"; app="${spec#*|}"
    if [ "$(login_item_state "$name")" = "$want" ]; then
        echo "✅ $name is already $want at login"; return 0
    fi
    if [ "$want" = on ] && [ ! -d "$app" ]; then
        echo "⚠️  $app isn't installed" >&2; return 1
    fi
    echo "$(group_title "$group"): turn $want at login"
    confirm "Turn $name $want at login?" || { echo "Skipped $name"; return 0; }
    if [ "$want" = off ]; then
        run osascript -e "tell application \"System Events\" to delete login item \"$name\"" || return 1
    else
        run osascript -e "tell application \"System Events\" to make login item at end with properties {path:\"$app\", hidden:false}" || return 1
    fi
    [ "$DRY_RUN" = true ] || echo "✅ $name is now $want at login"
}

# Switch every launchd item in a list of "scope|label|plist" lines.
set_items() {
    local want="$1" title="$2" lines="$3" line scope label plist pending="" n=0 rc=0
    refresh_disabled
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        IFS='|' read -r scope label plist <<< "$line"
        [ "$(item_state "$scope" "$label")" = "$want" ] && continue
        pending="$pending$line"$'\n'; n=$((n + 1))
    done <<< "$lines"
    if [ "$n" -eq 0 ]; then echo "✅ $title: already $want"; return 0; fi
    echo "$title: $n item(s) to turn $want"
    while IFS='|' read -r scope label plist; do
        [ -n "$label" ] && echo "   • $label ($scope)"
    done <<< "$pending"
    confirm "Turn these $want?" || { echo "Skipped $title"; return 0; }
    while IFS='|' read -r scope label plist; do
        [ -n "$label" ] || continue
        apply_item "$scope" "$label" "$plist" "$want" || { echo "⚠️  Couldn't switch $label" >&2; rc=1; }
    done <<< "$pending"
    [ "$DRY_RUN" = true ] && return $rc
    refresh_disabled
    while IFS='|' read -r scope label plist; do
        [ -n "$label" ] || continue
        if [ "$(item_state "$scope" "$label")" = "$want" ]; then echo "✅ $label is now $want"
        else echo "⚠️  $label still reads $(item_state "$scope" "$label")" >&2; rc=1; fi
    done <<< "$pending"
    return $rc
}

set_group() {
    local group="$1" want="$2" pattern matches
    if [ -n "$(login_item_for "$group")" ]; then set_login_item "$group" "$want"; return; fi
    pattern="$(group_pattern "$group")"
    matches="$(items | awk -F'|' -v p="$pattern" '$2 ~ p')"
    if [ -z "$matches" ]; then echo "✅ $(group_title "$group"): nothing installed"; return 0; fi
    set_items "$want" "$(group_title "$group")" "$matches"
}

set_label() {
    local label="$1" want="$2" match
    if echo "$label" | grep -Eq "$PROTECTED"; then
        echo "Refusing to switch $label: it belongs to macOS, a security tool, MacGuardian, Homebrew, Docker or your VPN." >&2
        return 2
    fi
    match="$(items | awk -F'|' -v l="$label" '$2 == l')"
    if [ -z "$match" ]; then echo "No startup item labelled '$label'. See: macguardian startup list --all" >&2; return 2; fi
    set_items "$want" "$label" "$match"
}

json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

list_items() {
    local line scope label plist group state protected first=true g spec name
    refresh_disabled
    [ "$JSON" = true ] && printf '['
    [ "$JSON" = true ] || { echo "Startup items$([ "$SHOW_ALL" = true ] || echo " (optional helpers; --all shows everything)")"; echo "----------------------------------------"; }
    while IFS='|' read -r scope label plist; do
        [ -n "$label" ] || continue
        group="$(group_of "$label")"
        [ "$SHOW_ALL" = true ] || [ -n "$group" ] || continue
        state="$(item_state "$scope" "$label")"
        echo "$label" | grep -Eq "$PROTECTED" && protected=true || protected=false
        if [ "$JSON" = true ]; then
            [ "$first" = true ] || printf ','; first=false
            printf '{"label":"%s","group":"%s","scope":"%s","state":"%s","protected":%s}' \
                "$(json_escape "$label")" "$group" "$scope" "$state" "$protected"
        else
            printf '  %-4s %-8s %-7s %s%s\n' "$state" "${group:--}" "$scope" "$label" "$([ "$protected" = true ] && echo "  (protected)")"
        fi
    done <<< "$(items)"
    for g in "${STARTUP_GROUPS[@]}"; do
        spec="$(login_item_for "$g")"; [ -n "$spec" ] || continue
        name="${spec%%|*}"; state="$(login_item_state "$name")"
        if [ "$JSON" = true ]; then
            [ "$first" = true ] || printf ','; first=false
            printf '{"label":"%s","group":"%s","scope":"login","state":"%s","protected":false}' "$(json_escape "$name")" "$g" "$state"
        else
            printf '  %-4s %-8s %-7s %s\n' "$state" "$g" "login" "$name"
        fi
    done
    if [ "$JSON" = true ]; then printf ']\n'; else
        broken_links
        echo ""; echo "Turn a group off: macguardian startup off <group>   ·   all optional helpers: macguardian startup trim"
    fi
}

# Startup entries whose target was uninstalled: they can't run, but they're clutter.
broken_links() {
    local dir f shown=false
    for dir in "$USER_AGENTS" "$GLOBAL_AGENTS" "$GLOBAL_DAEMONS"; do
        [ -d "$dir" ] || continue
        for f in "$dir"/*.plist; do
            [ -L "$f" ] && [ ! -e "$f" ] || continue
            [ "$shown" = true ] || { echo ""; echo "Leftover links (their app was removed; safe to delete):"; shown=true; }
            echo "  $f"
            case "$f" in "$HOME"/*) echo "     rm \"$f\"" ;; *) echo "     sudo rm \"$f\"" ;; esac
        done
    done
}

trim() {
    local g rc=0
    for g in "${STARTUP_GROUPS[@]}"; do set_group "$g" off || rc=1; done
    return $rc
}

usage() { sed -n '3,14p' "$0" | sed 's/^# \{0,1\}//'; }

ARGS=()
while [ "$#" -gt 0 ]; do
    case "$1" in
        -y|--yes)     ASSUME_YES=true ;;
        -n|--dry-run) DRY_RUN=true ;;
        --json)       JSON=true ;;
        --all)        SHOW_ALL=true ;;
        -h|--help)    usage; exit 0 ;;
        *)            ARGS+=("$1") ;;
    esac
    shift
done

ACTION="${ARGS[0]:-list}"
case "$ACTION" in
    list|status) list_items ;;
    groups) for g in "${STARTUP_GROUPS[@]}"; do printf '%-8s %s\n' "$g" "$(group_title "$g")"; done ;;
    trim) trim ;;
    on|off)
        TARGET="${ARGS[1]:-}"
        [ -n "$TARGET" ] || { echo "Say which group or label. Groups: ${STARTUP_GROUPS[*]}" >&2; exit 2; }
        if is_group "$TARGET"; then set_group "$TARGET" "$ACTION"; else set_label "$TARGET" "$ACTION"; fi ;;
    *) usage >&2; exit 2 ;;
esac
