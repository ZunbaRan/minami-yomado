#!/bin/bash
# Only snapshots of the disposable runner's owned product/fixture applications.
set -euo pipefail
ym_capture_source="$(cd "$(dirname "$0")" && pwd -P)"
source "$ym_capture_source/guard.sh"
ym_capture_helpers="${1:?missing helper directory}"
ym_capture_evidence="${2:?missing evidence directory}"
ym_capture_label="${3:?missing label}"
ym_capture_policy="${4:-}"
case "$ym_capture_policy" in ''|0|1) ;; *) printf 'Invalid expected activation policy.\n' >&2; exit 64;; esac
"$ym_capture_helpers/observe" > "$ym_capture_evidence/$ym_capture_label.json"
/usr/sbin/screencapture -x "$ym_capture_evidence/$ym_capture_label.png"
if [[ -n "$ym_capture_policy" ]]; then
  # These two real observations delimit a quiet interval. The checker requires
  # the timeline's samples within it to match this phase, including hidden
  # Accessory phases; transitions between phases are retained as evidence.
  sleep 0.6
  "$ym_capture_helpers/observe" > "$ym_capture_evidence/$ym_capture_label.stable-end.json"
  printf '{"expectedActivationPolicy":%s,"start":"%s.json","end":"%s.stable-end.json"}\n' \
    "$ym_capture_policy" "$ym_capture_label" "$ym_capture_label" > "$ym_capture_evidence/$ym_capture_label.interval.json"
fi
