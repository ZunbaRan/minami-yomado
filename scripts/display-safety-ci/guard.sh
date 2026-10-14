#!/bin/bash
set -euo pipefail
if [[ "${GITHUB_ACTIONS:-}" != true || "${RUNNER_ENVIRONMENT:-}" != github-hosted || "$(uname -s)" != Darwin ]]; then
  printf '%s\n' 'REFUSED: display mutation QA is restricted to disposable GitHub-hosted macOS.' >&2
  exit 64
fi
