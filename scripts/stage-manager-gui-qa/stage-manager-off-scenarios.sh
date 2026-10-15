#!/bin/bash
# Optional terminal acceptance evidence; never called by phase1 implicitly.
set -euo pipefail
ym_qa_source="$(cd "$(dirname "$0")" && pwd -P)"
source "$ym_qa_source/guard.sh"
ym_off_helpers="${1:?Usage: stage-manager-off-scenarios.sh helpers evidence companion-control-directory owned-yomado-pid}"
ym_off_evidence="${2:?missing evidence directory}"
ym_off_control="${3:?missing Companion control directory}"
ym_off_product_pid="${4:?missing owned Yomado PID}"
[[ "$("$ym_off_helpers/observe" pid dev.chekusu.yomado)" == "$ym_off_product_pid" ]]
mkdir -p "$ym_off_evidence"
ym_off_capture() {
  /bin/bash "$ym_qa_source/capture-lifecycle.sh" "$ym_off_helpers" "$ym_off_evidence" "$1" "${2:-}"
}
ym_off_capture 01-before-disable
"$ym_off_helpers/stage-manager-action" off > "$ym_off_evidence/02-disable-action.txt"
sleep 2
"$ym_off_helpers/observe" system-ui > "$ym_off_evidence/02-control-center-value.json"
ym_off_capture 02-control-center-off
/usr/bin/osascript -e 'tell application "System Events" to key code 53'
printf '{"nonce":"%s","command":"show"}\n' "$(/usr/bin/uuidgen)" > "$ym_off_control/command.tmp"
/bin/mv "$ym_off_control/command.tmp" "$ym_off_control/command.json"
sleep 2
ym_off_capture 03-companion-stage-manager-off
"$ym_off_helpers/panel-menu-actions" "$ym_off_product_pid" open > "$ym_off_evidence/04-menu-open-action.json"
sleep 1
ym_off_capture 04-menu-open
"$ym_off_helpers/panel-menu-actions" "$ym_off_product_pid" select-open-panel > "$ym_off_evidence/05-menu-select-action.json"
sleep 3
ym_off_capture 05-panel-stage-manager-off 0
"$ym_off_helpers/panel-window-actions" "$ym_off_product_pid" minimize > "$ym_off_evidence/06-minimize-action.json"
sleep 2
ym_off_capture 06-minimized-stage-manager-off
"$ym_off_helpers/panel-menu-actions" "$ym_off_product_pid" open > "$ym_off_evidence/07-restore-menu-open-action.json"
sleep 1
ym_off_capture 07-restore-menu-open
"$ym_off_helpers/panel-menu-actions" "$ym_off_product_pid" select-open-panel > "$ym_off_evidence/08-restore-menu-select-action.json"
sleep 3
ym_off_capture 08-restored-after-minimize 0
/bin/bash "$ym_qa_source/close-owned-panel.sh" "$ym_off_helpers" "$ym_off_product_pid" > "$ym_off_evidence/09-close-action.json"
sleep 2
ym_off_capture 09-closed-stage-manager-off 1
"$ym_off_helpers/panel-menu-actions" "$ym_off_product_pid" open > "$ym_off_evidence/10-menu-open-action.json"
sleep 1
ym_off_capture 10-menu-open
"$ym_off_helpers/panel-menu-actions" "$ym_off_product_pid" select-open-panel > "$ym_off_evidence/11-menu-select-action.json"
sleep 3
ym_off_capture 11-reopened-stage-manager-off 0
printf '%s\n' '{"collectionComplete":true,"stageManagerDisabled":"verify actual Control Center AXValue=0 and screenshot","panelVisibility":"requires real screenshot and current owned window evidence","noAutomaticPass":true,"terminalSetting":"Stage Manager left off in disposable runner"}' \
  > "$ym_off_evidence/collection-status.json"
