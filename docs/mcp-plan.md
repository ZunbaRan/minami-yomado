# Initial implementation contract

Approved direction from the implementation conversation: fork Yomado into an MCP-first virtual-workspace manager, configure display settings through MCP, and provide independent live whole-display PiP. Preserve the distinction from Minami computer-use/browser automation.

The initial slice must implement:

- A stdio MCP adapter and independent persistent native helper, with no Minami runtime dependency or upstream GUI click automation.
- Persistent named workspace profiles; create/list/get/configure/start/stop/delete for resolution and HiDPI, while retaining upstream topology verification and a physical main display.
- Explicit per-window placement and original-position restoration. Never collect unrelated app windows, steal foreground, or report success without verified geometry.
- A ScreenCaptureKit whole-display stream and independently closable/resizable nonactivating PiP on a physical display; observable live/error/suspended state.
- MCP reconnect without losing live displays; explicit empty-only helper shutdown. Capture and Accessibility authorization remain native user permissions.
- A separate helper identity and state, no upstream auto-update dependency; keep MIT notices and original GUI intact.
- Automated protocol/profile validation and opt-in native integration checks. Verify two visible task windows, updates, restoration, HiDPI, and unchanged existing display layout.

This is an initial usable developer build. Whole-desktop viewing is read-only; interactive remote input, physical monitor power/main switching, recording/network streaming, durable crash recovery, and multi-agent input isolation are outside this slice. Application automation remains with Minami. Do not claim those features or unattended reliability.
