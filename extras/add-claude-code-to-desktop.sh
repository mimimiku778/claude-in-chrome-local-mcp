#!/usr/bin/env bash
set -euo pipefail

# Optional: Add Claude Code as an MCP server in Claude Desktop.
# This lets Claude Desktop use Claude Code's tools (file editing, bash, etc.)
# via the MCP connector.

CONFIG_DIR="${HOME}/.config/Claude"
CONFIG_FILE="${CONFIG_DIR}/claude_desktop_config.json"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[+]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[x]${NC} $*" >&2; }

# --- Pre-flight checks ---

if ! command -v claude &>/dev/null; then
    error "Claude Code CLI not found."
    error "Install it first: https://docs.anthropic.com/en/docs/claude-code/overview"
    exit 1
fi

CLAUDE_PATH="$(command -v claude)"
info "Found Claude Code at ${CLAUDE_PATH}"

if [[ ! -d "$CONFIG_DIR" ]]; then
    error "Claude Desktop config directory not found at ${CONFIG_DIR}"
    error "Install and run Claude Desktop first."
    exit 1
fi

# --- Update config ---

if [[ ! -f "$CONFIG_FILE" ]]; then
    info "Creating ${CONFIG_FILE}"
    echo '{}' > "$CONFIG_FILE"
fi

if ! command -v python3 &>/dev/null; then
    error "Python 3 is required to update the JSON config."
    exit 1
fi

python3 -c "
import json, sys

config_path = '${CONFIG_FILE}'
claude_path = '${CLAUDE_PATH}'

with open(config_path, 'r') as f:
    config = json.load(f)

servers = config.setdefault('mcpServers', {})

if 'claude-code' in servers:
    print('[!] claude-code MCP server is already configured. Skipping.')
    sys.exit(0)

servers['claude-code'] = {
    'command': claude_path,
    'args': ['mcp', 'serve']
}

with open(config_path, 'w') as f:
    json.dump(config, f, indent=2)
    f.write('\n')

print('[+] Added claude-code MCP server to config.')
"

info "Done!"
echo ""
echo "Restart Claude Desktop to activate the Claude Code MCP connector."
