# Claude in Chrome — Local MCP

**[English](README.md)**

Claude in Chrome 拡張機能との接続を WSS からローカル Unix ソケットに置き換える MCP サーバー。
複数クライアントの同時接続に対応し、任意の MCP クライアントから利用できる。

[Claude in Chrome が接続できない問題（#20298）](https://github.com/anthropics/claude-code/issues/20298)も別アプローチで解決します。

- **WSS 不要** — `bridge.claudeusercontent.com` を経由しない
- **常にローカルの Chrome に直結** — 別端末への誤接続なし（[#25551](https://github.com/anthropics/claude-code/issues/25551)）
- **同時接続OK** — ネイティブホスト1つで複数クライアントをさばく
- **どのMCPクライアントでも使える** — Claude Desktop / Code に限らず何でも
- **Claude Desktop と Code の併用が可能** — ネイティブホストの競合を回避（[#20887](https://github.com/anthropics/claude-code/issues/20887)）

## アーキテクチャ

```
標準:          Claude Desktop / Code --WSS--> bridge.claudeusercontent.com --WSS--> chrome-native-host --stdio--> Chrome
本プロジェクト: Claude Desktop / Code --stdio--> claude-code-chrome-mcp --Unixソケット--> chrome-native-host --stdio--> Chrome
```

---

## セットアップ

```bash
claude --chrome                        # 1. ネイティブホストを初期化（初回のみ）

git clone https://github.com/mimimiku778/claude-in-chrome-local-mcp.git
cd claude-in-chrome-local-mcp
./install-local-mcp.sh                 # 2. MCPサーバー登録 & Claude Desktop のネイティブホストを無効化
```

**Linux のみ（任意）:** Claude Desktop の標準 Claude in Chrome（WSS）を有効にする:

```bash
./install-standard.sh                  # シンボリックリンク作成に sudo が必要
```

MCPサーバー（`claude-code-chrome-mcp`）はクローンしたディレクトリから実行されます。このディレクトリは削除しないでください。

インストール後、Claude Desktop を再起動してください。
Claude Desktop を後からインストールした場合は、`./install-local-mcp.sh` を再実行してください。

## 前提条件

- macOS / Linux
- Claude Code
- Google Chrome + [Claude in Chrome 拡張機能](https://chromewebstore.google.com/detail/claude/fcoeoabgfenejglbffodgkkbkcdhcgfn)
- Python 3.10+
- Claude Desktop（任意）

公式の Linux 版 Claude Desktop はありません。[claude-desktop-debian](https://github.com/aaddrick/claude-desktop-debian) を使用してください。

---

## スクリプト一覧

| スクリプト | 内容 |
|---|---|
| `install-local-mcp.sh` | `claude-code-chrome-mcp` をMCPサーバーとして登録。ネイティブメッセージングマニフェストを Claude Code のバイナリに書き換え。 |
| `install-standard.sh` | **Linux のみ。** Claude Desktop の標準 Claude in Chrome 機能を有効化（ネイティブメッセージングマニフェスト + シンボリックリンク） |
| `uninstall.sh` | 上記スクリプトでインストールしたものをすべて削除 |
| `claude-code-chrome-mcp` | MCPサーバー本体 — MCPプロトコルとネイティブホストのUnixソケット間を変換 |

## アンインストール

```bash
./uninstall.sh
```

---

## トラブルシューティング

- **拡張機能が接続されない** — `claude --chrome` でネイティブホストの設定を確認

- **ローカルMCPが動作しない** — `ls /tmp/claude-mcp-browser-bridge-$USER/` と `~/.config/Claude/logs/claude-code-chrome-mcp.log` を確認

- **標準コネクタが検出されない（Linux）** — `ls -la /usr/lib/claude-desktop/node_modules/electron/dist/resources/chrome-native-host` を確認

---

## 背景: Claude in Chrome の既知の問題

[Claude in Chrome](https://code.claude.com/docs/ja/chrome) は Anthropic のWSSリレー（`bridge.claudeusercontent.com`）経由で接続します。リリース以降、以下の問題が報告されています。

### ブラウザ指定 — 接続先を選べない

WSSリレーは同一アカウントのどの Chrome にもルーティングできるため、LAN上の複数端末で誤接続が発生します。

| 日付 | Issue |
|---|---|
| 2025-12-18 | [#14536](https://github.com/anthropics/claude-code/issues/14536) デフォルトブラウザではなくブラウザを選択可能に |
| 2025-12-23 | [#15125](https://github.com/anthropics/claude-code/issues/15125) 特定の Chrome インスタンス/プロファイルの指定 |
| 2026-02-13 | [#25551](https://github.com/anthropics/claude-code/issues/25551) LAN上の別端末のブラウザに誤接続 |

### ネイティブホスト競合 — Claude Desktop vs Claude Code

両方が同じ拡張機能IDに対してネイティブメッセージングホストを登録。Chrome は一方しか使えないため、後からインストールした方が優先。

| 日付 | Issue |
|---|---|
| 2026-01-23 | [#20341](https://github.com/anthropics/claude-code/issues/20341) Claude Desktop のネイティブホストが拡張機能を横取り |
| 2026-01-26 | [#20887](https://github.com/anthropics/claude-code/issues/20887) 拡張機能が Claude Code ではなく Claude Desktop に接続 |

### 接続失敗

| 日付 | Issue |
|---|---|
| 2026-01-23 | [#20298](https://github.com/anthropics/claude-code/issues/20298) 拡張機能が接続できない（macOS） |
| 2026-01-26 | [#21033](https://github.com/anthropics/claude-code/issues/21033) サンドボックスがソケットをブロック（macOS） |
| 2026-02-06 | [#23539](https://github.com/anthropics/claude-code/issues/23539) Windows で接続できない |
| 2026-02-08 | [#24192](https://github.com/anthropics/claude-code/issues/24192) Linux でソケットが作成されない（ENOENT） |
| 2026-02-10 | [#24593](https://github.com/anthropics/claude-code/issues/24593) 接続が永続的に失敗（macOS） |

---

## 技術詳細

### 本プロジェクトの仕組み

Chrome の Native Messaging が `chrome-native-host` を起動し、ローカルにUnixソケットを作成します:

```
/tmp/claude-mcp-browser-bridge-{USER}/{PID}.sock
```

**本プロジェクトはこのソケットに直接接続します。** ローカルで Chrome を操作するにはこれだけで十分です。

### なぜ標準パスは WSS リレーを経由するのか

`chrome-native-host` はローカルにUnixソケットを作成するだけでなく、Anthropic の外部サーバー `bridge.claudeusercontent.com` にも WSS で接続します。標準のMCPサーバーも同じ外部サーバーに接続し、リレーが両者を中継します:

```
MCPサーバー --WSS--> bridge.claudeusercontent.com <--WSS-- chrome-native-host
                     （Anthropicの外部サーバー）
```

これによりデバイス間でのブラウザ接続が可能になりますが、同一マシンでも通信が外部を経由します。

本プロジェクトは WSS リレーを経由せず、`chrome-native-host` が作成するローカルソケットに直接接続します:

```
claude-code-chrome-mcp --Unixソケット--> chrome-native-host
                        （同一マシン内で完結）
```

以下は Claude Code v2.1.42 バンドルバイナリから復元したコードです（Claude Desktop も同じコードを使用）。

ネイティブホスト（`runChromeNativeHost`、Chrome が自動起動）がローカルにUnixソケットを作成:

```js
// chrome-native-host — Chrome が起動するプロセス
this.server = net.createServer((socket) => this.handleMcpClient(socket));
this.server.listen(this.socketPath, () => {   // /tmp/claude-mcp-browser-bridge-{USER}/{PID}.sock
    fs.chmodSync(this.socketPath, 0o600);
});
```

MCPサーバー（`runClaudeInChromeMcpServer`）はこのソケットに接続する機能を持っていますが、フィーチャーフラグが有効な場合は外部WSSリレーにリダイレクトされます:

```js
function getBridgeUrl() {
    // LaunchDarkly（リモートフィーチャーフラグサービス）から取得
    // 第2引数 false はオフライン時のフォールバック。通常は true が返る
    if (!getFeatureFlag("tengu_copper_bridge", false)) return;
    return "wss://bridge.claudeusercontent.com";
}

let bridgeUrl = getBridgeUrl();

let config = {
    socketPath: getSocketPath(),       // ← ローカルUnixソケット（同一マシン内のみ）
    clientTypeId: "claude-code",
    ...bridgeUrl && { bridgeConfig: { url: bridgeUrl, ... } },
    // ↑ bridgeUrl があると WSS リレー（Anthropicの外部サーバー経由、デバイス間通信可能）が優先される
};
```

つまり、ローカルソケットへの接続コードは存在するのに、LaunchDarkly が常に `true` を返すため WSS リレーが優先され、ローカルソケットは使われません。本プロジェクトはこのフラグを迂回し、ソケットに直接接続します。
