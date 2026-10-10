# yomado

A virtual display for graphical agents on macOS.

[简体中文](README.zh-CN.md) · [MIT license](LICENSE)

Yomado gives applications such as Blender and Marvelous Designer an additional macOS display. Move the windows your agent needs onto it, then use your existing screenshot and computer-control tools to work there. No paid display utility is required.

![yomado usage concept: two dark physical monitors, an awake Mac, and a virtual desktop on the right with 3D and garment-design windows.](docs/images/yomado-usage.png)

*AI-generated usage illustration. Agent work belongs on the virtual display; operation with physical monitors off is still under validation.*

**Experimental prototype:** Yomado uses private macOS APIs. Compatibility can change with a system update. The goal is to keep graphical work available with a physical monitor off; actual monitor standby, power savings, agent operation after physical output is disabled, and long unattended operation have **not** been validated.

## What it does

- Creates a 1920 × 1080 or 2560 × 1440 virtual display, with optional HiDPI.
- Requests that the system and graphical desktop remain awake while the virtual display exists.
- Offers an optional, reversible trial that disables one selected physical display output.
- Includes a 15-second trial rollback, a recovery shortcut, and an independent recovery helper.

The virtual display belongs to your **existing login session**. It is not a separate operating system, user session, or isolated keyboard and mouse. Your agent and your own work share focus and input, so coordinate their use of the desktop. Yomado is not a remote desktop server or an agent: your existing tools still provide viewing, screenshots, and input.

## Build

Requires macOS and Xcode or the Command Line Tools. The app uses system frameworks only; there are no third-party runtime dependencies.

```sh
bash ./build.sh
```

Outputs:

```text
dist/Yomado.app
dist/Yomado.zip
```

The build script selects the active Xcode or Command Line Tools installation through `xcrun`. Set `YOMADO_DEVELOPER_DIR` to select another developer directory.

The native Apple Silicon build has been verified. The macOS 14 deployment target is a build setting, not a claim that every macOS 14+ system or Intel Mac is supported. This repository publishes source; it does not claim an available prebuilt release.

Builds receive an **ad hoc signature**, not an Apple Developer ID signature or notarization. Follow your Mac's normal security policies when choosing whether to run a local build.

## Use the virtual display

1. Open your locally built `Yomado.app` and choose a resolution. HiDPI doubles each pixel dimension: a 1920 × 1080 logical desktop becomes 3840 × 2160 pixels.
2. Create the virtual display. Physical outputs remain enabled, with their existing main display and positions retained. The new virtual display starts to the right of the physical displays.
3. Keep a physical monitor as your main display. In macOS Displays settings, choose where the virtual display belongs in your arrangement.
4. Move **only the agent's work windows** and necessary dialogs onto the virtual display. Leave your other windows on your physical monitors. Yomado does not automatically migrate third-party application windows.
5. Select the virtual display in your existing viewing or agent tools, if they support that selection. Verify a fresh target-app screenshot and an actual reversible input action before starting work.

Changing displays, window positions, or scaling can invalidate an agent's saved coordinates. Refresh its screenshot and window state after each change. A successful screenshot does not by itself prove that keyboard or mouse input works.

Keep Yomado running while using its virtual display. Closing the control panel leaves the menu-bar app running. Stopping the virtual display or quitting removes it after attempting physical-output recovery. Removing a display can make macOS reposition windows; if you manually made the virtual display the main display, Yomado must first switch back to an available physical display. There is no automatic login startup or reboot recovery.

Yomado does not change passwords, lock-screen policy, screen savers, or login settings. Its wake requests do not unlock a Mac. Screenshot and input permissions remain the responsibility of the tools that perform those actions.

## Optional physical-output trial

**This is an experimental action, not the default workflow.** It changes the main display and arrangement, which can cause macOS or applications to move other windows. Save your work first and test only while you can directly reach the Mac and monitor.

1. Verify that your existing tools can view and control the virtual display while the physical monitors are still on.
2. Select one physical display in Yomado. Disable mirroring for that display before testing.
3. Start the 15-second physical-output trial and accept its confirmation dialog. Yomado makes the virtual display the main display, moves its own control panel there, and requests that the selected physical output be disabled. Other physical outputs remain enabled.
4. Check the actual monitor and perform a fresh target-app screenshot and reversible input action on the virtual display. Confirm within the countdown only if you can still operate it. Otherwise, Yomado attempts recovery after 15 seconds.

Recover with **Control + Option + Command + R** (`⌃⌥⌘R`), the recovery button, or the menu-bar recovery command. Stopping or quitting also attempts recovery.

The separate `YomadoWatchdog` helper monitors an armed trial's app heartbeat and virtual-display availability. If the app exits, its heartbeat expires, or the virtual display becomes unavailable, the helper attempts to re-enable the recorded physical output. It never disables an output itself.

These recovery paths are **best effort**. An API request can fail or a monitor may not respond. Software-disabled output and a black screenshot do not establish that a monitor entered standby or used less power; Yomado cannot cut power or measure consumption. Recovery also cannot guarantee each application's previous window positions.

## Diagnostics and tests

A read-only interface and display inventory check:

```sh
./dist/Yomado.app/Contents/MacOS/Yomado --diagnose
```

Physical display serial numbers are redacted by default. The optional `--include-device-identifiers` flag includes them for local diagnosis. Inventory output still describes your display setup; inspect and sanitize it before sharing.

The build script compiles, ad hoc signs, and strictly verifies the staged bundle. It does **not** launch the app or run display tests.

Pure policy tests can run without creating a display or opening an application:

```sh
bash ./test.sh
```

These tests check display-placement and diagnostic-redaction policies. They do not exercise private APIs or prove that a live display configuration succeeds.

The following tests require an interactive macOS login session. **Do not run them automatically, in build-only CI, or while someone else is using the desktop.** They create and remove temporary displays and apply layout restoration, so windows may move. Save work and close other Yomado instances before running them.

```sh
./dist/Yomado.app/Contents/MacOS/Yomado --self-test ./test-output/standard
./dist/Yomado.app/Contents/MacOS/Yomado --self-test ./test-output/hidpi hidpi
./dist/Yomado.app/Contents/MacOS/Yomado --watchdog-test ./test-output/watchdog \
  ./dist/Yomado.app/Contents/MacOS/YomadoWatchdog
```

Lifecycle self-tests exercise a temporary virtual display, its dimensions, an app-owned AppKit view, virtual-output disable/re-enable, removal, and attempted layout restoration. The watchdog test uses a disposable process and a temporary virtual recovery target. Neither test deliberately disables a physical output.

Generated view images are **not** screenshots of Blender, Marvelous Designer, or another target application. Passing these tests does not validate an agent's input, physical monitor standby, energy savings, or unattended operation. Test receipts can contain display metadata; review them before sharing.

## Implementation

`app/Yomado.m` contains the AppKit app and test entry points. `app/Watchdog.m` contains the recovery helper; `bridge/VDVirtualDisplay.*` wraps the virtual-display interface. The application namespace is `dev.chekusu.yomado`.

The implementation uses private `CGVirtualDisplay` classes and dynamically discovers `CGSConfigureDisplayEnabled` / `SLSConfigureDisplayEnabled`. Feature availability is checked at runtime. Apple does not promise compatibility for these interfaces.

Contributions should preserve the distinction between creating a virtual display, changing display topology, and verifying real target-app operation. Keep diagnostics free of secrets and personal workflow data, and avoid running display-changing tests in automation.

## License

The [logo and usage illustration](docs/images/PROMPTS.md) were created with image generation; their prompts are included for reference.

[MIT](LICENSE).
