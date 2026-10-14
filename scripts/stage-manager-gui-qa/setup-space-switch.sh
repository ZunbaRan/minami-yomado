#!/bin/bash
set -euo pipefail
ym_qa_source="$(cd "$(dirname "$0")" && pwd -P)"
source "$ym_qa_source/guard.sh"
ym_space_helpers="${1:?missing helpers}"
ym_space_evidence="${2:?missing evidence directory}"
ym_space_mode="${3:?missing default/off mode}"
mkdir -p "$ym_space_evidence"
ym_space_code=0
"$ym_space_helpers/space-switch-setting" "$ym_space_mode" > "$ym_space_evidence/setting.json" 2> "$ym_space_evidence/setting.stderr" || ym_space_code=$?
"$ym_space_helpers/observe" system-ui > "$ym_space_evidence/settings-ax.json"
/usr/sbin/screencapture -x "$ym_space_evidence/settings.png"
# Only the disposable guest's settings app, opened above, is dismissed.
/usr/bin/osascript -e 'tell application "System Settings" to quit'
sleep 1
exit "$ym_space_code"
