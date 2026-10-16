# Minami Yomado

**A virtual workspace for your agent, with one live PiP of the whole desktop.**

Minami Yomado is a local macOS MCP server. Agents can create and configure virtual displays, move exact task windows, and open an independent live viewer. Your documents and application windows stay together while the agent works across apps.

- **One compact viewer:** 480×300 by default. Your size and position are remembered across reopening and restarts.
- **MCP control:** names, resolution, HiDPI, exact window placement, preview controls and restoration.
- **Independent lifetime:** the workspace survives MCP disconnects and closing the viewer.
- **Works alongside Minami:** Minami browser/computer-use can supply application automation; Minami Yomado supplies the workspace and whole-desktop view.

## Install for Codex

Requires **Apple Silicon macOS**, **Node.js 20+**, and Codex CLI for automatic registration. The release includes the native helper and Node dependencies; Xcode and npm are not required for the binary install.

```bash
curl -fsSL https://raw.githubusercontent.com/ZunbaRan/minami-yomado/mcp-v0.1.0/scripts/install.sh -o /tmp/minami-yomado-install.sh
bash /tmp/minami-yomado-install.sh --codex
```

Start a **new Codex session** after installation. No API key is needed. macOS control/capture permissions must be granted by the user on first use.

For other agents, omit `--codex`: the installer prints a standard `mcpServers` configuration and saves it in `~/.local/share/minami-yomado/mcp-config.json`. Merge that entry into your client's MCP configuration.

**[Full quick start and troubleshooting](docs/quickstart.md)** · **[Download release](https://github.com/ZunbaRan/minami-yomado/releases/tag/mcp-v0.1.0)** · **[中文](README.zh-CN.md)**

## First task

> Use minami_yomado to check permissions and list workspaces. Create a workspace named “Agent Work” only if needed. Open one compact whole-desktop PiP, reusing my saved size. Identify the exact windows for this task before moving them. Use your computer-use tools for application input. Keep the same viewer open while working; don't resize or reopen it between actions. When finished, save the work and restore the moved windows before stopping the workspace.

The PiP is read-only. Virtual displays share your macOS login, focus and input; they are not isolated computers. Keep a physical display enabled and primary. The native helper uses private macOS virtual-display APIs, so compatibility can change with OS updates.

## Build from source

With Node.js 20+ and Xcode Command Line Tools installed:

```bash
git clone https://github.com/ZunbaRan/minami-yomado.git
cd minami-yomado
npm ci --ignore-scripts
npm run build
npm run setup -- --codex
```

The installer refuses to replace a running workspace. Restore its windows and stop it before upgrading. Installation never automatically creates a virtual display or grants macOS permissions.

## For agents and contributors

Read [AGENTS.md](AGENTS.md), [the tool/lifecycle contract](docs/mcp-workspaces.md), and [the invoice review demo](docs/demo-invoice-review.md).

```bash
npm run doctor                 # inspect installation, no helper launch
npm run doctor -- --connect    # check helper and permissions, no display creation
npm run check
npm test
npm run test:live               # GUI integration test; creates its own disposable display
npm run release:package         # clean committed source + built helper required
```

## Release status and origin

The first MCP release is **mcp-v0.1.0** for Apple Silicon. It is **ad-hoc signed, not notarized**. macOS 14 is the build deployment target; live validation was performed on macOS 27.0.1. Intel and every older macOS version have not been validated. If macOS blocks the download, use your normal Privacy & Security review process or build from source; the installer does not remove quarantine or bypass Gatekeeper.

This is an MIT-licensed fork of [chekusu/yomado](https://github.com/chekusu/yomado). The original GUI app, its updater, and its release numbers are separate. See [upstream documentation](README.upstream.md) and [LICENSE](LICENSE). Do not use upstream Yomado downloads to install this MCP server.
