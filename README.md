# Claude in Chrome — Local MCP

**[日本語](README.ja.md)**

An MCP server that replaces the WSS connection to the Claude in Chrome extension with a local Unix socket.
Supports multiple simultaneous client connections and works with any MCP client.

[Claude in Chrome connection issues (#20298)](https://github.com/anthropics/claude-code/issues/20298) — solved with a different approach.

- **No WSS** — does not go through `bridge.claudeusercontent.com`
- **Always connects to local Chrome** — no cross-device mismatch ([#25551](https://github.com/anthropics/claude-code/issues/25551))
- **Simultaneous connections** — a single native host serves multiple clients
- **Works with any MCP client** — not limited to Claude Desktop / Code
- **Claude Desktop + Code coexistence** — avoids native host conflict ([#20887](https://github.com/anthropics/claude-code/issues/20887))

## Architecture

```
Standard:     Claude Desktop / Code --WSS--> bridge.claudeusercontent.com --WSS--> chrome-native-host --stdio--> Chrome
This project: Claude Desktop / Code --stdio--> claude-code-chrome-mcp --Unix socket--> chrome-native-host --stdio--> Chrome
```

---

## Setup

```bash
claude --chrome                        # 1. Initialize the native host (first time only)

git clone https://github.com/mimimiku778/claude-in-chrome-local-mcp.git
cd claude-in-chrome-local-mcp
./install-local-mcp.sh                 # 2. Register MCP server & disable Claude Desktop's native host
```

**Linux only (optional):** Enable the standard Claude in Chrome (WSS) for Claude Desktop:

```bash
./install-standard.sh                  # requires sudo for symlink
```

The MCP server (`claude-code-chrome-mcp`) runs from this cloned directory. Do not remove it.

Restart Claude Desktop after installation.
If you install Claude Desktop later, re-run `./install-local-mcp.sh`.

## Prerequisites

- macOS / Linux
- Claude Code
- Google Chrome + [Claude in Chrome extension](https://chromewebstore.google.com/detail/claude/fcoeoabgfenejglbffodgkkbkcdhcgfn)
- Python 3.10+
- Claude Desktop (optional)

No official Linux build of Claude Desktop is available. Use [claude-desktop-debian](https://github.com/aaddrick/claude-desktop-debian).

---

## Scripts

| Script | What it does |
|---|---|
| `install-local-mcp.sh` | Registers `claude-code-chrome-mcp` as an MCP server. Rewrites native messaging manifest to use Claude Code's binary. |
| `install-standard.sh` | **Linux only.** Enables the standard built-in Claude in Chrome for Claude Desktop (native messaging manifest + symlink) |
| `uninstall.sh` | Removes everything installed by the above scripts |
| `claude-code-chrome-mcp` | The MCP server — translates MCP protocol to/from the native host's Unix socket |

## Uninstall

```bash
./uninstall.sh
```

---

## Troubleshooting

- **Extension not connecting** — run `claude --chrome` to verify native host setup

- **Local MCP not working** — check `ls /tmp/claude-mcp-browser-bridge-$USER/` and `~/.config/Claude/logs/claude-code-chrome-mcp.log`

- **Standard connector not detected (Linux)** — check `ls -la /usr/lib/claude-desktop/node_modules/electron/dist/resources/chrome-native-host`

---

## Background: Known Issues with Claude in Chrome

[Claude in Chrome](https://code.claude.com/docs/en/chrome) connects to Claude Desktop / Claude Code via Anthropic's WSS relay (`bridge.claudeusercontent.com`). Several categories of issues have been reported since launch.

### Browser targeting — no way to choose which browser

The WSS relay can route to any Chrome on the same account, causing wrong-browser connections on multi-device LANs.

| Date | Issue |
|---|---|
| 2025-12-18 | [#14536](https://github.com/anthropics/claude-code/issues/14536) Allow browser selection instead of opening default browser |
| 2025-12-23 | [#15125](https://github.com/anthropics/claude-code/issues/15125) Support targeting specific Chrome instances/profiles |
| 2026-02-13 | [#25551](https://github.com/anthropics/claude-code/issues/25551) `--chrome` connects to wrong browser on LAN |

### Native host conflict — Claude Desktop vs Claude Code

Both register a native messaging host for the same extension ID. Chrome can only use one, so whichever was installed last wins.

| Date | Issue |
|---|---|
| 2026-01-23 | [#20341](https://github.com/anthropics/claude-code/issues/20341) Claude Desktop native host intercepts Chrome extension |
| 2026-01-26 | [#20887](https://github.com/anthropics/claude-code/issues/20887) Extension connects to Claude Desktop instead of Claude Code |

### Connection failures

| Date | Issue |
|---|---|
| 2026-01-23 | [#20298](https://github.com/anthropics/claude-code/issues/20298) Browser extension not connecting (macOS) |
| 2026-01-26 | [#21033](https://github.com/anthropics/claude-code/issues/21033) Sandbox blocks native messaging socket (macOS) |
| 2026-02-06 | [#23539](https://github.com/anthropics/claude-code/issues/23539) Not connecting on Windows |
| 2026-02-08 | [#24192](https://github.com/anthropics/claude-code/issues/24192) Socket never created on Linux (ENOENT) |
| 2026-02-10 | [#24593](https://github.com/anthropics/claude-code/issues/24593) Persistently fails to connect (macOS) |

---

## Technical Details

### How this project works

Chrome's Native Messaging spawns `chrome-native-host`, which creates a local Unix socket:

```
/tmp/claude-mcp-browser-bridge-{USER}/{PID}.sock
```

**This project connects directly to that socket.** That's all it takes to control Chrome locally.

### Why the standard path uses the WSS relay instead

`chrome-native-host` not only creates a local Unix socket, but also connects via WSS to Anthropic's external server `bridge.claudeusercontent.com`. The standard MCP server connects to the same server, and the relay bridges the two:

```
MCP server --WSS--> bridge.claudeusercontent.com <--WSS-- chrome-native-host
                    (Anthropic's external server)
```

This enables cross-device browser connections, but means even same-machine communication goes through an external server.

This project bypasses the WSS relay and connects directly to the local socket created by `chrome-native-host`:

```
claude-code-chrome-mcp --Unix socket--> chrome-native-host
                        (stays on the same machine)
```

The following is reconstructed from the Claude Code v2.1.42 bundled binary (Claude Desktop also uses this code).

The native host (`runChromeNativeHost`, spawned by Chrome) creates a local Unix socket:

```js
// chrome-native-host — process spawned by Chrome
this.server = net.createServer((socket) => this.handleMcpClient(socket));
this.server.listen(this.socketPath, () => {   // /tmp/claude-mcp-browser-bridge-{USER}/{PID}.sock
    fs.chmodSync(this.socketPath, 0o600);
});
```

The MCP server (`runClaudeInChromeMcpServer`) can connect to this socket, but when a feature flag is enabled it redirects to the external WSS relay instead:

```js
function getBridgeUrl() {
    // Fetched from LaunchDarkly (remote feature flag service)
    // Second arg (false) is the offline fallback only — normally returns true
    if (!getFeatureFlag("tengu_copper_bridge", false)) return;
    return "wss://bridge.claudeusercontent.com";
}

let bridgeUrl = getBridgeUrl();

let config = {
    socketPath: getSocketPath(),       // ← local Unix socket (same machine only)
    clientTypeId: "claude-code",
    ...bridgeUrl && { bridgeConfig: { url: bridgeUrl, ... } },
    // ↑ when bridgeUrl exists, WSS relay (Anthropic's external server, enables cross-device) takes priority
};
```

The local socket code exists but is never used — LaunchDarkly always returns `true`, so the WSS relay takes priority. This project bypasses that flag and connects to the socket directly.
