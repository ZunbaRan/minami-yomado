#!/usr/bin/env python3
"""Check bounded state evidence; screenshots still require independent review."""
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
checks = []
def check(name, condition):
    checks.append({"name": name, "passed": bool(condition)})
def read(name):
    return json.loads((root / name).read_text())
def app(data, bundle="dev.chekusu.yomado"):
    matches = [a for a in data.get("applications", []) if a.get("bundleIdentifier") == bundle]
    return matches[0] if len(matches) == 1 else {}
def windows(a, title="yomado"):
    return [w for w in a.get("cgWindows", []) if w.get("kCGWindowName") == title and w.get("kCGWindowLayer") == 0]
def visible(a, title="yomado"):
    return [w for w in windows(a, title) if w.get("kCGWindowIsOnscreen") is True]
def tree_matches(value, predicate):
    if isinstance(value, dict):
        return ([value] if predicate(value) else []) + [n for child in value.values() for n in tree_matches(child, predicate)]
    if isinstance(value, list):
        return [n for child in value for n in tree_matches(child, predicate)]
    return []

try:
    labels = ["02-yomado-first-open", "04-reopen", "04b-dock-reopen", "06-reopen-minimized",
              "08-open-from-full-screen", "desktops/04-existing-panel-from-second-desktop",
              "desktops/07-reopened-from-second-desktop", "stage-manager-off/05-panel-stage-manager-off",
              "stage-manager-off/08-restored-after-minimize"]
    for label in labels:
        data = read(label + ".json")
        product = app(data)
        check(label + ": regular activation policy", product.get("activationPolicy") == 0)
        check(label + ": exactly one visible normal-size panel", len(visible(product)) == 1 and visible(product)[0].get("kCGWindowBounds", {}).get("Width", 0) >= 600)
        status = tree_matches(product.get("axMenuBars", []), lambda n: n.get("AXSubrole") == "AXMenuExtra" and n.get("AXDescription") == "yomado · 夜窗")
        check(label + ": enabled status-menu entry remains", len(status) == 1 and status[0].get("AXEnabled") is True)
    before, after = app(read("04-reopen.json")), app(read("04b-dock-reopen.json"))
    check("Dock reopen reuses PID and window", before.get("pid") == after.get("pid") and
          [w.get("kCGWindowNumber") for w in windows(before)] == [w.get("kCGWindowNumber") for w in windows(after)])
    dock = read("04b-dock-reopen.json").get("dock", {})
    check("Dock reopen icon present with readable complete positive control", dock.get("yomadoIconObservation") == "present" and
          dock.get("dockReadable") is True and dock.get("walkComplete") is True and dock.get("regularCompanionPositiveControl") is True)
    menu_action = read("04-reopen-menu-select-action.json")
    check("menu reopen used real mouse on current AX item", menu_action.get("inputPath") == "mouse-at-current-visible-AX-menu-item-center")
    minimized = app(read("stage-manager-off/06-minimized-stage-manager-off.json"))
    check("Stage Manager off genuinely minimized", any(w.get("AXMinimized") is True for w in minimized.get("axWindows", [])))
    restored = app(read("stage-manager-off/08-restored-after-minimize.json"))
    check("menu restored genuinely minimized panel", any(w.get("AXMinimized") is False for w in restored.get("axWindows", [])) and len(visible(restored)) == 1)
    off_controls = tree_matches(read("stage-manager-off/02-control-center-value.json"), lambda n: n.get("AXDescription") == "Stage Manager" and n.get("AXRole") == "AXCheckBox")
    check("actual Control Center Stage Manager off", bool(off_controls) and all(n.get("AXValue") == 0 for n in off_controls))
    group = read("manual-group-result.json")
    check("manual group scenario collected without blocked guard", group.get("exitCode") == 0)
    timeline = [json.loads(line) for line in (root / "dock-timeline.jsonl").read_text().splitlines()]
    running = [s for s in timeline if s.get("recordType") == "sample" and s.get("yomadoActivationPolicy", -1) != -1]
    check("all observed running policies regular", bool(running) and all(s["yomadoActivationPolicy"] == 0 for s in running))
    check("timeline completed by requested stop", timeline[-1].get("reason") == "requested-stop")
except Exception as error:
    checks.append({"name": "complete expected evidence", "passed": False, "errorType": type(error).__name__})

result = {"checks": checks, "passed": sum(c["passed"] for c in checks), "failed": sum(not c["passed"] for c in checks),
          "acceptanceVerdict": "requires independent screenshots and Space/group behavior review"}
print(json.dumps(result, indent=2))
sys.exit(0 if result["failed"] == 0 else 1)
