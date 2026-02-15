#!/usr/bin/env bash
set -euo pipefail

# Chrome Local MCP - Uninstaller
# Removes everything installed by install-standard.sh and install-local-mcp.sh.
# Works on both Linux and macOS.

# Detect OS and set paths
OS="$(uname -s)"
case "$OS" in
    Linux)
        MANIFEST_FILE="${HOME}/.config/google-chrome/NativeMessagingHosts/com.anthropic.claude_browser_extension.json"
        DESKTOP_CONFIG_FILE="${HOME}/.config/Claude/claude_desktop_config.json"
        ;;
    Darwin)
        MANIFEST_FILE="${HOME}/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.anthropic.claude_browser_extension.json"
        DESKTOP_CONFIG_FILE="${HOME}/Library/Application Support/Claude/claude_desktop_config.json"
        ;;
    *)
        MANIFEST_FILE=""
        DESKTOP_CONFIG_FILE=""
        ;;
esac
NATIVE_HOST_LINK="/usr/lib/claude-desktop/node_modules/electron/dist/resources/chrome-native-host"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[+]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[x]${NC} $*" >&2; }

# --- Remove symlink (Linux only) ---

if [[ "$OS" == "Linux" ]] && [[ -L "$NATIVE_HOST_LINK" || -f "$NATIVE_HOST_LINK" ]]; then
    info "Removing native host symlink at ${NATIVE_HOST_LINK}..."
    if [[ -w "$(dirname "$NATIVE_HOST_LINK")" ]]; then
        rm -f "$NATIVE_HOST_LINK"
    elif command -v pkexec &>/dev/null; then
        pkexec rm -f "$NATIVE_HOST_LINK"
    elif command -v sudo &>/dev/null; then
        sudo rm -f "$NATIVE_HOST_LINK"
    else
        error "Cannot remove ${NATIVE_HOST_LINK} — remove it manually with sudo"
    fi
    info "Removed"
fi

# --- Remove native messaging manifest ---

if [[ -n "$MANIFEST_FILE" && -f "$MANIFEST_FILE" ]]; then
    rm -f "$MANIFEST_FILE"
    info "Removed native messaging manifest"
fi

# --- Remove "Claude in Chrome Local" MCP from Claude Desktop config ---

if [[ -n "$DESKTOP_CONFIG_FILE" && -f "$DESKTOP_CONFIG_FILE" ]] && command -v python3 &>/dev/null; then
    python3 -c "
import json, sys

config_path = '${DESKTOP_CONFIG_FILE}'

with open(config_path, 'r') as f:
    config = json.load(f)

servers = config.get('mcpServers', {})
removed = False
for key in ['Claude in Chrome Local', 'claude-in-chrome-local']:
    if key in servers:
        del servers[key]
        removed = True
        print(f'[+] Removed {key} MCP server from Claude Desktop config.')
if removed:
    with open(config_path, 'w') as f:
        json.dump(config, f, indent=2)
        f.write('\n')
else:
    print('[+] Claude in Chrome Local MCP server not found in Claude Desktop config (already removed).')
"
fi

# --- Remove "claude-in-chrome-local" MCP from Claude Code ---

CLAUDE_CMD=""
if command -v claude &>/dev/null; then
    CLAUDE_CMD="claude"
elif [[ -x "$HOME/.local/bin/claude" ]]; then
    CLAUDE_CMD="$HOME/.local/bin/claude"
fi

if [[ -n "$CLAUDE_CMD" ]]; then
    info "Removing 'claude-in-chrome-local' MCP server from Claude Code..."
    "$CLAUDE_CMD" mcp remove claude-in-chrome-local 2>/dev/null || true
    info "Removed from Claude Code"
fi

# --- Done ---

info "Uninstall complete!"
echo ""
echo "Restart Chrome and Claude Desktop to finish cleanup."
