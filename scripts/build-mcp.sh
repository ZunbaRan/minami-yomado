#!/bin/bash
set -euo pipefail
ym_root="$(cd "$(dirname "$0")/.." && pwd -P)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Library/Developer/CommandLineTools}"
ym_stage="$(mktemp -d "${TMPDIR:-/tmp}/yomado-mcp-build.XXXXXX")"
trap 'rm -rf "$ym_stage"' EXIT
ym_bundle="$ym_stage/Minami Yomado.app"
mkdir -p "$ym_bundle/Contents/MacOS" "$ym_root/dist"
xcrun clang -fobjc-arc -Wall -Wextra -Werror -mmacosx-version-min=14.0 \
  -I "$ym_root/bridge" -I "$ym_root/native" \
  "$ym_root"/native/*.m "$ym_root/bridge/VDVirtualDisplay.m" "$ym_root/bridge/YMDisplayTopology.m" \
  -framework AppKit -framework ApplicationServices -framework CoreGraphics -framework ColorSync \
  -framework ScreenCaptureKit -framework AVFoundation -framework CoreMedia -framework QuartzCore \
  -o "$ym_bundle/Contents/MacOS/MinamiYomado"
cat > "$ym_bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.zunbaran.yomado.workspace</string>
<key>CFBundleName</key><string>Minami Yomado</string>
<key>CFBundleExecutable</key><string>MinamiYomado</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$ym_bundle"
codesign --verify --deep --strict "$ym_bundle"
# A running helper retains its old inode until explicitly shut down.
rm -rf "$ym_root/dist/Minami Yomado.app"
ditto "$ym_bundle" "$ym_root/dist/Minami Yomado.app"
printf 'Built %s\n' "$ym_root/dist/Minami Yomado.app"
