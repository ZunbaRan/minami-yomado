#!/bin/bash
# Evidence collection, not an automatic Stage Manager pass/fail oracle.
set -euo pipefail
ym_qa_source="$(cd "$(dirname "$0")" && pwd -P)"
source "$ym_qa_source/guard.sh"
ym_qa_app="${1:?Usage: phase1.sh Yomado.app helper-directory evidence-directory variant}"
ym_qa_helpers="${2:?missing helper-directory}"
ym_qa_evidence="${3:?missing evidence-directory}"
ym_qa_variant="${4:?missing variant}"
case "$ym_qa_variant" in base|head|activation-order-experiment|early-primary-experiment|sync-activation-experiment|legacy-activation-experiment|managed-primary-experiment|combined-primary-activation-experiment|regular-policy-diagnostic-not-shippable) ;; *) printf 'Unknown QA variant.\n' >&2; exit 64;; esac
ym_qa_stage_manager="unverified"
if [[ "${YM_QA_STAGE_MANAGER_RUNTIME_CONFIRMED:-}" == true \
   && "$(/usr/bin/defaults read com.apple.WindowManager GloballyEnabled 2>/dev/null || true)" == 1 ]]; then
  ym_qa_stage_manager="runtime-setup-confirmed-still-requires-group-review"
else
  printf '%s\n' 'Stage Manager is unverified; collecting ordinary-window and full-screen evidence without claiming grouping success.' >&2
fi
[[ -x "$ym_qa_app/Contents/MacOS/Yomado" && -x "$ym_qa_helpers/observe" ]]
mkdir -p "$ym_qa_evidence/control"
if "$ym_qa_helpers/observe" pid dev.chekusu.yomado > "$ym_qa_evidence/preexisting-yomado-pid.txt" 2>/dev/null; then
  printf '%s\n' 'REFUSED: the fresh runner already has a Yomado process; cannot identify a new launch safely.' >&2
  exit 1
