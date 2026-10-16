# MCP-managed workspaces and whole-desktop PiP

This fork adds an MCP-first service alongside the original Yomado application. It reuses Yomado's virtual-display bridge and topology verification. Its independent native helper owns the displays and renders whole-desktop PiP; it does not use Minami's PiP or require Minami to run. Minami can separately operate applications in a workspace.

## Build and configure Codex

Requires a logged-in, unlocked macOS 14+ graphical session, Command Line Tools, and Node.js 20+. Native Apple Silicon/macOS 27 is the current live-test environment; other OS/hardware combinations need validation. Virtual-display creation uses private macOS APIs.

```sh
npm ci
npm run build
codex mcp add yomado_workspaces -- node /absolute/path/to/yomado/mcp/server.mjs
```

Restart/reconnect the Codex session to discover the tools. Use an absolute Node path if the host cannot resolve `node`. The helper is built at `dist/Yomado Workspace.app`, with its own bundle identity `com.zunbaran.yomado.workspace`. The helper has no control-panel window, Dock icon, Sparkle dependency, or automatic updater. The original GUI and its updater remain separate and unchanged; do not build/install the original `Yomado.app` as the MCP service.

`service_status` reports permissions. macOS must grant Screen Recording for preview and Accessibility for placement to the responsible host/helper. The user grants permissions in System Settings; MCP does not bypass that step. No permission is needed for listing tools or editing stopped profiles.

The default private state directory is `~/Library/Application Support/yomado-mcp` (0700). `YOMADO_MCP_STATE_DIR` selects an isolated directory; keep the Unix socket path shorter than 104 bytes. The helper log and persisted profiles live there. The socket accepts only the owning user's connections. No TCP listener is opened.

## Workflow and tool contract

1. `workspace_list` and `window_list`: inspect display layout and choose explicitly authorized window/PID pairs.
2. `workspace_create {name,width,height,hidpi}`: create a **stopped** profile and return its stable `id`.
3. `workspace_start {workspace_id}`: create/verify an extended display without changing existing outputs.
4. `workspace_move_window {workspace_id,window_id,pid,x?,y?}`: move one window. `x`/`y` are local offsets inside the workspace; defaults center horizontally, 48pt from its top. Oversized windows shrink to fit. The first move must start fully contained within one physical display; spanning/partly off-screen origins are rejected before movement. Exact original bounds and AX identity are retained for restoration. Subsequent moves between owned workspaces preserve that origin. Unsupported/rejected positioning returns an error; inspect state and restore before retrying.
5. `preview_open {workspace_id,width?,height?,output_width?,fps?,shows_cursor?}`: open the independent viewer on the physical main display. Panel size defaults to 480×270 points; capture defaults to 1280px wide/up to 30 fps, with no audio. Output dimensions are capped at 3840px per side. An existing open preview is returned unchanged.
6. `preview_configure {workspace_id,width?,height?,x?,y?}`: change panel bounds. These coordinates are global screen points from the physical main screen's top-left, constrained to its usable area. Close/reopen to change capture resolution/FPS/cursor.
7. `workspace_get`: settings, running display ID/bounds, tracked-window count, and preview state (`starting`, `live`, `suspended`, `error`, `closed`), frame count and age. A static desktop can legitimately have an old last-complete-frame timestamp.
8. `preview_close`: stop viewing, leaving the workspace alive. The native window's close button has the same effect.
9. `workspace_restore`: return this workspace's tracked windows to their exact recorded physical placement. Errors retain checkpoints. Closed windows release their records.
10. `workspace_stop`: remove an empty display and verify survivor topology, retaining the profile. It refuses unresolved window checkpoints/ordinary occupants. `workspace_destroy` deletes a stopped profile.

`workspace_configure` accepts name, width, height and HiDPI. Resolution/HiDPI changes require a stopped profile. Renaming a running profile changes its stored label; the OS display name changes on the next start. Logical dimensions must be at least 320×240, at most 8192 physical pixels per dimension, and at most 32 million pixels. HiDPI doubles pixel dimensions. Display refresh is currently fixed at 60 Hz, matching the upstream bridge; capture FPS is independently configurable.

`workspace_recover` retries a failed topology recovery. An unrelated user display change can prevent automatic writes; the original topology module preserves that refusal. Keep physical displays enabled and a physical display main. Physical monitor power switching, making a virtual display main, upstream application updates, and app-wide collection are intentionally outside this service's tool surface.

## Process lifetime and recovery

`Codex -> stdio MCP adapter -> private Unix socket -> native AppKit helper -> CGVirtualDisplay / ScreenCaptureKit`

One native helper owns profiles and live displays for each state directory. MCP clients may reconnect without interrupting them. A filesystem lock serializes helper startup; a single operation queue serializes management commands while the AppKit event loop stays responsive. Failed/timed-out mutations are not automatically replayed: inspect state before retrying.

`service_shutdown` works only when all owned displays are stopped and topology recovery is resolved. It prevents subsequent requests while shutting down. Before rebuilding/replacing an active helper, restore windows, stop its displays, call shutdown, and wait for it to exit. Merely rebuilding the bundle does not hot-reload a running helper.

Profiles persist across helper restarts. Live displays, capture sessions, and exact window recovery checkpoints are **in-memory** in this initial version. An unexpected helper crash removes its virtual displays; macOS may relocate windows, and exact placement recovery is not guaranteed. There is no crash-recovery journal or unattended-operation guarantee yet.

## Viewing semantics and boundaries

The viewer captures the virtual display's actual composition: desktop, menu bar, visible windows and dialogs on that display. It does not capture invisible/minimized windows or dialogs that appear on a different display/Space. Some managed browser hosts deliberately hide their windows while still supporting window-level capture; whole-display preview will not reveal those hidden windows.

PiP is read-only. It uses a nonactivating floating AppKit panel and a ScreenCaptureKit display stream feeding `AVSampleBufferDisplayLayer`. The helper excludes its own app from capture and keeps the viewer off its source display. Capture failure/suspension clears stale imagery. A preview does not need Minami; Minami is an optional input provider. The virtual display shares macOS focus/keyboard/pointer and is not an independent input seat or VM.

## Verification

```sh
npm run build
npm run check
npm test             # validation, MCP transport, persistence/reconnect; no display creation
npm run test:live    # opt-in: creates/moves only its two disposable native fixture windows
DEVELOPER_DIR=/Library/Developer/CommandLineTools YOMADO_DEVELOPER_DIR=/Library/Developer/CommandLineTools ./test.sh
```

Upstream tests require `DEVELOPER_DIR=/Library/Developer/CommandLineTools ./scripts/fetch-sparkle.sh` once. The MCP build itself does not need Sparkle.

Live validation on 2026-10-16: 1920×1080 display creation, two scoped native-window moves, independent PiP showing both windows and advancing clocks, Minami AX clicks reflected in both counters, refusal to stop an occupied workspace, exact window restoration, PiP close preserving the workspace, 1280×720 HiDPI (2560×1440 pixels), preview resizing, and unchanged physical display geometry after cleanup. Sleep/wake, long unattended sessions, locked sessions and other OS/hardware remain unvalidated.
