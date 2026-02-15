#!/usr/bin/env bash
set -euo pipefail

# Linux only: Enables the standard built-in Claude in Chrome for Claude Desktop.
# Creates a symlink + native messaging manifest.
# macOS does not need this — Claude Desktop sets up native messaging automatically.

CLAUDE_CODE_NATIVE_HOST="${HOME}/.claude/chrome/chrome-native-host"

# Chrome extension IDs (official Anthropic)
EXT_PROD="fcoeoabgfenejglbffodgkkbkcdhcgfn"
EXT_DEV="dihbgbndebgnbjfmelmegjepbnkhlgni"
EXT_STAGING="dngcpimnedloihjnnfngkgjoidhnaolf"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[+]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[x]${NC} $*" >&2; }

# --- Detect OS ---

OS="$(uname -s)"
case "$OS" in
    Linux)
        MANIFEST_DIR="${HOME}/.config/google-chrome/NativeMessagingHosts"
        ;;
    Darwin)
        MANIFEST_DIR="${HOME}/Library/Application Support/Google/Chrome/NativeMessagingHosts"
        ;;
    *)
        error "Unsupported OS: ${OS}"
        exit 1
        ;;
esac
MANIFEST_FILE="${MANIFEST_DIR}/com.anthropic.claude_browser_extension.json"

# --- Pre-flight checks ---

if [[ ! -f "$CLAUDE_CODE_NATIVE_HOST" ]]; then
    error "Claude Code's chrome-native-host not found at ${CLAUDE_CODE_NATIVE_HOST}"
    error "Run 'claude --chrome' first to set up the native host."
    exit 1
fi

# --- Linux only: create symlink for Claude Desktop detection ---

if [[ "$OS" == "Linux" ]]; then
    RESOURCES_DIR="/usr/lib/claude-desktop/node_modules/electron/dist/resources"
    NATIVE_HOST_LINK="${RESOURCES_DIR}/chrome-native-host"

    if [[ ! -d "$RESOURCES_DIR" ]]; then
        warn "Claude Desktop not found at ${RESOURCES_DIR} — skipping symlink"
    else
        info "Creating symlink at ${NATIVE_HOST_LINK} -> ${CLAUDE_CODE_NATIVE_HOST}"
        if [[ -w "$RESOURCES_DIR" ]]; then
            ln -sf "$CLAUDE_CODE_NATIVE_HOST" "$NATIVE_HOST_LINK"
        else
            warn "Elevated privileges required to write to ${RESOURCES_DIR}"
            if command -v pkexec &>/dev/null; then
                pkexec ln -sf "$CLAUDE_CODE_NATIVE_HOST" "$NATIVE_HOST_LINK"
            elif command -v sudo &>/dev/null; then
                sudo ln -sf "$CLAUDE_CODE_NATIVE_HOST" "$NATIVE_HOST_LINK"
            else
                error "Cannot obtain elevated privileges. Manually run:"
                error "  sudo ln -sf '$CLAUDE_CODE_NATIVE_HOST' '$NATIVE_HOST_LINK'"
                exit 1
            fi
        fi
    fi
fi

# --- Create native messaging manifest ---

info "Creating native messaging manifest at ${MANIFEST_FILE}"
mkdir -p "$MANIFEST_DIR"
cat > "$MANIFEST_FILE" <<EOF
{
  "name": "com.anthropic.claude_browser_extension",
  "description": "Claude Browser Extension Native Host",
  "path": "${CLAUDE_CODE_NATIVE_HOST}",
  "type": "stdio",
  "allowed_origins": [
    "chrome-extension://${EXT_DEV}/",
    "chrome-extension://${EXT_PROD}/",
    "chrome-extension://${EXT_STAGING}/"
  ]
}
EOF

# --- Done ---

info "Installation complete!"
echo ""
echo "Next steps:"
echo "  1. Restart Chrome and Claude Desktop"
echo "  2. The standard browser tools should now work"
echo ""
echo "To also enable local MCP (always targets this PC's Chrome):"
echo "  ./install-local-mcp.sh"
