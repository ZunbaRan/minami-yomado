# Hosted Stage Manager GUI evidence

This harness is restricted to an ephemeral **GitHub-hosted macOS runner**. It
must never be run on a person's desktop. Every entry point checks
`GITHUB_ACTIONS=true` and `RUNNER_ENVIRONMENT=github-hosted`; no helper requests
or modifies Accessibility or Screen Recording permission.

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

Evidence includes full desktop screenshots from the empty runner; CGWindow
metadata and AX trees are restricted to these two apps. A Dock observer checks
for the exact `yomado` Dock title every 100 ms. Absence from samples is evidence
at that sampling rate, not proof that an arbitrarily brief icon never appeared.
The production app's activation policy is recorded alongside those samples.

`observe system-ui` captures the fresh runner's Control Center, System
Settings, and Mission Control accessibility trees for adaptive setup and
Desktop creation. It performs no input. System UI elements must be inspected
before using them; do not hardcode guessed screen coordinates.

## Acceptance boundary

The harness deliberately does **not** infer a Stage Manager group from a
collection-behavior bit, app activation policy, or `kCGWindowIsOnscreen` alone.
Review the screenshots for the companion moving into a separate Stage Manager
thumbnail when the head panel opens, compared with base; corroborate with
window bounds and actual system UI. A screenshot must show Stage Manager
actually operating before this can pass.

Two ordinary Desktops still need a Mission Control test: create Desktop 2 in
the runner's inspected native UI, keep the companion there, request the
existing Yomado panel, record which desktop becomes active, and verify that
the panel is accessible. Test closing and reopening on Desktop 2 as well.
The native full-screen phase does not substitute for this ordinary Desktop
test. Any failed or unavailable scenario stays pending, and does not authorize
a merge. Manual grouping should also be inspected separately if macOS grouping
controls are available in the runner.

Do not upload unrelated user data, runner credentials, environment dumps,
app profiles, or local paths. Before publication review screenshots and logs;
use only the test fixture's generated content. The scripts neither merge a PR
nor publish a release.
