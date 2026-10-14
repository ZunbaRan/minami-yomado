#!/bin/bash
# Evidence collection, not an automatic Stage Manager pass/fail oracle.
set -euo pipefail
ym_qa_source="$(cd "$(dirname "$0")" && pwd -P)"
source "$ym_qa_source/guard.sh"
ym_qa_app="${1:?Usage: phase1.sh Yomado.app helper-directory evidence-directory variant}"
ym_qa_helpers="${2:?missing helper-directory}"
ym_qa_evidence="${3:?missing evidence-directory}"
ym_qa_variant="${4:?missing variant}"
case "$ym_qa_variant" in base|head) ;; *) printf 'Expected variant base or head.\n' >&2; exit 64;; esac
ym_qa_stage_manager="unverified"
if [[ "${YM_QA_STAGE_MANAGER_RUNTIME_CONFIRMED:-}" == true \
   && "$(/usr/bin/defaults read com.apple.WindowManager GloballyEnabled 2>/dev/null || true)" == 1 ]]; then
  ym_qa_stage_manager="runtime-setup-confirmed-still-requires-group-review"
else
  printf '%s\n' 'Stage Manager is unverified; collecting ordinary-window and full-screen evidence without claiming grouping success.' >&2
fi
[[ -x "$ym_qa_app/Contents/MacOS/Yomado" && -x "$ym_qa_helpers/observe" ]]
mkdir -p "$ym_qa_evidence/control"
ym_qa_yomado_pid=""
ym_qa_companion_pid=""
ym_qa_observer_pid=""
ym_qa_cleanup() {
  # All PIDs were started by this one run; never kill all instances by name.
  for ym_qa_pid in "$ym_qa_observer_pid" "$ym_qa_yomado_pid" "$ym_qa_companion_pid"; do
    if [[ -n "$ym_qa_pid" ]] && kill -0 "$ym_qa_pid" 2>/dev/null; then kill -TERM "$ym_qa_pid" 2>/dev/null || true; fi
  done
}
trap ym_qa_cleanup EXIT
ym_qa_capture() {
  local label="$1"
  "$ym_qa_helpers/observe" > "$ym_qa_evidence/$label.json"
  /usr/sbin/screencapture -x "$ym_qa_evidence/$label.png"
}
ym_qa_companion_command() {
  local command="$1"
  printf '{"nonce":"%s","command":"%s"}\n' "$(/usr/bin/uuidgen)" "$command" > "$ym_qa_evidence/control/command.tmp"
  /bin/mv "$ym_qa_evidence/control/command.tmp" "$ym_qa_evidence/control/command.json"
}
ym_qa_own_ax_action() {
  local action="$1"
  /usr/bin/osascript - "$ym_qa_yomado_pid" "$action" <<'APPLESCRIPT'
on run argv
  set targetPID to (item 1 of argv) as integer
  set actionName to item 2 of argv
  tell application "System Events"
    set targetProcess to first application process whose unix id is targetPID
    tell targetProcess
      if actionName is "close" then
        click (first button of window 1 whose subrole is "AXCloseButton")
      else if actionName is "minimize" then
        set value of attribute "AXMinimized" of window 1 to true
      end if
    end tell
  end tell
end run
APPLESCRIPT
}

"$ym_qa_helpers/observe" > "$ym_qa_evidence/00-before.json"
YM_QA_CONTROL_DIRECTORY="$ym_qa_evidence/control" \
  "$ym_qa_helpers/Companion.app/Contents/MacOS/Companion" > "$ym_qa_evidence/companion.jsonl" 2> "$ym_qa_evidence/companion.stderr" &
ym_qa_companion_pid=$!
sleep 3
ym_qa_capture 01-companion-front

"$ym_qa_helpers/observe" timeline 55 > "$ym_qa_evidence/dock-timeline.jsonl" &
ym_qa_observer_pid=$!
"$ym_qa_app/Contents/MacOS/Yomado" > "$ym_qa_evidence/yomado.stdout" 2> "$ym_qa_evidence/yomado.stderr" &
ym_qa_yomado_pid=$!
sleep 4
kill -0 "$ym_qa_yomado_pid"
ym_qa_capture 02-yomado-first-open

ym_qa_own_ax_action close
sleep 2
kill -0 "$ym_qa_yomado_pid"
ym_qa_capture 03-panel-closed-app-alive
ym_qa_companion_command show
sleep 2
/usr/bin/open "$ym_qa_app"
sleep 3
ym_qa_capture 04-reopen

ym_qa_own_ax_action minimize
sleep 2
ym_qa_capture 05-minimized
ym_qa_companion_command show
sleep 2
/usr/bin/open "$ym_qa_app"
sleep 3
ym_qa_capture 06-reopen-minimized

# The companion's real native full-screen window supplies a separate Space.
# Screenshots and did-enter-full-screen log evidence are required before any
# cross-Space conclusion. The panel may return to its existing desktop; that
# is recorded, not silently assumed to satisfy the product's accessibility goal.
ym_qa_companion_command enter-full-screen
sleep 4
ym_qa_capture 07-companion-full-screen
/usr/bin/open "$ym_qa_app"
sleep 4
ym_qa_capture 08-open-from-full-screen
ym_qa_companion_command exit-full-screen
sleep 4
ym_qa_capture 09-after-full-screen

printf '{"variant":"%s","collectionComplete":true,"stageManagerSetup":"%s","groupingVerdict":"requires-review","crossDesktopVerdict":"not-yet-tested","dockSamplingIntervalSeconds":0.1,"fullScreenVerdict":"requires-review"}\n' \
  "$ym_qa_variant" "$ym_qa_stage_manager" > "$ym_qa_evidence/collection-status.json"
