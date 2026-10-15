#!/bin/bash
# Optional terminal scenario. Not part of phase1 until reviewed explicitly.
set -euo pipefail
ym_qa_source="$(cd "$(dirname "$0")" && pwd -P)"
source "$ym_qa_source/guard.sh"
ym_group_helpers="${1:?Usage: manual-group-scenarios.sh helpers evidence companion-control-directory owned-yomado-pid}"
ym_group_evidence="${2:?missing evidence directory}"
ym_group_control="${3:?missing Companion control directory}"
ym_group_product_pid="${4:?missing owned Yomado PID}"
[[ "$("$ym_group_helpers/observe" pid dev.chekusu.yomado)" == "$ym_group_product_pid" ]]
mkdir -p "$ym_group_evidence/reference-control"
MACOSX_DEPLOYMENT_TARGET=14.0 /usr/bin/xcrun swiftc -O "$ym_qa_source/ManualGroupActions.swift" -o "$ym_group_helpers/manual-group-actions"
ym_group_reference_pid=""
ym_group_cleanup() {
  local code=$?
  if [[ "$code" -ne 0 ]]; then
    "$ym_group_helpers/observe" > "$ym_group_evidence/failure-state.json" || true
    /usr/sbin/screencapture -x "$ym_group_evidence/failure-state.png" || true
  fi
  if [[ -n "$ym_group_reference_pid" ]] && kill -0 "$ym_group_reference_pid" 2>/dev/null; then
    kill -TERM "$ym_group_reference_pid" || true
  fi
}
trap ym_group_cleanup EXIT
ym_group_capture() {
  /bin/bash "$ym_qa_source/capture-lifecycle.sh" "$ym_group_helpers" "$ym_group_evidence" "$1" "${2:-}"
  "$ym_group_helpers/manual-group-actions" inspect > "$ym_group_evidence/$1-group-discovery.json"
}
ym_group_show_companion() {
  printf '{"nonce":"%s","command":"show"}\n' "$(/usr/bin/uuidgen)" > "$ym_group_control/command.tmp"
  /bin/mv "$ym_group_control/command.tmp" "$ym_group_control/command.json"
  sleep 2
}
ym_group_open_panel() {
  "$ym_group_helpers/panel-menu-actions" "$ym_group_product_pid" open > "$ym_group_evidence/$1-menu-open-action.json"
  sleep 1
  ym_group_capture "$1-menu-open"
  "$ym_group_helpers/panel-menu-actions" "$ym_group_product_pid" select-open-panel > "$ym_group_evidence/$1-menu-select-action.json"
  sleep 3
}

ym_group_show_companion
ym_group_open_panel 01-before-manual-group
ym_group_capture 01-before-manual-group
"$ym_group_helpers/manual-group-actions" drag-companion-into-yomado > "$ym_group_evidence/02-actual-drag.jsonl"
sleep 3
ym_group_capture 03-after-manual-group

if "$ym_group_helpers/observe" pid org.yomado.qa.Reference >/dev/null 2>&1; then
  printf '%s\n' 'REFUSED: an unrelated Reference fixture already exists.' >&2; exit 1
fi
YM_QA_CONTROL_DIRECTORY="$ym_group_evidence/reference-control" \
  "$ym_group_helpers/Reference.app/Contents/MacOS/Companion" > "$ym_group_evidence/reference.jsonl" 2> "$ym_group_evidence/reference.stderr" &
ym_group_reference_pid=$!
sleep 3
ym_group_capture 04-reference-active-group-away
ym_group_open_panel 05-reopen-manual-group
ym_group_capture 05-reopen-manual-group 0
# Preserve direct evidence of the existing group across the newly introduced
# close -> Accessory -> reopen path; do not infer grouping from window flags.
/bin/bash "$ym_qa_source/close-owned-panel.sh" "$ym_group_helpers" "$ym_group_product_pid" > "$ym_group_evidence/06-close-action.json"
sleep 2
ym_group_capture 06-closed-manual-group 1
ym_group_show_companion
ym_group_open_panel 07-reopen-manual-group-after-close
ym_group_capture 07-reopen-manual-group-after-close 0
printf '%s\n' '{"collectionComplete":true,"manualGroupFormation":"requires actual before/after drag screenshot review","manualGroupPreservation":"requires paired-thumbnail and both-returned-window evidence after Reference switch and after close/Accessory/reopen","noAutomaticPass":true}' \
  > "$ym_group_evidence/collection-status.json"
