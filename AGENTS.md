# Working with Minami Yomado

## Install / connect

- This repository is `ZunbaRan/minami-yomado`; upstream is `chekusu/yomado`. Always pass `--repo ZunbaRan/minami-yomado` for GitHub release/PR mutations. MCP release tags use `mcp-v*`.
- Start with README.md and docs/quickstart.md. The original `skills/yomado` and `README.upstream*` describe the upstream GUI, not this MCP workflow.
- Binary release: run `bash scripts/install.sh --codex`, or omit `--codex` for other clients. Source checkout: `npm ci --ignore-scripts && npm run build`, then `npm run setup -- --codex`.
- `npm run doctor` is non-launching. `npm run doctor -- --connect` starts/connects to the helper and checks permissions without creating displays. The user grants macOS permissions.

## Operational contract

1. Inspect `service_status`, `workspace_list`, and `window_list`. Do not infer task ownership from a familiar name alone.
2. Create a stopped profile; configure it, then start it. Keep the physical main display enabled and unchanged.
3. Move only authorized exact PID/window-ID pairs. Keep the helper running so restoration checkpoints survive.
4. Open ONE compact PiP and keep it open during work. Omit width/height unless initial sizing was explicitly requested. Respect saved size/position. Never close/reopen or enlarge it between actions, or reopen a viewer the user closed without a request to view it.
5. Use Minami or another verified computer-use tool for app input. PiP is a read-only whole-display view; it does not isolate focus/keyboard/mouse.
6. Save work, restore moved windows, then stop a workspace only when cleanup is requested. Do not shut down unrelated workspaces. If recovery fails, leave the display running and report the unresolved windows.
7. Inspect state after timeout/transport errors; do not blindly retry mutations.

## Development / release

- Native: `native/`; MCP: `mcp/`; setup and distribution: `scripts/`. Preserve upstream bridge attribution and license.
- Before replacing the helper: restore windows, stop owned displays, call `service_shutdown`, and wait for exit. Never kill a helper that owns active workspaces.
- Checks: `npm run build`, `npm run check`, `npm test`. `npm run test:live` needs an unlocked GUI and permissions and creates its own disposable fixtures/display. Run live checks for display, placement or preview changes.
- Packaging: clean committed source, arm64 macOS, `npm run release:package`. Verify the archive from a fresh extracted directory and an isolated installation/config prefix. Publish ZIP, SHA256SUMS and install.sh with notes stating signature/notarization and tested OS accurately.
- Keep stdout clean for the MCP stdio protocol; diagnostic output belongs on stderr or in the separate doctor command.
