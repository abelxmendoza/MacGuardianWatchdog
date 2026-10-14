#!/bin/bash

# Update and upgrade software managed by Homebrew and the Mac App Store.
#
#   package_updates.sh update
#       Refresh Homebrew metadata and show everything that is outdated.
#
#   package_updates.sh upgrade
#       Upgrade every outdated formula, every outdated cask (including
#       auto_updates/latest casks), and Mac App Store apps when `mas` exists.
#
#   package_updates.sh all
#       Run both operations.

set -uo pipefail

export PATH="${PATH:-}:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

MODE="${1:-}"
[ "$#" -gt 0 ] && shift
ASSUME_YES=false
INSTALL_MAS=false

while [ "$#" -gt 0 ]; do
    case "$1" in
        -y|--yes|--non-interactive) ASSUME_YES=true ;;
        --install-mas) INSTALL_MAS=true ;;
        -h|--help)
            MODE="help"
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 2
            ;;
    esac
    shift
done

usage() {
    cat <<'EOF'
Usage: package_updates.sh {update|upgrade|all} [OPTIONS]

Commands:
  update        Refresh Homebrew and list outdated formulae, casks and App Store apps
  upgrade       Upgrade all outdated formulae/casks and App Store apps
  all           Run update, then upgrade

Options:
  -y, --yes     Run Homebrew upgrades without confirmation
  --install-mas Offer to install the `mas` helper when App Store coverage is missing
EOF
}

case "$MODE" in
    update|upgrade|all) ;;
    help|-h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
esac

if ! command -v brew >/dev/null 2>&1; then
    echo "ERROR: Homebrew is not installed. Install it from https://brew.sh first." >&2
    exit 1
fi

BREW_BIN="$(command -v brew)"
FAILURES=0

run_step() {
    local label="$1"
    shift
    echo ""
    echo "== $label =="
    if "$@"; then
        return 0
    fi
    echo "WARNING: $label failed; continuing with the remaining updates." >&2
    FAILURES=$((FAILURES + 1))
    return 0
}

list_outdated() {
    local title="$1"
    shift
    local output
    output=$("$@" 2>&1)
    local result=$?
    echo ""
    echo "-- $title --"
    if [ "$result" -ne 0 ]; then
        echo "$output" >&2
        FAILURES=$((FAILURES + 1))
    elif [ -n "$output" ]; then
        echo "$output"
    else
        echo "Up to date"
    fi
}

update_catalogs() {
    run_step "Refreshing Homebrew package and app catalogs" "$BREW_BIN" update
    list_outdated "Outdated command-line tools" "$BREW_BIN" outdated --formula --quiet
    list_outdated "Outdated Homebrew apps (including auto-update/latest casks)" \
        "$BREW_BIN" outdated --cask --greedy --quiet

    if command -v mas >/dev/null 2>&1; then
        list_outdated "Outdated Mac App Store apps" "$(command -v mas)" outdated
    else
        echo ""
        echo "-- Mac App Store apps --"
        echo "Coverage unavailable: install the 'mas' helper with 'brew install mas',"
        echo "or run this script's upgrade command with --install-mas."
    fi
}

confirm_mas_install() {
    [ "$INSTALL_MAS" = true ] || return 1
    if [ "$ASSUME_YES" = true ]; then
        return 0
    fi
    [ -t 0 ] || return 1
    local reply
    read -r -p "Install the 'mas' helper so MacGuardian can upgrade App Store apps? [Y/n] " reply
    [[ -z "$reply" || "$reply" =~ ^[Yy] ]]
}

ensure_mas() {
    if command -v mas >/dev/null 2>&1; then
        return 0
    fi
    if confirm_mas_install; then
        run_step "Installing Mac App Store update helper" "$BREW_BIN" install mas
    fi
    command -v mas >/dev/null 2>&1
}

upgrade_items() {
    local kind="$1"
    shift
    local items item
    items=$("$BREW_BIN" outdated "$kind" "$@" --quiet 2>/dev/null)
    local result=$?
    if [ "$result" -ne 0 ]; then
        echo "WARNING: Could not read the outdated $kind list." >&2
        FAILURES=$((FAILURES + 1))
        return 0
    fi
    if [ -z "$items" ]; then
        echo "Nothing to upgrade."
        return 0
    fi

    while IFS= read -r item; do
        [ -n "$item" ] || continue
        if [ "$kind" = "--cask" ]; then
            if [ "$ASSUME_YES" = true ]; then
                run_step "Upgrading app: $item" "$BREW_BIN" upgrade --cask --greedy --no-ask "$item"
            else
                run_step "Upgrading app: $item" "$BREW_BIN" upgrade --cask --greedy "$item"
            fi
        elif [ "$ASSUME_YES" = true ]; then
            run_step "Upgrading tool: $item" "$BREW_BIN" upgrade --formula --no-ask "$item"
        else
            run_step "Upgrading tool: $item" "$BREW_BIN" upgrade --formula "$item"
        fi
    done <<< "$items"
}

upgrade_everything() {
    echo ""
    echo "== Upgrading every Homebrew formula =="
    upgrade_items --formula

    echo ""
    echo "== Upgrading every Homebrew-managed app =="
    upgrade_items --cask --greedy

    if ensure_mas; then
        run_step "Upgrading all Mac App Store apps" "$(command -v mas)" upgrade
    else
        echo ""
        echo "Mac App Store apps were skipped because the 'mas' helper is not installed."
    fi

    run_step "Cleaning old Homebrew versions" "$BREW_BIN" cleanup

    echo ""
    echo "Note: apps installed directly from vendor websites are not managed by"
    echo "Homebrew or the Mac App Store and must use their own built-in updater."
}

case "$MODE" in
    update) update_catalogs ;;
    upgrade) upgrade_everything ;;
    all)
        update_catalogs
        upgrade_everything
        ;;
esac

if [ "$FAILURES" -gt 0 ]; then
    echo ""
    echo "Completed with $FAILURES failed update step(s)." >&2
    exit 1
fi

echo ""
echo "Software maintenance completed successfully."
