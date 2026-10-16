#!/bin/bash
set -euo pipefail
if [[ "${1:-}" == "--help" ]]; then
  printf 'Usage: bash install.sh [--codex] [--prefix DIRECTORY]\nDownloads the pinned Apple Silicon release, verifies SHA-256, then installs MCP. Requires Node.js 20+.\n'
  exit 0
fi
[[ "$(uname -s)" == Darwin && "$(uname -m)" == arm64 ]] || { echo 'The prebuilt release requires an Apple Silicon Mac. See source-build instructions for other systems.' >&2; exit 1; }
command -v node >/dev/null || { echo 'Install Node.js 20+ first, then rerun this command.' >&2; exit 1; }
node -e 'if (+process.versions.node.split(".")[0] < 20) process.exit(1)' || { echo 'Node.js 20+ is required.' >&2; exit 1; }
ym_version=0.1.0
ym_asset="minami-yomado-${ym_version}-macos-arm64.zip"
ym_url="https://github.com/ZunbaRan/minami-yomado/releases/download/mcp-v${ym_version}"
ym_tmp="$(mktemp -d "${TMPDIR:-/tmp}/minami-yomado-install.XXXXXX")"
trap 'rm -rf "$ym_tmp"' EXIT
curl --fail --location --proto '=https' --tlsv1.2 "$ym_url/$ym_asset" -o "$ym_tmp/$ym_asset"
curl --fail --location --proto '=https' --tlsv1.2 "$ym_url/SHA256SUMS" -o "$ym_tmp/SHA256SUMS"
(cd "$ym_tmp" && shasum -a 256 -c SHA256SUMS)
ditto -x -k "$ym_tmp/$ym_asset" "$ym_tmp"
node "$ym_tmp/minami-yomado/scripts/install.mjs" "$@"
