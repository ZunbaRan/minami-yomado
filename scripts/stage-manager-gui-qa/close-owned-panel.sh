#!/bin/bash
set -euo pipefail
ym_close_source="$(cd "$(dirname "$0")" && pwd -P)"
source "$ym_close_source/guard.sh"
ym_close_helpers="${1:?missing helper directory}"
ym_close_pid="${2:?missing owned product PID}"
[[ "$ym_close_pid" =~ ^[0-9]+$ ]]
[[ "$("$ym_close_helpers/observe" pid dev.chekusu.yomado)" == "$ym_close_pid" ]]
/usr/bin/osascript - "$ym_close_pid" <<'APPLESCRIPT'
on run argv
  tell application "System Events"
    tell (first application process whose unix id is ((item 1 of argv) as integer))
      set panels to every window whose name is "yomado"
      if (count of panels) is not 1 then error "Expected one owned yomado panel"
      click (first button of (item 1 of panels) whose subrole is "AXCloseButton")
    end tell
  end tell
end run
APPLESCRIPT
printf '{"pid":%s,"action":"close","inputPath":"AXPress via System Events on exact owned panel close button","result":"input sent; inspect subsequent state"}\n' "$ym_close_pid"
