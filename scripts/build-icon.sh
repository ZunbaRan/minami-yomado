#!/bin/bash
set -euo pipefail

# Repackage the approved Image Generation source into standard macOS sizes.
ym_icon_root="$(cd "$(dirname "$0")/.." && pwd -P)"
ym_icon_source="$ym_icon_root/app/Resources/night-window.png"
ym_icon_stage="$(mktemp -d "${TMPDIR:-/tmp}/Yomado-icon.XXXXXX")"
trap 'rm -rf "$ym_icon_stage"' EXIT
ym_icon_set="$ym_icon_stage/Yomado.iconset"
mkdir -p "$ym_icon_set"

while read -r ym_icon_name ym_icon_size; do
  /usr/bin/sips -z "$ym_icon_size" "$ym_icon_size" "$ym_icon_source" \
    --out "$ym_icon_set/$ym_icon_name.png" >/dev/null
done <<'SIZES'
icon_16x16 16
icon_16x16@2x 32
icon_32x32 32
icon_32x32@2x 64
icon_128x128 128
icon_128x128@2x 256
icon_256x256 256
icon_256x256@2x 512
icon_512x512 512
icon_512x512@2x 1024
SIZES

/usr/bin/iconutil -c icns "$ym_icon_set" -o "$ym_icon_root/app/Resources/Yomado.icns"
printf 'Packaged: app/Resources/Yomado.icns\n'
