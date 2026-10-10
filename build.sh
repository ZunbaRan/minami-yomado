#!/bin/bash
set -euo pipefail

ym_root="$(cd "$(dirname "$0")" && pwd -P)"
ym_dist="$ym_root/dist"
ym_output="$ym_dist/Yomado.app"

if [ "${YOMADO_DEVELOPER_DIR:-}" != "" ]; then
  ym_clang="$(DEVELOPER_DIR="$YOMADO_DEVELOPER_DIR" /usr/bin/xcrun --sdk macosx --find clang)"
  ym_sdk="$(DEVELOPER_DIR="$YOMADO_DEVELOPER_DIR" /usr/bin/xcrun --sdk macosx --show-sdk-path)"
else
  ym_clang="$(/usr/bin/xcrun --sdk macosx --find clang)"
  ym_sdk="$(/usr/bin/xcrun --sdk macosx --show-sdk-path)"
fi

ym_stage="$(mktemp -d "${TMPDIR:-/tmp}/Yomado-build.XXXXXX")"
trap 'rm -rf "$ym_stage"' EXIT
ym_bundle="$ym_stage/Yomado.app"
mkdir -p "$ym_bundle/Contents/MacOS" "$ym_bundle/Contents/Resources"

ym_flags=(
  -fobjc-arc -Wall -Wextra -Werror -g0
  -isysroot "$ym_sdk" -mmacosx-version-min=14.0
  "-ffile-prefix-map=$ym_root=."
  "-fmacro-prefix-map=$ym_root=."
  "-fdebug-prefix-map=$ym_root=."
  "-ffile-prefix-map=$ym_stage=."
  "-fmacro-prefix-map=$ym_stage=."
  "-fdebug-prefix-map=$ym_stage=."
)

"$ym_clang" "${ym_flags[@]}" -I "$ym_root/bridge" \
  "$ym_root/app/Yomado.m" "$ym_root/bridge/VDVirtualDisplay.m" \
  -framework AppKit -framework CoreGraphics -framework IOKit -framework Carbon \
  -o "$ym_bundle/Contents/MacOS/Yomado"

"$ym_clang" "${ym_flags[@]}" "$ym_root/app/Watchdog.m" \
  -framework Foundation -framework CoreGraphics \
  -o "$ym_bundle/Contents/MacOS/YomadoWatchdog"

/bin/cp -X "$ym_root/Info.plist" "$ym_bundle/Contents/Info.plist"
/usr/bin/xattr -cr "$ym_bundle"
/usr/bin/codesign --force --sign - "$ym_bundle/Contents/MacOS/YomadoWatchdog"
/usr/bin/codesign --force --sign - "$ym_bundle"
/usr/bin/codesign --verify --strict "$ym_bundle/Contents/MacOS/YomadoWatchdog"
/usr/bin/codesign --verify --strict "$ym_bundle"

# Only generated artifacts in this repository's dist directory are replaced.
# Archive the verified staged bundle before destination metadata can be added.
mkdir -p "$ym_dist"
/usr/bin/ditto -c -k --norsrc --noextattr --keepParent \
  "$ym_bundle" "$ym_stage/Yomado.zip"
rm -rf "$ym_output"
/usr/bin/ditto --norsrc --noextattr "$ym_bundle" "$ym_output"
/bin/mv -f "$ym_stage/Yomado.zip" "$ym_dist/Yomado.zip"
printf 'Built: %s\nArchive: %s\n' "$ym_output" "$ym_dist/Yomado.zip"
