#!/bin/bash
set -euo pipefail
ym_qa_source="$(cd "$(dirname "$0")" && pwd -P)"
source "$ym_qa_source/guard.sh"
ym_qa_app="${1:?missing app path}"
ym_qa_helpers="${2:?missing helper directory}"
ym_qa_evidence="${3:?missing evidence directory}"
ym_qa_yomado_pid="${4:?missing owned Yomado PID}"
mkdir -p "$ym_qa_evidence"
ym_desktop_capture() {
  /bin/bash "$ym_qa_source/capture-lifecycle.sh" "$ym_qa_helpers" "$ym_qa_evidence" "$1" "${2:-}"
}
ym_desktop_mc() { /usr/bin/open -a 'Mission Control'; sleep 2; }
ym_desktop_escape() { /usr/bin/osascript -e 'tell application "System Events" to key code 53'; sleep 1; }
ym_desktop_select_second() {
  ym_desktop_mc
  "$ym_qa_helpers/desktop-actions" select 2 > "$ym_qa_evidence/$1-selection.json"
  sleep 3
}
ym_desktop_panel_menu() {
  local label="$1"
  "$ym_qa_helpers/panel-menu-actions" "$ym_qa_yomado_pid" open > "$ym_qa_evidence/$label-menu-open-action.json"
  sleep 1
  ym_desktop_capture "$label-menu-open"
  "$ym_qa_helpers/panel-menu-actions" "$ym_qa_yomado_pid" select-open-panel > "$ym_qa_evidence/$label-menu-select-action.json"
}

# The identifiers and descriptions below were actually observed in the
# preceding hosted-runner Mission Control AX evidence. The native helper
# rechecks the current hierarchy, enabled state and AXPress action each time.
ym_desktop_mc
"$ym_qa_helpers/desktop-actions" inspect > "$ym_qa_evidence/01-before-create-ax.json"
ym_desktop_capture 01-before-create
"$ym_qa_helpers/desktop-actions" create-second > "$ym_qa_evidence/02-create-action.json"
sleep 2
"$ym_qa_helpers/desktop-actions" inspect > "$ym_qa_evidence/02-two-desktops-ax.json"
ym_desktop_capture 02-two-desktops
"$ym_qa_helpers/desktop-actions" select 2 > "$ym_qa_evidence/03-select-second-action.json"
sleep 3
ym_desktop_capture 03-second-desktop-before-open

ym_desktop_panel_menu 04-existing-panel-from-second-desktop
sleep 3
ym_desktop_capture 04-existing-panel-from-second-desktop 0
ym_desktop_mc
"$ym_qa_helpers/desktop-actions" inspect > "$ym_qa_evidence/05-existing-panel-space-ax.json"
ym_desktop_capture 05-existing-panel-space
ym_desktop_escape

# Close only the production panel that this suite owns, preserving its process.
/bin/bash "$ym_qa_source/close-owned-panel.sh" "$ym_qa_helpers" "$ym_qa_yomado_pid" > "$ym_qa_evidence/06-close-action.json"
kill -0 "$ym_qa_yomado_pid"
sleep 1
ym_desktop_select_second 06-closed-panel-second-desktop
ym_desktop_capture 06-closed-panel-second-desktop 1
ym_desktop_panel_menu 07-reopened-from-second-desktop
sleep 3
ym_desktop_capture 07-reopened-from-second-desktop 0
ym_desktop_mc
"$ym_qa_helpers/desktop-actions" inspect > "$ym_qa_evidence/08-reopened-panel-space-ax.json"
ym_desktop_capture 08-reopened-panel-space
ym_desktop_escape
ym_desktop_capture 09-final
# Repeat the close/demotion cycle and exercise the other actual Desktop.
/bin/bash "$ym_qa_source/close-owned-panel.sh" "$ym_qa_helpers" "$ym_qa_yomado_pid" > "$ym_qa_evidence/10-close-action.json"
sleep 2
ym_desktop_capture 10-closed-before-first-desktop 1
ym_desktop_mc
"$ym_qa_helpers/desktop-actions" select 1 > "$ym_qa_evidence/11-select-first-action.json"
sleep 3
ym_desktop_capture 11-first-desktop-before-reopen 1
ym_desktop_panel_menu 12-reopened-from-first-desktop
sleep 3
ym_desktop_capture 12-reopened-from-first-desktop 0
ym_desktop_mc
"$ym_qa_helpers/desktop-actions" inspect > "$ym_qa_evidence/13-reopened-panel-space-ax.json"
ym_desktop_capture 13-reopened-panel-space
ym_desktop_escape
ym_desktop_capture 14-final
printf '%s\n' '{"collectionComplete":true,"desktopCreation":"native observed AXPress","desktopCountExpected":2,"existingPanelVerdict":"requires actual screenshot and AX review","closedPanelReopenVerdict":"requires actual screenshot and AX review after Accessory cycles from both Desktop selections","note":"Returning to the panel existing Desktop is distinct from moving the panel; either result must be reported accurately."}' \
  > "$ym_qa_evidence/collection-status.json"
