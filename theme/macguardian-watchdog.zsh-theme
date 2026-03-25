#!/usr/bin/env zsh
#
# MacGuardian Watchdog Theme
# Omega Technologies - Dark Cyberpunk Aesthetic
# Primary: #8A2BE2 (Electric Purple)
# Secondary: #FF0044 (Neon Red)
#

# Color definitions
MACGUARDIAN_PURPLE='%F{135}%B'      # #8A2BE2 (electric purple)
MACGUARDIAN_RED='%F{196}%B'          # #FF0044 (neon red)
MACGUARDIAN_CYAN='%F{51}'            # Cyan glow
MACGUARDIAN_GRAY='%F{240}'           # Dim gray
MACGUARDIAN_RESET='%f%b'

# ASCII Art Header (shown once per session)
if [[ -z "$MACGUARDIAN_HEADER_SHOWN" ]]; then
    echo ""
    echo "${MACGUARDIAN_PURPLE}╔════════════════════════════════════════════════════════════╗${MACGUARDIAN_RESET}"
    echo "${MACGUARDIAN_PURPLE}║${MACGUARDIAN_RESET}                                                                    ${MACGUARDIAN_PURPLE}║${MACGUARDIAN_RESET}"
    echo "${MACGUARDIAN_PURPLE}║${MACGUARDIAN_RESET}    ${MACGUARDIAN_CYAN}Ω-Technologies${MACGUARDIAN_RESET} ${MACGUARDIAN_GRAY}//${MACGUARDIAN_RESET} ${MACGUARDIAN_PURPLE}MacGuardian Watchdog${MACGUARDIAN_RESET}     ${MACGUARDIAN_PURPLE}║${MACGUARDIAN_RESET}"
    echo "${MACGUARDIAN_PURPLE}║${MACGUARDIAN_RESET}                                                                    ${MACGUARDIAN_PURPLE}║${MACGUARDIAN_RESET}"
    echo "${MACGUARDIAN_PURPLE}╚════════════════════════════════════════════════════════════╝${MACGUARDIAN_RESET}"
    echo ""
    export MACGUARDIAN_HEADER_SHOWN=1
fi

# Function to get git repo name
_macguardian_git_repo() {
    local git_dir=$(git rev-parse --show-toplevel 2>/dev/null)
    if [[ -n "$git_dir" ]]; then
        basename "$git_dir"
    else
        echo ""
    fi
}

# Function to get git status indicator
_macguardian_git_status() {
    local git_status=$(git status --porcelain 2>/dev/null)
    if [[ -n "$git_status" ]]; then
        echo "${MACGUARDIAN_RED}●${MACGUARDIAN_RESET}"
    else
        echo "${MACGUARDIAN_CYAN}●${MACGUARDIAN_RESET}"
    fi
}

# Prompt components
# Timestamp in purple
PROMPT_TIME="${MACGUARDIAN_PURPLE}[%*]${MACGUARDIAN_RESET}"

# User in purple
PROMPT_USER="${MACGUARDIAN_PURPLE}%n${MACGUARDIAN_RESET}"

# Current directory in gray
PROMPT_DIR="${MACGUARDIAN_GRAY}%~${MACGUARDIAN_RESET}"

# Git repo name in purple (if in git repo)
PROMPT_GIT_REPO='$([ -n "$(_macguardian_git_repo)" ] && echo "${MACGUARDIAN_PURPLE}[$(_macguardian_git_repo)]${MACGUARDIAN_RESET} ")'

# Git status indicator
PROMPT_GIT_STATUS='$([ -n "$(_macguardian_git_repo)" ] && echo "$(_macguardian_git_status) ")'

# Main prompt: [time] user [repo] dir ● >
PROMPT="${PROMPT_TIME} ${PROMPT_USER} ${PROMPT_GIT_REPO}${PROMPT_DIR} ${PROMPT_GIT_STATUS}${MACGUARDIAN_RED}>${MACGUARDIAN_RESET} "

# Right prompt: Show command execution time for long-running commands
RPROMPT="${MACGUARDIAN_GRAY}%?${MACGUARDIAN_RESET}"

# Command execution time tracking
preexec() {
    _MACGUARDIAN_CMD_START=$(date +%s)
}

precmd() {
    if [[ -n "$_MACGUARDIAN_CMD_START" ]]; then
        local cmd_duration=$(($(date +%s) - $_MACGUARDIAN_CMD_START))
        if [[ $cmd_duration -gt 2 ]]; then
            RPROMPT="${MACGUARDIAN_PURPLE}⏱ ${cmd_duration}s${MACGUARDIAN_RESET} ${MACGUARDIAN_GRAY}%?${MACGUARDIAN_RESET}"
        else
            RPROMPT="${MACGUARDIAN_GRAY}%?${MACGUARDIAN_RESET}"
        fi
        unset _MACGUARDIAN_CMD_START
    fi
}

# Error indicator in red
PROMPT2="${MACGUARDIAN_RED}%_>${MACGUARDIAN_RESET} "
PROMPT3="${MACGUARDIAN_RED}?#${MACGUARDIAN_RESET} "

# Syntax highlighting colors (if zsh-syntax-highlighting is installed)
if [[ -d "${HOME}/.zsh/zsh-syntax-highlighting" ]] || command -v zsh-syntax-highlighting &>/dev/null; then
    export ZSH_HIGHLIGHT_STYLES[command]="${MACGUARDIAN_PURPLE}"
    export ZSH_HIGHLIGHT_STYLES[builtin]="${MACGUARDIAN_PURPLE}"
    export ZSH_HIGHLIGHT_STYLES[function]="${MACGUARDIAN_PURPLE}"
    export ZSH_HIGHLIGHT_STYLES[alias]="${MACGUARDIAN_CYAN}"
    export ZSH_HIGHLIGHT_STYLES[single-hyphen-option]="${MACGUARDIAN_GRAY}"
    export ZSH_HIGHLIGHT_STYLES[double-hyphen-option]="${MACGUARDIAN_GRAY}"
    export ZSH_HIGHLIGHT_STYLES[path]="${MACGUARDIAN_CYAN}"
    export ZSH_HIGHLIGHT_STYLES[globbing]="${MACGUARDIAN_RED}"
    export ZSH_HIGHLIGHT_STYLES[history-expansion]="${MACGUARDIAN_RED}"
fi

# Autosuggestions color (if zsh-autosuggestions is installed)
if [[ -d "${HOME}/.zsh/zsh-autosuggestions" ]] || command -v zsh-autosuggestions &>/dev/null; then
    export ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=240"  # Dim gray
fi

# LS colors (for dark cyberpunk theme)
export LSCOLORS="gxfxcxdxbxegedabagacad"
export CLICOLOR=1

# Terminal title
case $TERM in
    xterm*|rxvt*|screen*)
        precmd() {
            print -Pn "\e]0;Ω-Technologies // MacGuardian Watchdog // %n@%m: %~\a"
        }
        preexec() {
            print -Pn "\e]0;Ω-Technologies // MacGuardian Watchdog // $1\a"
        }
        ;;
esac

