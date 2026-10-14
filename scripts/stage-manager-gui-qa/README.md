# Hosted Stage Manager GUI evidence

This harness is restricted to an ephemeral **GitHub-hosted macOS runner**. It
must never be run on a person's desktop. Every entry point checks
`GITHUB_ACTIONS=true` and `RUNNER_ENVIRONMENT=github-hosted`; no helper requests
or modifies Accessibility or Screen Recording permission.

The base and head jobs build exact revisions. A separately labeled
`activation-order-experiment` job applies and saves one explicit presentation
patch for comparison; its evidence is not attributed to the unchanged PR head.

Build the production base and PR revisions without changing their bundle IDs,
activation policy, window classes, or launch path. Build the helpers with
`build-helpers.sh <helper-directory>`. The helper compilation and every GUI
operation must happen on the runner, not on a developer's machine.

Run `setup-guest.sh <helper-directory> <evidence-directory>` for a bounded
guest-only setup attempt and capture of the actual Control Center. This writes
the Stage Manager and separate Spaces preferences and restarts only the fresh
runner's Dock. It does not change TCC or claim the new preferences took effect.

Before interpreting `phase1.sh`, inspect the actual system Stage Manager switch and
visible grouping behavior. A `GloballyEnabled` preference is insufficient:
`NSScreen.screensHaveSeparateSpaces` and Window Manager availability can block
activation. If a native settings change requires logout, complete that change
on the disposable runner and verify the new graphical login session. Never
edit TCC databases or treat a permission bypass as test setup. Only after
runtime confirmation set `YM_QA_STAGE_MANAGER_RUNTIME_CONFIRMED=true`. Without
that confirmation, the suite still gathers ordinary-window/full-screen
evidence but records Stage Manager as unverified.

Run `phase1.sh <production-app> <helper-directory> <evidence-directory> base`
and then the same command for `head`, using separate artifact directories.
The real Yomado binary is used, not preview mode or a recreated panel. It is
paired with one recognizable regular application that owns only its own
temporary window. The harness closes and reopens the production panel,
minimizes and reopens it, and requests the panel from the companion's native
full-screen Space. Closing the panel is checked to leave its process alive.
Before the production launch, a second separately identified regular app
(`QA Reference`, blue window) is activated and then `QA Companion` (red window)
is reactivated. These screenshots establish whether Stage Manager separates
ordinary apps at all. The real AppKit fixture also logs
`NSScreen.screensHaveSeparateSpaces` and its active state, avoiding reliance
on a command-line-only screen query. Reference is terminated after this check.

Evidence includes full desktop screenshots from the empty runner; CGWindow
metadata and AX trees are restricted to these two apps. A Dock observer checks
for the exact `yomado` Dock title or current bundle URL. Each observation must
read the Dock successfully, finish traversal, and find the regular Companion's
Dock icon as a positive control before an absent result can be interpreted.
Missing Dock processes, AX read errors, truncation, or a missing positive
control produce `unknown`, not an absent-icon result. The first flushed sample
is required before Yomado is launched.
The initial production launch uses LaunchServices, refusing a runner with an
existing Yomado process so cleanup cannot target an unrelated instance.

The observer records monotonic sample start/end times and the actual interval
between samples. Its 100 ms sleep is only a requested delay after each walk;
it is not a guaranteed 10 Hz observation rate. Absence from readable samples
does not prove that an icon never appeared between samples. The production
app's activation policy is recorded alongside those samples.
Sampling continues until a stop file is written after the final screenshot,
with a 240-second safety limit. A limit reached before the final capture is
incomplete evidence. Compare the final snapshot's monotonic timestamp with
the timeline's sample and termination timestamps when reviewing coverage.

`observe system-ui` captures the fresh runner's Control Center, System
Settings, and Mission Control accessibility trees for adaptive setup and
Desktop creation. It performs no input. System UI elements must be inspected
before using them; do not hardcode guessed screen coordinates.
The final phase enters Mission Control once, records its screenshot and AX
identifiers/enabled state, then closes it with Escape. It does not create or
rearrange Desktops in that phase.

## Acceptance boundary

The harness deliberately does **not** infer a Stage Manager group from a
collection-behavior bit, app activation policy, or `kCGWindowIsOnscreen` alone.
Review the screenshots for the companion moving into a separate Stage Manager
thumbnail when the head panel opens, compared with base; corroborate with
window bounds and actual system UI. A screenshot must show Stage Manager
actually operating before this can pass.

The ordinary Desktop phase uses the previously observed native Mission Control
identifiers `mc.spaces.add` and `mc.spaces.list`. It revalidates the current
tree, enabled state and AXPress action, requires exactly one initial Desktop,
creates a second, and selects it from the actual AX list. It requests the
existing panel from Desktop 2, then closes the panel and requests it again
from Desktop 2. Screenshots and a Mission Control capture distinguish returning
to the existing panel's Desktop from moving the panel. No guessed coordinates
or private Space-changing APIs are used. This remains evidence for review,
not an automatic merge approval. Manual grouping should also be inspected
separately if macOS grouping controls are available in the runner.

Do not upload unrelated user data, runner credentials, environment dumps,
app profiles, or local paths. Before publication review screenshots and logs;
use only the test fixture's generated content. The scripts neither merge a PR
nor publish a release.
