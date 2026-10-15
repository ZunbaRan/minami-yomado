# PR 6 hosted macOS GUI acceptance

All graphical entry points require both `GITHUB_ACTIONS=true` and
`RUNNER_ENVIRONMENT=github-hosted`. Run them only in disposable GitHub-hosted
macOS guests. Never execute them on a developer desktop or spoof these guards.
Local syntax/typechecking is allowed. The suite never modifies TCC.

The workflow separately checks out its QA harness and an immutable production
revision. Production code is built unchanged; its commit and executable hash
are recorded. QA drivers are not injected into the product binary. Experimental
scripts inherited from PR 2 are not invoked.

Two guests exercise the real Mission Control automatic Space-switching setting,
with its native checkbox on and off. Stage Manager setup is checked through
actual Control Center state and visual positive-control fixture applications.
Preference writes alone do not prove the resulting behavior.

## Required evidence

- Explicit open: Regular application, running Dock item, same visible panel.
- Explicit close: Accessory application, no running Dock item in a complete
  readable Dock tree, same product process and available menu-bar item.
- Real menu-bar reopening after close/demotion from another Desktop and from
  another application's native fullscreen Space. Preserve PID and panel identity
  and record which Desktop the panel actually occupies.
- Preserve intentionally created Stage Manager grouping through the tested
  lifecycle. Real minimize/restore must show `AXMinimized=true`; thumbnailing
  is not a substitute. A Dock click is valid only while a running or deliberately
  pinned item actually exists.
- Create a virtual display through the real product UI. Keep a separate fixture
  window rendering on that product-owned display while closing/reopening the
  control panel. Compare display identity, modes, bounds, original main-display
  topology, fixture bounds, and actual captured counter pixels over time.

The product-owned virtual-display suite is separate from synthetic topology
checks. It proves sustained rendering only for the exercised guest setup and
interval. It does not establish physical DisplayLink compatibility, arbitrary
application behavior, lock-screen operation, or independent keyboard/mouse input.

Screenshots are taken only on the empty disposable guests with fixture content.
Structural JSON assertions supplement actual screenshot/Space/fullscreen review;
a green Actions job alone is not final functional acceptance. Missing evidence,
blocked native controls, or a skipped scenario must remain explicitly unverified.

The suite cleans up only processes and artifacts it started. It does not merge
pull requests or publish releases. Review and filter evidence before public
posting; no personal-machine paths, credentials, account data or unrelated
content belong in public source or attachments.