fi
ym_qa_yomado_pid=""
ym_qa_companion_pid=""
ym_qa_reference_pid=""
ym_qa_observer_pid=""
ym_qa_cleanup() {
  local exit_status=$?
  if [[ "$exit_status" -ne 0 ]]; then
    "$ym_qa_helpers/observe" > "$ym_qa_evidence/failure-state.json" || true
    /usr/sbin/screencapture -x "$ym_qa_evidence/failure-state.png" || true
  fi
  # All PIDs were started by this one run; never kill all instances by name.
  for ym_qa_pid in "$ym_qa_observer_pid" "$ym_qa_yomado_pid" "$ym_qa_companion_pid" "$ym_qa_reference_pid"; do
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
ym_qa_panel_menu() {
  local label="$1"
  "$ym_qa_helpers/panel-menu-actions" "$ym_qa_yomado_pid" open > "$ym_qa_evidence/$label-menu-open-action.json"
  sleep 1
  ym_qa_capture "$label-menu-open"
  "$ym_qa_helpers/panel-menu-actions" "$ym_qa_yomado_pid" select-open-panel > "$ym_qa_evidence/$label-menu-select-action.json"
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
YM_QA_CONTROL_DIRECTORY="$ym_qa_evidence/control" YM_QA_PRODUCT_APP="$ym_qa_app" \
  "$ym_qa_helpers/Companion.app/Contents/MacOS/Companion" > "$ym_qa_evidence/companion.jsonl" 2> "$ym_qa_evidence/companion.stderr" &
ym_qa_companion_pid=$!
sleep 3
ym_qa_capture 01-companion-front

# A second independent regular app is a positive control for Stage Manager
# itself. Both binaries use separate bundle IDs and separately owned windows.
# If ordinary apps do not separate, the accessory-app A/B cannot prove its fix.
mkdir -p "$ym_qa_evidence/reference-control"
YM_QA_CONTROL_DIRECTORY="$ym_qa_evidence/reference-control" \
  "$ym_qa_helpers/Reference.app/Contents/MacOS/Companion" > "$ym_qa_evidence/reference.jsonl" 2> "$ym_qa_evidence/reference.stderr" &
ym_qa_reference_pid=$!
sleep 3
ym_qa_capture 01a-reference-front-positive-control
ym_qa_companion_command show
sleep 3
ym_qa_capture 01b-companion-front-positive-control
kill -TERM "$ym_qa_reference_pid"
wait "$ym_qa_reference_pid" || true
ym_qa_reference_pid=""
sleep 1

ym_qa_stop_file="$ym_qa_evidence/control/dock-observer.stop"
/bin/rm -f "$ym_qa_stop_file"
"$ym_qa_helpers/observe" timeline 240 "$ym_qa_stop_file" > "$ym_qa_evidence/dock-timeline.jsonl" &
ym_qa_observer_pid=$!
# Wait for the first complete, flushed observation before launching Yomado.
# Starting a background process alone is not a pre-launch observation.
ym_qa_ready=false
for ym_qa_attempt in {1..100}; do
  if [[ -s "$ym_qa_evidence/dock-timeline.jsonl" ]]; then ym_qa_ready=true; break; fi
  kill -0 "$ym_qa_observer_pid"
  sleep 0.1
done
if [[ "$ym_qa_ready" != true ]]; then
  printf '%s\n' 'Dock observer did not produce its first sample; refusing an unobserved launch.' >&2
  exit 1
fi
# Keep the original CLI LaunchServices baseline; the optional terminal
# diagnostic separately measures an active native app's launch handoff.
# No preexisting Yomado instance was allowed, so this PID belongs to this run.
/usr/bin/open -n "$ym_qa_app"
for ym_qa_attempt in {1..100}; do
  if ym_qa_yomado_pid="$("$ym_qa_helpers/observe" pid dev.chekusu.yomado 2>/dev/null)"; then break; fi
  sleep 0.1
done
if [[ -z "$ym_qa_yomado_pid" ]]; then
  printf '%s\n' 'LaunchServices did not produce an identifiable Yomado process.' >&2
  exit 1
fi
sleep 4
kill -0 "$ym_qa_yomado_pid"
ym_qa_capture 02-yomado-first-open

ym_qa_own_ax_action close
sleep 2
kill -0 "$ym_qa_yomado_pid"
ym_qa_capture 03-panel-closed-app-alive
ym_qa_companion_command show
sleep 2
ym_qa_panel_menu 04-reopen
sleep 3
ym_qa_capture 04-reopen

ym_qa_own_ax_action minimize
sleep 2
ym_qa_capture 05-minimized
ym_qa_companion_command show
sleep 2
ym_qa_panel_menu 06-reopen-minimized
sleep 3
ym_qa_capture 06-reopen-minimized

# The companion's real native full-screen window supplies a separate Space.
# Screenshots and did-enter-full-screen log evidence are required before any
# cross-Space conclusion. The panel may return to its existing desktop; that
# is recorded, not silently assumed to satisfy the product's accessibility goal.
ym_qa_companion_command enter-full-screen
sleep 4
ym_qa_capture 07-companion-full-screen
ym_qa_panel_menu 08-open-from-full-screen
sleep 4
ym_qa_capture 08-open-from-full-screen
ym_qa_companion_command exit-full-screen
sleep 4
ym_qa_capture 09-after-full-screen

# Capture the runner's real Mission Control AX identifiers before any later
# Desktop-creation action is designed. Do not guess coordinates or buttons.
/usr/bin/open -a 'Mission Control'
sleep 1
"$ym_qa_helpers/observe" system-ui > "$ym_qa_evidence/10-mission-control-ax.json"
ym_qa_capture 10-mission-control
/usr/bin/osascript -e 'tell application "System Events" to key code 53'
sleep 1
ym_qa_capture 11-final

/bin/bash "$ym_qa_source/desktop-scenarios.sh" "$ym_qa_app" "$ym_qa_helpers" \
  "$ym_qa_evidence/desktops" "$ym_qa_yomado_pid"

if [[ "${YM_QA_NATIVE_LAUNCH_DIAGNOSTIC:-false}" == true ]]; then
  # This extra scenario begins only after all baseline scenarios are captured.
  # The existing owned production process is the only application terminated.
  ym_qa_capture 12-native-launch-before-restart
  kill -TERM "$ym_qa_yomado_pid"
  for ym_qa_attempt in {1..100}; do
    if ! kill -0 "$ym_qa_yomado_pid" 2>/dev/null; then break; fi
    sleep 0.1
  done
  if kill -0 "$ym_qa_yomado_pid" 2>/dev/null; then
    printf '%s\n' 'Owned Yomado did not terminate for the separate cold-launch diagnostic.' >&2
    exit 1
  fi
  ym_qa_yomado_pid=""
  ym_qa_companion_command show
  sleep 2
  ym_qa_capture 13-native-launch-active-companion
  ym_qa_companion_command launch-product
  for ym_qa_attempt in {1..100}; do
    if ym_qa_yomado_pid="$("$ym_qa_helpers/observe" pid dev.chekusu.yomado 2>/dev/null)"; then break; fi
    sleep 0.1
  done
  if [[ -z "$ym_qa_yomado_pid" ]]; then
    printf '%s\n' 'Native Companion launch did not produce the expected Yomado process.' >&2
    exit 1
  fi
  sleep 4
  ym_qa_capture 14-native-cold-launch-result
fi

if [[ "${YM_QA_EXTRA_GROUP_SCENARIOS:-false}" == true ]]; then
  ym_qa_group_status=0
  /bin/bash "$ym_qa_source/manual-group-scenarios.sh" "$ym_qa_helpers" "$ym_qa_evidence/manual-group" \
    "$ym_qa_evidence/control" "$ym_qa_yomado_pid" || ym_qa_group_status=$?
  # Missing a genuine independent starting group is a recorded blocked test,
  # never a pass. Other driver failures still stop the suite.
  if [[ "$ym_qa_group_status" -ne 0 && "$ym_qa_group_status" -ne 78 ]]; then exit "$ym_qa_group_status"; fi
  printf '{"exitCode":%s,"verdict":"requires-review-or-blocked-not-passed"}\n' "$ym_qa_group_status" > "$ym_qa_evidence/manual-group-result.json"
  /bin/bash "$ym_qa_source/stage-manager-off-scenarios.sh" "$ym_qa_helpers" "$ym_qa_evidence/stage-manager-off" \
    "$ym_qa_evidence/control" "$ym_qa_yomado_pid"
fi

# If the safety cap expired before the final capture, coverage is incomplete.
kill -0 "$ym_qa_observer_pid"
/usr/bin/touch "$ym_qa_stop_file"
wait "$ym_qa_observer_pid"
ym_qa_observer_pid=""

printf '{"variant":"%s","collectionComplete":true,"stageManagerSetup":"%s","groupingVerdict":"requires-review","crossDesktopVerdict":"requires-review-of-desktops-evidence","dockSampling":"ready before LaunchServices launch; stop requested after final Desktop screenshot; compare monotonic sample start/end and final snapshot timestamps; 0.1s is only requested sleep","fullScreenVerdict":"requires-review"}\n' \
  "$ym_qa_variant" "$ym_qa_stage_manager" > "$ym_qa_evidence/collection-status.json"
