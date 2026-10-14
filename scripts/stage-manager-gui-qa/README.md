# Hosted Stage Manager GUI acceptance

This harness runs only in a disposable **GitHub-hosted macOS runner**. Every
GUI entry point checks `GITHUB_ACTIONS=true` and
`RUNNER_ENVIRONMENT=github-hosted`. It does not alter TCC or request permissions.
Never run a helper or scenario on a person's desktop. Local typechecking is
safe; helper execution belongs to the runner.

The workflow builds the exact production commit pinned in its matrix and
checks that production source remains unchanged. No experimental patch is
applied. Both jobs test the regular-application design: the Dock icon is now
expected, and the menu-bar icon must remain usable.

## Two fresh guests

`regular-default-spaces` verifies that the native Mission Control checkbox is
on. `regular-no-auto-spaces` turns off “When switching to an application, switch
to a Space with open windows for the application” using that actual named
System Settings accessibility control. The native helper records the real
checkbox value before and after; it does not infer success from a plist.
Both jobs stop if their intended setting cannot be confirmed. Preference
values and observed resulting Space behavior must both be reviewed.
[Apple documents this setting and its default behavior.](https://support.apple.com/guide/mac-help/mh14112/mac)

The earlier three-hypothesis matrix is preserved in QA history and its isolated
artifacts. `fullscreen-experiment.py` is not invoked in production acceptance.
An experiment's success does not substitute for an unchanged production test.

Stage Manager setup is separately observed through the real Control Center
switch and any onboarding sheet. A preference write is not proof that Stage
Manager is operating. Two regular fixture apps provide a visual positive
control: blue Reference and red Companion should alternate between the center
and thumbnail rail. The native fixture logs separate-Spaces and active state.

## Scenarios

- Cold launch the actual production app through LaunchServices. Refuse a
  preexisting product process so cleanup only targets this run's processes.
- Close the panel, then reopen through a real mouse click on its current AX
  menu-bar item and actual “打开控制面板” menu item. Keep PID/window evidence.
- Close again, then click the exact Dock item whose title and bundle URL match
  the running product. Verify reuse of the same process and panel window.
- Click the currently observed minimize button, then reopen by menu. Only
  `AXMinimized=true` proves true minimization; a Stage Manager thumbnail does
  not. Repeat with Stage Manager off to verify true minimize/restore.
- Put Companion into native full-screen and request Yomado via its revealed
  menu bar. Capture whether the panel appears on an ordinary desktop rather
  than over the full-screen app.
- Create and select Desktop 2 through current Mission Control AX controls.
  Request both an existing panel and a closed panel. Mission Control screenshots
  distinguish returning to Desktop 1 from moving the window to Desktop 2.
- Repeat a cold launch using an active native app's NSWorkspace launch handoff.
- Drag Companion's real identified Stage Manager thumbnail into Yomado's
  current stage. Switch to Reference, then reopen Yomado; inspect the paired
  thumbnail and both restored windows to verify manual-group preservation.
- Turn Stage Manager off through the actual Control Center checkbox, record
  `AXValue=0`, and verify menu opening plus true minimize/restore.

All mouse points come from current, uniquely identified AX controls or exact
owned CG windows. No guessed coordinates or private Space-changing API is used.
The manual-group guard returns `78` if its actual starting state is unsuitable;
that means blocked, not passed.

## Evidence and acceptance

Screenshots are captured from the empty guest with only fixture-generated
content. Observation includes owned-app AX/CG state and relevant system UI.
The Dock sampler requires a complete readable tree and a detected regular
Companion icon as positive control. Missing processes, read errors or truncated
walks produce `unknown`. The first flushed sample precedes product launch;
sampling stops after the final scenario, with a 240-second cap. It records
actual monotonic intervals. A requested 100 ms sleep is not guaranteed 10 Hz.

`check-regular-evidence.py` verifies bounded structural facts: regular policy,
visible panel, enabled menu-bar control, Dock identity/reopen, true off-mode
minimization, complete manual-group collection and sampler completion. Regular
activation policy must remain regular after each PID first reaches regular;
any earlier startup transients remain recorded explicitly. A startup transition
from the old bundle declaration is not a steady-state policy failure. These
checks do not infer Stage Manager groups from flags. A green job still requires
independent review of the actual positive-control, group, Desktop and full-screen
screenshots before product acceptance or merging.

Before public posting, inspect images and filter metadata. Do not publish raw
system trees, private paths, account names, credentials or unrelated data.
The harness does not merge PRs or publish releases.
