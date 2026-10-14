#!/bin/bash
# Only modifies the disposable runner's session preferences, never TCC.
set -euo pipefail
ym_qa_source="$(cd "$(dirname "$0")" && pwd -P)"
source "$ym_qa_source/guard.sh"
ym_qa_helpers="${1:?Usage: setup-guest.sh helper-directory evidence-directory}"
ym_qa_evidence="${2:?missing evidence-directory}"
mkdir -p "$ym_qa_evidence"
"$ym_qa_helpers/observe" > "$ym_qa_evidence/setup-before.json"
/usr/sbin/screencapture -x "$ym_qa_evidence/setup-before.png"

# This is a setup attempt, not proof of an effective runtime change. macOS may
# require a fresh login for separate Spaces. Later screenshots and API values
# must expose that limitation rather than silently marking Stage Manager on.
/usr/bin/defaults write com.apple.spaces spans-displays -bool false
/usr/bin/defaults write com.apple.WindowManager GloballyEnabled -bool true
/usr/bin/killall Dock || true
sleep 5
"$ym_qa_helpers/observe" > "$ym_qa_evidence/setup-after-preferences.json"
"$ym_qa_helpers/observe" system-ui > "$ym_qa_evidence/system-ui-before-control-center.json"

/usr/bin/osascript <<'APPLESCRIPT' > "$ym_qa_evidence/control-center-open.txt" 2> "$ym_qa_evidence/control-center-open.stderr" || true
tell application "System Events"
  tell process "ControlCenter"
    set matchingItems to every menu bar item of menu bar 1 whose description contains "Control Center"
    if (count of matchingItems) is 0 then
      return "No matching Control Center accessibility menu item; inspect system-ui evidence."
    end if
    click item 1 of matchingItems
    return "Opened observed Control Center menu item."
  end tell
end tell
APPLESCRIPT
sleep 2
"$ym_qa_helpers/observe" system-ui > "$ym_qa_evidence/control-center-open.json"
/usr/sbin/screencapture -x "$ym_qa_evidence/control-center-open.png"

# The preference alone did not activate actual grouping in the first run.
# Exercise the real, previously observed Control Center switch exactly twice.
# Start from the explicitly requested on preference, record each result, and
# leave effective state to screenshot/AX review; never treat the flag as proof.
for ym_qa_toggle in off on; do
  "$ym_qa_helpers/stage-manager-action" "$ym_qa_toggle" \
    > "$ym_qa_evidence/stage-manager-toggle-$ym_qa_toggle.txt" \
    2> "$ym_qa_evidence/stage-manager-toggle-$ym_qa_toggle.stderr"
  sleep 3
  "$ym_qa_helpers/observe" > "$ym_qa_evidence/stage-manager-$ym_qa_toggle.json"
  "$ym_qa_helpers/observe" system-ui > "$ym_qa_evidence/stage-manager-$ym_qa_toggle-ax.json"
  /usr/sbin/screencapture -x "$ym_qa_evidence/stage-manager-$ym_qa_toggle.png"
done

# Dismiss only this system popover before the fixture opens. No application
# windows have been created by this suite yet.
/usr/bin/osascript -e 'tell application "System Events" to key code 53' \
  > "$ym_qa_evidence/control-center-dismiss.txt" 2> "$ym_qa_evidence/control-center-dismiss.stderr" || true
"$ym_qa_helpers/observe" system-ui > "$ym_qa_evidence/before-onboarding-action-ax.json"
/usr/sbin/screencapture -x "$ym_qa_evidence/before-onboarding-action.png"
if ! "$ym_qa_helpers/stage-manager-action" finish-onboarding \
  > "$ym_qa_evidence/onboarding-action.txt" 2> "$ym_qa_evidence/onboarding-action.stderr"; then
  "$ym_qa_helpers/observe" system-ui > "$ym_qa_evidence/onboarding-failure-ax.json"
  /usr/sbin/screencapture -x "$ym_qa_evidence/onboarding-failure.png"
  exit 1
fi
"$ym_qa_helpers/observe" system-ui > "$ym_qa_evidence/after-onboarding-action-ax.json"
/usr/sbin/screencapture -x "$ym_qa_evidence/after-onboarding-action.png"
"$ym_qa_helpers/observe" > "$ym_qa_evidence/setup-final.json"
printf '%s\n' '{"setupAttempted":true,"stageManagerRuntimeVerified":false,"requiresReview":"Check separate Spaces API, actual Control Center state, and visible Stage Manager grouping. Preference writes are not acceptance."}' \
  > "$ym_qa_evidence/setup-status.json"
