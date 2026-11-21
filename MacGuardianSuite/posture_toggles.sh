#!/bin/bash

# MacGuardian posture toggles: see and switch common macOS hardening controls.
#
#   posture_toggles.sh status [--json]     Show every control and whether it's in the safe state
#   posture_toggles.sh on|off <control>    Switch one control
#   posture_toggles.sh harden              Put every control in its safe state
#   posture_toggles.sh list                List control names
#
# Options: -y/--yes skip confirmation · -n/--dry-run print commands only
# Changes that macOS protects ask for your password (sudo / sysadminctl).

set -uo pipefail

CONTROLS=(ssh screenlock airplay powernap netwake extensions)
DRY_RUN=false
ASSUME_YES=false
JSON=false
SUDO="${MG_SUDO:-sudo}"

label() {
    case "$1" in
        ssh)        echo "Remote Login (SSH)" ;;
        screenlock) echo "Lock screen immediately" ;;
        airplay)    echo "AirPlay Receiver" ;;
        powernap)   echo "Power Nap" ;;
        netwake)    echo "Wake for network access" ;;
        extensions) echo "Show all filename extensions" ;;
    esac
}

# The state each control should be in on a hardened Mac.
safe_state() {
    case "$1" in
        ssh|airplay|powernap|netwake) echo off ;;
        screenlock|extensions)        echo on ;;
    esac
}

settings_hint() {
    case "$1" in
        ssh)        echo "System Settings > General > Sharing > Remote Login" ;;
        screenlock) echo "System Settings > Lock Screen > Require password after screen saver begins or display is turned off" ;;
        airplay)    echo "System Settings > General > AirDrop & Handoff > AirPlay Receiver" ;;
        powernap)   echo "System Settings > Battery > Options > Enable Power Nap" ;;
        netwake)    echo "System Settings > Battery > Options > Wake for network access" ;;
        extensions) echo "Finder > Settings > Advanced > Show all filename extensions" ;;
    esac
}

is_control() {
    local c
    for c in "${CONTROLS[@]}"; do [ "$c" = "$1" ] && return 0; done
    return 1
}

# ---- Read current state (no privileges needed) ----------------------------
current_state() {
    case "$1" in
        ssh)
            nc -z -G 2 127.0.0.1 22 >/dev/null 2>&1 && echo on || echo off ;;
        screenlock)
            sysadminctl -screenLock status 2>&1 | grep -qE 'immediate|delay is [0-5] seconds' && echo on || echo off ;;
        airplay)
            lsof -nP -iTCP:7000 -sTCP:LISTEN 2>/dev/null | grep -q ControlCe && echo on || echo off ;;
        powernap)
            pmset -g custom 2>/dev/null | awk '/powernap/ && $2==1 {f=1} END {exit !f}' && echo on || echo off ;;
        netwake)
            pmset -g custom 2>/dev/null | awk '/womp/ && $2==1 {f=1} END {exit !f}' && echo on || echo off ;;
        extensions)
            defaults read NSGlobalDomain AppleShowAllExtensions 2>/dev/null | grep -q 1 && echo on || echo off ;;
    esac
}

# ---- Change state ---------------------------------------------------------
run() {
    echo "  \$ $*"
    [ "$DRY_RUN" = true ] && return 0
    "$@"
}

apply() {
    local control="$1" want="$2" bool num
    [ "$want" = on ] && { bool=true; num=1; } || { bool=false; num=0; }
    case "$control" in
        ssh)
            # systemsetup needs Full Disk Access for the terminal on recent macOS.
            run "$SUDO" systemsetup -f -setremotelogin "$want" ;;
        screenlock)
            # "off" keeps a password but restores the 5-minute grace period.
            if [ "$want" = on ]; then
                run sysadminctl -screenLock immediate -password -
            else
                run sysadminctl -screenLock 300 -password -
            fi ;;
        airplay)
            # Apple's key really is spelled "Reciever".
            run defaults -currentHost write com.apple.controlcenter AirplayRecieverEnabled -bool "$bool"
            run defaults write com.apple.controlcenter AirplayRecieverEnabled -bool "$bool"
            run killall ControlCenter ;;
        powernap)
            run "$SUDO" pmset -a powernap "$num" ;;
        netwake)
            run "$SUDO" pmset -a womp "$num" ;;
        extensions)
            run defaults write NSGlobalDomain AppleShowAllExtensions -bool "$bool"
            run killall Finder ;;
    esac
}

