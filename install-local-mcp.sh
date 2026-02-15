#!/usr/bin/env bash
set -euo pipefail

# Chrome Local MCP - Installer
# Registers the "claude-in-chrome-local" MCP server with Claude Desktop and Claude Code.
# This enables local-only browser control that bypasses Anthropic's WSS bridge.
# Works on both Linux and macOS.
#
# Prerequisite: Run `claude --chrome` at least once to set up the native host.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MCP_SCRIPT="${SCRIPT_DIR}/claude-code-chrome-mcp"

NATIVE_HOST_CLAUDE_CODE="${HOME}/.claude/chrome/chrome-native-host"

# Detect OS and set Claude Desktop config path
case "$(uname -s)" in
    Linux)
        DESKTOP_CONFIG_DIR="${HOME}/.config/Claude"
        ;;
    Darwin)
        DESKTOP_CONFIG_DIR="${HOME}/Library/Application Support/Claude"
        ;;
    *)
        echo "Unsupported OS: $(uname -s)" >&2
        exit 1
        ;;
esac
DESKTOP_CONFIG_FILE="${DESKTOP_CONFIG_DIR}/claude_desktop_config.json"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[+]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[x]${NC} $*" >&2; }

# --- Pre-flight checks ---

if ! command -v python3 &>/dev/null; then
    error "Python 3 is required but not found."
    exit 1
fi

if [[ ! -f "$MCP_SCRIPT" ]]; then
    error "claude-code-chrome-mcp not found at ${MCP_SCRIPT}"
    exit 1
fi

if [[ ! -f "$NATIVE_HOST_CLAUDE_CODE" ]]; then
    error "Claude Code's chrome-native-host not found at ${NATIVE_HOST_CLAUDE_CODE}"
    error "Run 'claude --chrome' first to set up the native host."
    exit 1
fi

# --- Rewrite native messaging manifest to use Claude Code's binary ---
# Chrome extension hardcodes "com.anthropic.claude_browser_extension" as the host name,
# so we overwrite Desktop's manifest to point to Claude Code's native host binary.
# This ensures the extension connects to Claude Code (which creates the local socket)
# instead of Claude Desktop (which routes through Anthropic's WSS bridge).

# Chrome extension IDs (official Anthropic)
EXT_PROD="fcoeoabgfenejglbffodgkkbkcdhcgfn"
EXT_DEV="dihbgbndebgnbjfmelmegjepbnkhlgni"
EXT_STAGING="dngcpimnedloihjnnfngkgjoidhnaolf"

MANIFEST_DIR=""
case "$(uname -s)" in
    Linux)
        MANIFEST_DIR="${HOME}/.config/google-chrome/NativeMessagingHosts"
        ;;
    Darwin)
        MANIFEST_DIR="${HOME}/Library/Application Support/Google/Chrome/NativeMessagingHosts"
        ;;
esac
DESKTOP_MANIFEST="${MANIFEST_DIR}/com.anthropic.claude_browser_extension.json"

mkdir -p "$MANIFEST_DIR"
cat > "$DESKTOP_MANIFEST" <<EOF
{
  "name": "com.anthropic.claude_browser_extension",
  "description": "Claude Browser Extension Native Host",
  "path": "${NATIVE_HOST_CLAUDE_CODE}",
  "type": "stdio",
  "allowed_origins": [
    "chrome-extension://${EXT_DEV}/",
    "chrome-extension://${EXT_PROD}/",
    "chrome-extension://${EXT_STAGING}/"
  ]
}
EOF
info "Rewrote native messaging manifest to use Claude Code's binary"

# --- Claude Desktop config ---

if [[ ! -d "$DESKTOP_CONFIG_DIR" ]]; then
    warn "Claude Desktop not found. Skipping Claude Desktop configuration."
else
    info "Configuring Claude Desktop..."

    if [[ ! -f "$DESKTOP_CONFIG_FILE" ]]; then
        info "Creating ${DESKTOP_CONFIG_FILE}"
        echo '{}' > "$DESKTOP_CONFIG_FILE"
    fi

    python3 -c "
import json, sys

config_path = '${DESKTOP_CONFIG_FILE}'
mcp_script = '${MCP_SCRIPT}'

with open(config_path, 'r') as f:
    config = json.load(f)

servers = config.setdefault('mcpServers', {})

if 'Claude in Chrome Local' in servers:
    print('[!] Claude in Chrome Local MCP server is already configured in Claude Desktop. Skipping.')
else:
    servers['Claude in Chrome Local'] = {
        'command': 'python3',
        'args': [mcp_script]
    }
    with open(config_path, 'w') as f:
        json.dump(config, f, indent=2)
        f.write('\n')
    print('[+] Added Claude in Chrome Local MCP server to Claude Desktop config.')
"
fi

# --- Claude Code CLI ---

CLAUDE_CMD=""
if command -v claude &>/dev/null; then
    CLAUDE_CMD="claude"
elif [[ -x "$HOME/.local/bin/claude" ]]; then
    CLAUDE_CMD="$HOME/.local/bin/claude"
fi

if [[ -n "$CLAUDE_CMD" ]]; then
    info "Registering 'claude-in-chrome-local' MCP server with Claude Code..."
    "$CLAUDE_CMD" mcp add --scope user claude-in-chrome-local -- python3 "$MCP_SCRIPT"
    info "Registered with Claude Code."
else
    warn "Claude Code CLI not found. To register manually, run:"
    echo "  claude mcp add --scope user 'claude-in-chrome-local' -- python3 ${MCP_SCRIPT}"
fi

# --- Done ---

REGISTERED=""
[[ -d "$DESKTOP_CONFIG_DIR" ]] && REGISTERED="Claude Desktop"
[[ -n "$CLAUDE_CMD" ]] && { [[ -n "$REGISTERED" ]] && REGISTERED="${REGISTERED} + Claude Code" || REGISTERED="Claude Code"; }

info "Local MCP setup complete! (${REGISTERED:-none})"
echo ""
if [[ -d "$DESKTOP_CONFIG_DIR" ]]; then
    echo "Restart Claude Desktop to activate."
else
    echo "Claude Desktop was not found. After installing it, run this script again."
fi
echo "To remove: ./uninstall.sh"
echo "(Note: Claude Desktop UI cannot remove this server. Use uninstall.sh instead.)"
