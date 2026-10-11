#!/bin/bash
set -euo pipefail

ym_update_root="$(cd "$(dirname "$0")/.." && pwd -P)"
ym_update_stage="$(mktemp -d "${TMPDIR:-/tmp}/Yomado-update-tests.XXXXXX")"
trap 'rm -rf "$ym_update_stage"' EXIT
ym_update_developer="${YOMADO_DEVELOPER_DIR:-$(xcode-select -p)}"
ym_update_clang="$(DEVELOPER_DIR="$ym_update_developer" /usr/bin/xcrun --find clang)"
ym_update_sdk="$(DEVELOPER_DIR="$ym_update_developer" /usr/bin/xcrun --sdk macosx --show-sdk-path)"

"$ym_update_clang" -fobjc-arc -Wall -Wextra -Werror -isysroot "$ym_update_sdk" \
  -mmacosx-version-min=14.0 \
  -ffile-prefix-map="$ym_update_root"=. -fmacro-prefix-map="$ym_update_root"=. \
  -I "$ym_update_root/app" "$ym_update_root/tests/UpdateCheckerTests.m" \
  "$ym_update_root/app/UpdateChecker.m" \
  -framework Foundation -o "$ym_update_stage/UpdateCheckerTests"
"$ym_update_stage/UpdateCheckerTests"