confirm() {
    [ "$ASSUME_YES" = true ] || [ "$DRY_RUN" = true ] && return 0
    if [ ! -t 0 ]; then
        echo "Refusing to change settings without a terminal. Re-run with --yes to confirm." >&2
        return 1
    fi
    local reply
    read -r -p "$1 [y/N] " reply
    [[ "$reply" =~ ^[Yy]$ ]]
}

set_control() {
    local control="$1" want="$2" before after
    before="$(current_state "$control")"
    if [ "$before" = "$want" ]; then
        echo "✅ $(label "$control") is already $want"
        return 0
    fi
    confirm "Turn $(label "$control") $want?" || { echo "Skipped $(label "$control")"; return 0; }
    echo "→ Turning $(label "$control") $want"
    if ! apply "$control" "$want"; then
        echo "⚠️  Couldn't change it from the command line. Change it here instead:" >&2
        echo "   $(settings_hint "$control")" >&2
        return 1
    fi
    [ "$DRY_RUN" = true ] && return 0
    sleep 1
    after="$(current_state "$control")"
    if [ "$after" = "$want" ]; then
        echo "✅ $(label "$control") is now $want"
    else
        echo "⚠️  $(label "$control") still reads $after. It may need a moment, or change it in:" >&2
        echo "   $(settings_hint "$control")" >&2
        return 1
    fi
}

show_status() {
    local c state safe first=true
    if [ "$JSON" = true ]; then
        printf '['
        for c in "${CONTROLS[@]}"; do
            state="$(current_state "$c")"; safe="$(safe_state "$c")"
            [ "$first" = true ] || printf ','
            first=false
            printf '{"control":"%s","label":"%s","state":"%s","safe_state":"%s","safe":%s}' \
                "$c" "$(label "$c")" "$state" "$safe" "$([ "$state" = "$safe" ] && echo true || echo false)"
        done
        printf ']\n'
        return 0
    fi
    echo "MacGuardian posture controls"
    echo "----------------------------------------"
    for c in "${CONTROLS[@]}"; do
        state="$(current_state "$c")"; safe="$(safe_state "$c")"
        if [ "$state" = "$safe" ]; then
            printf '  ✅ %-30s %-4s\n' "$(label "$c")" "$state"
        else
            printf '  ⚠️  %-30s %-4s (recommended: %s → macguardian posture %s %s)\n' "$(label "$c")" "$state" "$safe" "$safe" "$c"
        fi
    done
}

harden() {
    local c rc=0
    for c in "${CONTROLS[@]}"; do
        set_control "$c" "$(safe_state "$c")" || rc=1
    done
    return $rc
}

usage() { sed -n '3,12p' "$0" | sed 's/^# \{0,1\}//'; echo "Controls: ${CONTROLS[*]}"; }

ARGS=()
while [ "$#" -gt 0 ]; do
    case "$1" in
        -y|--yes)     ASSUME_YES=true ;;
        -n|--dry-run) DRY_RUN=true ;;
        --json)       JSON=true ;;
        -h|--help)    usage; exit 0 ;;
        *)            ARGS+=("$1") ;;
    esac
    shift
done

ACTION="${ARGS[0]:-status}"
case "$ACTION" in
    status) show_status ;;
    list)   printf '%s\n' "${CONTROLS[@]}" ;;
    harden) harden ;;
    on|off)
        CONTROL="${ARGS[1]:-}"
        if ! is_control "$CONTROL"; then
            echo "Unknown control '${CONTROL}'. Choose one of: ${CONTROLS[*]}" >&2
            exit 2
        fi
        set_control "$CONTROL" "$ACTION" ;;
    *) usage >&2; exit 2 ;;
esac
