#!/bin/bash
# Register MacGuardian with your AI coding tools so they can run checkups.
#
#   install_agent_tools.sh            Claude Code: MCP server + skill (and Codex/Cursor if found)
#   install_agent_tools.sh --print    only print the config snippets, change nothing
#   install_agent_tools.sh --remove   undo what this script added
#
# Paths are resolved from where this script lives, so it works for a git clone
# or the copy in ~/Library/Application Support/MacGuardian.

set -uo pipefail
SUITE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SUITE/.." && pwd)"
SERVER="$SUITE/mcp_server.py"
SKILL_SRC="$ROOT/agent/skills/macguardian"
PY=/usr/bin/python3; [ -x "$PY" ] || PY="$(command -v python3)"
MODE="${1:-install}"

snippet() {
    cat <<EOF
MCP server (any client):
  command: $PY
  args:    ["$SERVER"]

JSON (Cursor ~/.cursor/mcp.json, Claude Desktop, etc.):
  "macguardian": { "command": "$PY", "args": ["$SERVER"] }

TOML (Codex ~/.codex/config.toml):
  [mcp_servers.macguardian]
  command = "$PY"
  args = ["$SERVER"]
EOF
}

if [ "$MODE" = "--print" ]; then snippet; exit 0; fi

if [ "$MODE" = "--remove" ]; then
    command -v claude >/dev/null && claude mcp remove macguardian --scope user 2>/dev/null && echo "Removed Claude Code MCP server"
    [ -L "$HOME/.claude/skills/macguardian" ] && rm "$HOME/.claude/skills/macguardian" && echo "Removed Claude Code skill link"
    echo "Codex/Cursor entries (if any) must be removed by hand: look for 'macguardian'."
    exit 0
fi

# Claude Code
if command -v claude >/dev/null 2>&1; then
    claude mcp remove macguardian --scope user >/dev/null 2>&1
    if claude mcp add macguardian --scope user -- "$PY" "$SERVER" >/dev/null; then
        echo "✅ Claude Code: MCP server 'macguardian' registered (all projects)"
    else
        echo "⚠️  Claude Code: could not register the MCP server"
    fi
    mkdir -p "$HOME/.claude/skills"
    if [ -e "$HOME/.claude/skills/macguardian" ] && [ ! -L "$HOME/.claude/skills/macguardian" ]; then
        echo "⚠️  Claude Code: ~/.claude/skills/macguardian exists and is not ours; left it alone"
    else
        ln -sfn "$SKILL_SRC" "$HOME/.claude/skills/macguardian" && echo "✅ Claude Code: skill 'macguardian' linked"
    fi
fi

# Codex
CODEX="$HOME/.codex/config.toml"
if [ -f "$CODEX" ]; then
    if grep -q '^\[mcp_servers.macguardian\]' "$CODEX"; then
        echo "✅ Codex: already configured"
    else
        cp "$CODEX" "$CODEX.bak.$(date +%Y%m%d%H%M%S)"
        printf '\n[mcp_servers.macguardian]\ncommand = "%s"\nargs = ["%s"]\n' "$PY" "$SERVER" >> "$CODEX"
        echo "✅ Codex: MCP server added (backup saved next to config.toml)"
    fi
fi

# Cursor
CURSOR="$HOME/.cursor/mcp.json"
if [ -f "$CURSOR" ]; then
    "$PY" -I - "$CURSOR" "$PY" "$SERVER" <<'PY'
import json, sys, shutil, time
path, py, server = sys.argv[1:4]
try:
    data = json.load(open(path))
except ValueError:
    print("⚠️  Cursor: mcp.json is not valid JSON; left it alone"); sys.exit()
servers = data.setdefault("mcpServers", {})
if servers.get("macguardian", {}).get("args") == [server]:
    print("✅ Cursor: already configured"); sys.exit()
shutil.copy(path, f"{path}.bak.{time.strftime('%Y%m%d%H%M%S')}")
servers["macguardian"] = {"command": py, "args": [server]}
json.dump(data, open(path, "w"), indent=2)
print("✅ Cursor: MCP server added (backup saved next to mcp.json)")
PY
fi

echo ""
echo "Other tools: run '$0 --print' for config snippets."
echo "Try it: ask your assistant to \"run a MacGuardian checkup\"."
