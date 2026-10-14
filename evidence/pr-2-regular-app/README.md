# PR #2: regular-app runtime acceptance

Production revision: `3776ed9c5ec1fb49260bf3400da1492210dfa091`. QA revision: `5b33beaac5e5de5c88e5f4b6497fbbd6c73695fd`.

[Final hosted run](https://github.com/chekusu/yomado/actions/runs/38516093493) · [PR #2](https://github.com/chekusu/yomado/pull/2) · [Machine-readable summary](acceptance.json)

The normal interactive app now uses a regular activation policy and a primary control-panel window. It has a Dock icon and retains its menu-bar icon. Closing the panel keeps the app running. This is the accepted product design; the earlier accessory-policy evidence describes a rejected implementation.

All GUI tests ran in disposable GitHub-hosted macOS 26.6.2 (25G83) sessions, with one 1024 × 768 display at scale 1 and dedicated fixture apps. Each guest built the exact production revision without an experimental patch. No personal desktop or unrelated windows were used. The original screenshots below contain only the test guests.

## Results

The actual System Settings checkbox for switching to an application's Space was verified as **1** in one guest and **0** in the other. Each guest passed **37/37** structural checks. The implementation agent and a separate reviewer inspected the actual screenshots, native AX state, window identity and Space evidence; a green evidence-collection job alone was not treated as acceptance.

| Scenario | Automatic Space switching on | Automatic Space switching off |
| --- | --- | --- |
| Stage Manager open/menu reopen creates an independent group | Pass | Pass |
| User-created Yomado + Companion group survives leaving and reopening | Pass | Pass |
| Existing and closed panel opened from Desktop 2 | Returns to original Desktop 1 | Returns to original Desktop 1 |
| Menu open while Companion is in native fullscreen | Original panel becomes visible | Original panel becomes visible |
| Close then click the native Dock icon | Same PID and window | Same PID and window |
| Stage Manager off: genuine minimize, then menu restore | AXMinimized false → true → false | AXMinimized false → true → false |

Fullscreen retrieval changes the active Space to the panel's original desktop. It does not move the companion window out of fullscreen. Cross-Desktop reopening likewise reuses the original panel rather than moving it into Desktop 2. Ordinary menu/Dock/fullscreen/Spaces checks retained PID/window 3222/84 in the default guest and 4628/83 in the no-auto-switch guest. A later cold launch used for manual grouping and minimize tests retained 5538/236 and 6936/229 respectively.

Build with warnings treated as errors, ad hoc signature verification, 618 pure panel-geometry assertions and a public-diff privacy check also passed.

## Original screenshot evidence

| Scene | Automatic switching on | Automatic switching off |
| --- | --- | --- |
| Independent Stage Manager group | [Image](regular-default-spaces/independent-stage.png) | [Image](regular-no-auto-spaces/independent-stage.png) |
| Native Dock reopen | [Image](regular-default-spaces/dock-reopen.png) | [Image](regular-no-auto-spaces/dock-reopen.png) |
| Companion in fullscreen before request | [Image](regular-default-spaces/fullscreen-before.png) | [Image](regular-no-auto-spaces/fullscreen-before.png) |
| Original panel retrieved from fullscreen | [Image](regular-default-spaces/fullscreen-return.png) | [Image](regular-no-auto-spaces/fullscreen-return.png) |
| Closed panel reopened from Desktop 2 | [Image](regular-default-spaces/desktop2-return.png) | [Image](regular-no-auto-spaces/desktop2-return.png) |
| Manual pair after switching to Reference | [Image](regular-default-spaces/manual-group-away.png) | [Image](regular-no-auto-spaces/manual-group-away.png) |
| Manual pair restored together | [Image](regular-default-spaces/manual-group-return.png) | [Image](regular-no-auto-spaces/manual-group-return.png) |
| Genuine minimization with Stage Manager off | [Image](regular-default-spaces/minimized.png) | [Image](regular-no-auto-spaces/minimized.png) |
| Same panel restored after minimization | [Image](regular-default-spaces/minimize-restored.png) | [Image](regular-no-auto-spaces/minimize-restored.png) |

## Scope and limitations

- This is actual hosted macOS 26.6.2 GUI validation, not validation of the reporter's macOS 27.2 or a physical multiple-display layout.
- Stage Manager-on thumbnailing is not called genuine minimization. Genuine minimization was verified separately with Stage Manager disabled.
- Dock presence is intended. Policy observations had maximum sample gaps of approximately 3.24 s and 0.43 s; they do not establish frame-perfect startup behavior.
- The CLI/self-test modes keep their prior activation policies. The installed app, displays, power, permissions and other user windows were not changed.
- This source fix does not publish a new binary or release. It does not claim a Dock-free solution to the original issue.
