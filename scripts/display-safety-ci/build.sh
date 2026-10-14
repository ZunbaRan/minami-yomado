#!/bin/bash
# Compilation only; this may run locally. Executable refuses local execution.
set -euo pipefail
ym_ci_source="$(cd "$(dirname "$0")" && pwd -P)"
ym_ci_production="${1:?production checkout required}"
ym_ci_output="${2:?output path required}"
ym_ci_tmp="$(mktemp -d "${TMPDIR:-/tmp}/yomado-display-ci-build.XXXXXX")"
trap 'rm -rf "$ym_ci_tmp"' EXIT
ym_ci_flags=(-fobjc-arc -Wall -Wextra -Werror -g0 -mmacosx-version-min=14.0 -I "$ym_ci_production/bridge" -I "$ym_ci_production/app")
xcrun clang "${ym_ci_flags[@]}" -Dmain=YMUnusedApplicationMain -c "$ym_ci_production/app/Yomado.m" -o "$ym_ci_tmp/Yomado.o"
xcrun clang "${ym_ci_flags[@]}" "$ym_ci_source/DisplaySafetyCI.m" "$ym_ci_tmp/Yomado.o" \
  "$ym_ci_production/app/ControlUI.m" "$ym_ci_production/app/WindowRecovery.m" \
  "$ym_ci_production/app/UpdateChecker.m" "$ym_ci_production/app/MenuBarIcon.m" "$ym_ci_production/app/PanelPresentation.m" \
  "$ym_ci_production/app/AppWorkspace.m" "$ym_ci_production/app/AppWorkspaceView.m" \
  "$ym_ci_production/bridge/VDVirtualDisplay.m" "$ym_ci_production/bridge/YMDisplayTopology.m" \
  -framework AppKit -framework CoreGraphics -framework IOKit -framework Carbon -framework ApplicationServices -framework QuartzCore -framework ColorSync \
  -o "$ym_ci_output"
