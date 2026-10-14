#!/bin/bash
set -euo pipefail
ym_qa_source="$(cd "$(dirname "$0")" && pwd -P)"
source "$ym_qa_source/guard.sh"
ym_qa_build="${1:?Usage: build-helpers.sh output-directory}"
mkdir -p "$ym_qa_build/Companion.app/Contents/MacOS"
MACOSX_DEPLOYMENT_TARGET=14.0 /usr/bin/xcrun swiftc -O "$ym_qa_source/Companion.swift" -o "$ym_qa_build/Companion.app/Contents/MacOS/Companion"
MACOSX_DEPLOYMENT_TARGET=14.0 /usr/bin/xcrun swiftc -O "$ym_qa_source/Observe.swift" -o "$ym_qa_build/observe"
cat > "$ym_qa_build/Companion.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>org.yomado.qa.Companion</string>
<key>CFBundleExecutable</key><string>Companion</string>
<key>CFBundleName</key><string>QA Companion</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
/usr/bin/codesign --force --sign - "$ym_qa_build/Companion.app"
printf '%s\n' 'Built hosted-runner QA helpers.'
