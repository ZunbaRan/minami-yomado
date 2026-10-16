# Install and start Minami Yomado MCP

## Choose your installation

The prebuilt release is for **Apple Silicon macOS**, with **Node.js 20+** installed. It bundles the native helper and all production Node dependencies. No API key, npm, Xcode, Minami installation or upstream Yomado app is required to install it. An app automation tool such as Minami computer-use is needed to operate applications after placing their windows.

The binary has a macOS 14 deployment target; actual live testing was on macOS 27.0.1. It is ad-hoc signed and **not notarized**. Use your normal macOS Privacy & Security review process if blocked, or build from source. We do not remove quarantine or bypass Gatekeeper. Managed company Macs may require administrator approval.

### Codex CLI: quick install

```bash
curl -fsSL https://raw.githubusercontent.com/ZunbaRan/minami-yomado/mcp-v0.1.0/scripts/install.sh -o /tmp/minami-yomado-install.sh
bash /tmp/minami-yomado-install.sh --codex
```

The script downloads the pinned `mcp-v0.1.0` ZIP and `SHA256SUMS` over HTTPS, verifies SHA-256, extracts it into a temporary directory, and copies the runtime into `~/.local/share/minami-yomado/releases/`. A stable `current` symlink selects the installed version. It registers only the `minami_yomado` server via `codex mcp add`, using the current Node executable's absolute path. It does not modify other MCP entries.

Start a new Codex session. Confirm registration with:

```bash
codex mcp get minami_yomado
```

If Node is later removed/upgraded at that absolute path, rerun installation using the new Node executable to update the registration.

### Manual download / other agents

1. Download `minami-yomado-0.1.0-macos-arm64.zip` and `SHA256SUMS` from the [release](https://github.com/ZunbaRan/minami-yomado/releases/tag/mcp-v0.1.0).
2. In the download directory, run `shasum -a 256 -c SHA256SUMS`.
3. Extract the ZIP and run:

```bash
cd minami-yomado
node scripts/install.mjs
```

The installer prints JSON containing `mcpServers.minami_yomado` with absolute `command` and `args`. Merge that entry into your client's MCP settings; do not replace unrelated entries. A copy is saved in `~/.local/share/minami-yomado/mcp-config.json`. Clients with a different configuration schema should use the same command and argument as a **stdio** server, not an HTTP URL.

`--prefix /absolute/path` changes the install directory. For Codex registration add `--codex`. Neither method creates a virtual display during installation.

### Source build

Install Node.js 20+ and Xcode Command Line Tools (`xcode-select --install` if needed), then:

```bash
git clone https://github.com/ZunbaRan/minami-yomado.git
cd minami-yomado
npm ci --ignore-scripts
npm run build
npm run setup -- --codex
```

The upstream `build.sh` builds a different GUI product. Use `npm run build` for this MCP helper. Intel source builds are experimental and unvalidated; no Intel release binary is supplied.

## First connection and macOS permissions

Inspect the installation without launching anything:

```bash
node "$HOME/.local/share/minami-yomado/current/scripts/doctor.mjs"
```

Check the helper and permissions, without creating any displays:

```bash
node "$HOME/.local/share/minami-yomado/current/scripts/doctor.mjs" --connect
```

The user must approve Accessibility / Device Control & Data Access and Screen Recording for the responsible host/helper in System Settings. Labels differ by macOS version and permissions can be attributed to the terminal or agent host. Follow the OS entry and the diagnostic result; do not grant permissions to an unrelated app. The helper bundle is:

```text
~/.local/share/minami-yomado/current/dist/Minami Yomado.app
```

If adding the helper manually in Settings, navigate into this installation and select that app. Reconnect the host/helper after changing permissions if macOS requests it. The installer and agent never grant permissions automatically.

## A safe first task

Ask the agent:

> Call service_status and workspace_list. If permissions are ready, create a workspace named “Agent Work” at 1920×1080, start it, and open its compact PiP without supplying width or height. Leave my other windows alone. Keep one viewer open and respect my resized dimensions. Tell me when it is ready.

A blank desktop in PiP is expected until task windows are moved. Next identify exact task window IDs with `window_list`, then move them with `workspace_move_window`. Use application screenshot/input tools to verify and perform the actual task. Whole-desktop PiP only shows visible, non-minimized windows on that display.

When finished: save work, call `workspace_restore`, then `workspace_stop`. `preview_close` only closes the viewer. Disconnecting MCP leaves the helper and workspace running. Never force-stop a workspace containing unrelated windows.

## Troubleshooting

| Symptom | Action |
| --- | --- |
| MCP is absent in the current session | Start a new agent session; check `codex mcp get minami_yomado`. |
| `node` or `codex` not found | Install/add the executable to PATH. Use manual JSON setup if not using Codex. |
| Helper missing | Extract the complete release, or run `npm run build` in a source checkout. |
| Capture/control permission false | The user grants the missing permission in System Settings, then reconnects. |
| Preview remains blank | Inspect `workspace_get.preview.state/error`; verify a visible window is on that exact display. |
| Installer refuses an active workspace | Save work, restore task windows, stop owned workspaces, then retry. It will not interrupt active work. |
| `.install-lock` already exists | Check for an installer still running. Remove only a confirmed stale lock directory before retrying. |
| PiP is closed | Reopen only when the user asks to view it. Saved geometry takes precedence over old open arguments. |
| Permission/state path error | Default state is `~/Library/Application Support/yomado-mcp`, owned by the current user with mode 0700. Do not delete active helper state. |

## Upgrade and uninstall

Use the installer from the desired release after restoring windows and stopping active workspaces. It switches `current` to a newly copied version and retains previous runtime directories; workspace profiles and PiP preferences stay in the separate state directory. It shuts down an idle old helper so the next connection starts the new binary.

To uninstall, first restore windows, stop workspaces, and call `service_shutdown`. Remove the MCP entry (`codex mcp remove minami_yomado` for Codex), then remove only `~/.local/share/minami-yomado` or your explicit install prefix. Keep the state directory if you want to retain stopped workspace profiles and PiP preferences. Do not remove the original `/Applications/Yomado.app` as part of uninstalling this MCP; it is a separate application.

See [the complete lifecycle/tool contract](mcp-workspaces.md) and [agent instructions](../AGENTS.md).
