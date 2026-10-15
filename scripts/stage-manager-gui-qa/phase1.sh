#!/bin/bash
# Evidence collection, not an automatic Stage Manager pass/fail oracle.
set -euo pipefail
ym_qa_source="$(cd "$(dirname "$0")" && pwd -P)"
source "$ym_qa_source/guard.sh"
ym_qa_app="${1:?Usage: phase1.sh Yomado.app helper-directory evidence-directory variant}"
ym_qa_helpers="${2:?missing helper-directory}"
ym_qa_evidence="${3:?missing evidence-directory}"
ym_qa_variant="${4:?missing variant}"
case "$ym_qa_variant" in regular-default-spaces|regular-no-auto-spaces) ;; *) printf 'Unknown production QA variant.\n' >&2; exit 64;; esac
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
  # The next isolated virtual-display suite requires no pre-existing product.
  # Give only this run's processes time to finish; never kill by application name.
  for ym_qa_attempt in {1..50}; do
    local any_alive=false
    for ym_qa_pid in "$ym_qa_observer_pid" "$ym_qa_yomado_pid" "$ym_qa_companion_pid" "$ym_qa_reference_pid"; do
      if [[ -n "$ym_qa_pid" ]] && kill -0 "$ym_qa_pid" 2>/dev/null; then any_alive=true; fi
    done
    if [[ "$any_alive" == false ]]; then break; fi
    sleep 0.1
  done
  for ym_qa_pid in "$ym_qa_observer_pid" "$ym_qa_yomado_pid" "$ym_qa_companion_pid" "$ym_qa_reference_pid"; do
    if [[ -n "$ym_qa_pid" ]] && kill -0 "$ym_qa_pid" 2>/dev/null; then
      printf 'Owned fixture PID did not finish cleanup: %s\n' "$ym_qa_pid" >&2
      exit_status=1
    fi
  done
  return "$exit_status"
}
trap ym_qa_cleanup EXIT
ym_qa_capture() {
  /bin/bash "$ym_qa_source/capture-lifecycle.sh" "$ym_qa_helpers" "$ym_qa_evidence" "$1" "${2:-}"
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
ym_qa_close_panel() {
  /bin/bash "$ym_qa_source/close-owned-panel.sh" "$ym_qa_helpers" "$ym_qa_yomado_pid" > "$ym_qa_evidence/$1-close-action.json"
}

"$ym_qa_helpers/observe" > "$ym_qa_evidence/00-before.json"
YM_QA_CONTROL_DIRECTORY="$ym_qa_evidence/control" YM_QA_PRODUCT_APP="$ym_qa_app" \
  "$ym_qa_helpers/Companion.app/Contents/MacOS/Companion" > "$ym_qa_evidence/companion.jsonl" 2> "$ym_qa_evidence/companion.stderr" &
ym_qa_companion_pid=$!
sleep 3
ym_qa_capture 01-companion-front

# A second independent regular app is a positive control for Stage Manager
# itself. Both binaries use separate bundle IDs and separately owned windows.
# If ordinary apps do not separate, product grouping cannot be accepted.
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
"$ym_qa_helpers/observe" timeline 480 "$ym_qa_stop_file" > "$ym_qa_evidence/dock-timeline.jsonl" &
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
/usr/bin/open -n --stdout "$ym_qa_evidence/product.stdout" --stderr "$ym_qa_evidence/product.stderr" "$ym_qa_app"
for ym_qa_attempt in {1..100}; do
  if ym_qa_yomado_pid="$("$ym_qa_helpers/observe" pid dev.chekusu.yomado 2>/dev/null)"; then break; fi
  sleep 0.1
done
if [[ -z "$ym_qa_yomado_pid" ]]; then
  printf '%s\n' 'LaunchServices did not produce an identifiable Yomado process.' >&2
  exit 1
fi
python3 - "$ym_qa_helpers/observe" "$ym_qa_yomado_pid" "$ym_qa_evidence" <<'PY'
import json, math, pathlib, subprocess, sys, time

observer, expected_pid, evidence = sys.argv[1], int(sys.argv[2]), pathlib.Path(sys.argv[3])

def ready_state(data, expected_pid):
    reasons = []
    products = [a for a in data.get('applications', []) if a.get('bundleIdentifier') == 'dev.chekusu.yomado']
    product = products[0] if len(products) == 1 else {}
    if len(products) != 1 or product.get('pid') != expected_pid:
        reasons.append('owned process identity unavailable')
    if product.get('activationPolicy') != 0 or product.get('terminated') is not False:
        reasons.append('owned process is not live Regular')
    panels = [w for w in product.get('cgWindows', [])
              if w.get('kCGWindowName') == 'yomado' and w.get('kCGWindowLayer') == 0]
    panel = panels[0] if len(panels) == 1 else {}
    box = panel.get('kCGWindowBounds', {})
    geometry = [box.get(k) for k in ['X', 'Y', 'Width', 'Height']]
    valid_geometry = all(isinstance(v, (int, float)) and math.isfinite(v) for v in geometry)
    if (len(panels) != 1 or panel.get('kCGWindowIsOnscreen') is not True
            or not valid_geometry or box.get('Width', 0) < 600 or box.get('Height', 0) <= 0):
        reasons.append('normal-size onscreen product panel not ready')
    ax = [w for w in product.get('axWindows', [])
          if w.get('AXRole') == 'AXWindow' and w.get('AXTitle') == 'yomado'
          and w.get('AXMinimized') is False]
    ax_geometry = (ax[0].get('AXPosition', []) + ax[0].get('AXSize', [])) if len(ax) == 1 else []
    if (not valid_geometry or len(ax_geometry) != 4
            or not all(isinstance(v, (int, float)) and math.isfinite(v) for v in ax_geometry)
            or any(abs(a-b) > 1 for a,b in zip(geometry, ax_geometry))):
        reasons.append('corresponding AXWindow geometry not ready')
    dock = data.get('dock', {})
    if (dock.get('dockReadable') is not True or dock.get('walkComplete') is not True
            or dock.get('regularCompanionPositiveControl') is not True
            or dock.get('yomadoIconObservation') != 'present'
            or not any(i.get('matchesRunningBundleURL') is True for i in dock.get('yomadoItems', []))):
        reasons.append('reliable matching product Dock item not ready')
    # A CLI LaunchServices cold start is not required to take app focus.
    return {'ready': not reasons, 'reasons': reasons, 'panelWindowID': panel.get('kCGWindowNumber')}

start = time.monotonic()
deadline = start + 10
samples = []
original_window_id = None
passed = False
while time.monotonic() < deadline:
    label = f'02-cold-start-wait-{len(samples):03d}'
    entry = {'label': label, 'startElapsedSeconds': time.monotonic() - start}
    try:
        result = subprocess.run([observer], capture_output=True, text=True,
                                timeout=max(.05, min(3, deadline-time.monotonic())), check=True)
        (evidence / (label + '.json')).write_text(result.stdout)
        if result.stderr:
            (evidence / (label + '.stderr')).write_text(result.stderr)
        data = json.loads(result.stdout)
        status = ready_state(data, expected_pid)
        window_id = status['panelWindowID']
        if original_window_id is None and isinstance(window_id, int):
            original_window_id = window_id
        if window_id is not None and window_id != original_window_id:
            status['ready'] = False
            status['reasons'].append('original cold-start panel identity changed')
        entry.update(status)
        entry['sampleUptimeSeconds'] = data.get('monotonicUptimeSeconds')
    except (subprocess.SubprocessError, ValueError) as error:
        entry.update({'ready': False, 'observationError': str(error)})
    entry['endElapsedSeconds'] = time.monotonic() - start
    samples.append(entry)
    if entry.get('ready') and time.monotonic() <= deadline:
        passed = True
        break
    time.sleep(min(.15, max(0, deadline-time.monotonic())))
report = {'passed': passed, 'maximumWaitSeconds': 10, 'elapsedSeconds': time.monotonic() - start,
          'ownedPID': expected_pid, 'originalPanelWindowID': original_window_id,
          'focusRequirement': 'none for CLI cold start', 'samples': samples}
(evidence / '02-cold-start-readiness.json').write_text(json.dumps(report, indent=2) + '\n')
if not passed:
    raise SystemExit('Cold-start panel did not reach complete observable state within 10 seconds')
PY
kill -0 "$ym_qa_yomado_pid"
ym_qa_capture 02-yomado-first-open 0

ym_qa_close_panel 03
sleep 2
kill -0 "$ym_qa_yomado_pid"
ym_qa_capture 03-panel-closed-app-alive 1
ym_qa_companion_command show
sleep 2
ym_qa_panel_menu 04-reopen
sleep 3
ym_qa_capture 04-reopen 0

# Closing demotes the running process and removes its unpinned Dock item.
# Reopen it through LaunchServices, not a nonexistent Dock item; do not use -n.
ym_qa_close_panel 04a
sleep 2
ym_qa_capture 04a-panel-closed-before-launchservices 1
/usr/bin/open "$ym_qa_app"
sleep 3
[[ "$("$ym_qa_helpers/observe" pid dev.chekusu.yomado)" == "$ym_qa_yomado_pid" ]]
ym_qa_capture 04b-launchservices-reopen 0
# A Dock click is still useful while the open panel is Regular. Hide it behind
# the Companion without closing, then click the real current Dock item.
ym_qa_companion_command show
sleep 2
"$ym_qa_helpers/panel-window-actions" "$ym_qa_yomado_pid" dock-open > "$ym_qa_evidence/04c-dock-open-action.json"
sleep 3
ym_qa_capture 04c-dock-open-while-regular 0

"$ym_qa_helpers/panel-window-actions" "$ym_qa_yomado_pid" minimize > "$ym_qa_evidence/05-minimize-action.json"
sleep 2
ym_qa_capture 05-minimized
ym_qa_companion_command show
sleep 2
ym_qa_panel_menu 06-reopen-minimized
sleep 3
ym_qa_capture 06-reopen-minimized 0

# The companion's real native full-screen window supplies a separate Space.
# Screenshots and did-enter-full-screen log evidence are required before any
# cross-Space conclusion. The panel may return to its existing desktop; that
# is recorded, not silently assumed to satisfy the product's accessibility goal.
ym_qa_companion_command enter-full-screen
sleep 4
ym_qa_capture 07-companion-full-screen
ym_qa_panel_menu 08-open-from-full-screen
sleep 4
ym_qa_capture 08-open-from-full-screen 0
# Repeat the cross-Space operation only after the production presenter has
# really hidden the panel and demoted the same process to Accessory.
ym_qa_close_panel 08a
sleep 2
ym_qa_capture 08a-panel-closed-after-full-screen-open 1
ym_qa_companion_command show
sleep 3
ym_qa_capture 08b-native-full-screen-after-close
ym_qa_panel_menu 08c-reopen-from-full-screen-after-close
sleep 4
ym_qa_capture 08c-reopen-from-full-screen-after-close 0
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

# No cold restart: every scenario below must retain the original PID/window.

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

printf '{"variant":"%s","collectionComplete":true,"stageManagerSetup":"%s","groupingVerdict":"requires-review","crossDesktopVerdict":"requires-review-of-desktops-evidence","dockSampling":"prelaunch timeline with explicit quiet Regular/Accessory intervals; same PID through close and reopen; 0.1s is only requested sleep","fullScreenVerdict":"requires-review"}\n' \
  "$ym_qa_variant" "$ym_qa_stage_manager" > "$ym_qa_evidence/collection-status.json"
python3 "$ym_qa_source/check-regular-evidence.py" "$ym_qa_evidence" > "$ym_qa_evidence/lifecycle-structural-checks.json"
