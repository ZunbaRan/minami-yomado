#!/bin/bash
set -euo pipefail

# Render only the menu glyph into memory; never launch yomado or create UI.
ym_icon_test_root="$(cd "$(dirname "$0")/.." && pwd -P)"
ym_icon_test_stage="$(mktemp -d "${TMPDIR:-/tmp}/Yomado-menu-icon-tests.XXXXXX")"
trap 'rm -rf "$ym_icon_test_stage"' EXIT
ym_icon_test_developer="${YOMADO_DEVELOPER_DIR:-$(xcode-select -p)}"
ym_icon_test_clang="$(DEVELOPER_DIR="$ym_icon_test_developer" /usr/bin/xcrun --find clang)"
ym_icon_test_sdk="$(DEVELOPER_DIR="$ym_icon_test_developer" /usr/bin/xcrun --sdk macosx --show-sdk-path)"

"$ym_icon_test_clang" -fobjc-arc -Wall -Wextra -Werror -isysroot "$ym_icon_test_sdk" \
  -mmacosx-version-min=14.0 \
  -ffile-prefix-map="$ym_icon_test_root"=. -fmacro-prefix-map="$ym_icon_test_root"=. \
  -I "$ym_icon_test_root/app" "$ym_icon_test_root/tests/MenuBarIconTests.m" \
  "$ym_icon_test_root/app/MenuBarIcon.m" \
  -framework AppKit -o "$ym_icon_test_stage/MenuBarIconTests"
"$ym_icon_test_stage/MenuBarIconTests"
