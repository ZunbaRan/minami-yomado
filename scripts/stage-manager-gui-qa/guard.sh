#!/bin/bash
# Source this before any graphical operation. This suite is never a local test.
set -euo pipefail
if [[ "${GITHUB_ACTIONS:-}" != true || "${RUNNER_ENVIRONMENT:-}" != github-hosted ]]; then
  printf '%s\n' 'REFUSED: graphical QA requires a disposable GitHub-hosted runner.' >&2
  exit 64
fi
if [[ "$(/usr/bin/uname -s)" != Darwin ]]; then
  printf '%s\n' 'REFUSED: graphical QA requires macOS.' >&2
  exit 64
fi
