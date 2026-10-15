#!/usr/bin/env python3
"""Validate real lifecycle observations; native Space/group screenshots need review."""
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
checks = []
interval_summary = []

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

def status_entry(product):
    return tree_matches(product.get("axMenuBars", []), lambda n: n.get("AXSubrole") == "AXMenuExtra" and n.get("AXDescription") == "yomado · 夜窗")

def dock_reliable(data, expected):
    d = data.get("dock", {})
    return (d.get("yomadoIconObservation") == expected and d.get("dockReadable") is True
            and d.get("walkComplete") is True and d.get("regularCompanionPositiveControl") is True)

try:
    initial = app(read("02-yomado-first-open.json"))
    expected_pid = initial.get("pid")
    expected_windows = [w.get("kCGWindowNumber") for w in windows(initial)]
    check("one original panel identity captured", isinstance(expected_pid, int) and expected_pid > 0 and len(expected_windows) == 1)
    open_labels = ["02-yomado-first-open", "04-reopen", "04b-launchservices-reopen", "04c-dock-open-while-regular",
                   "06-reopen-minimized", "08-open-from-full-screen", "08c-reopen-from-full-screen-after-close",
                   "desktops/04-existing-panel-from-second-desktop", "desktops/07-reopened-from-second-desktop",
                   "desktops/12-reopened-from-first-desktop", "manual-group/05-reopen-manual-group",
                   "manual-group/07-reopen-manual-group-after-close", "stage-manager-off/05-panel-stage-manager-off",
                   "stage-manager-off/08-restored-after-minimize", "stage-manager-off/11-reopened-stage-manager-off"]
    closed_labels = ["03-panel-closed-app-alive", "04a-panel-closed-before-launchservices",
                     "08a-panel-closed-after-full-screen-open", "desktops/06-closed-panel-second-desktop",
                     "desktops/10-closed-before-first-desktop", "desktops/11-first-desktop-before-reopen",
                     "manual-group/06-closed-manual-group", "stage-manager-off/09-closed-stage-manager-off"]
    for label in open_labels + closed_labels:
        data = read(label + ".json")
        product = app(data)
        opened = label in open_labels
        expected_policy = 0 if opened else 1
        check(label + ": same process remains alive", product.get("pid") == expected_pid and product.get("terminated") is False)
        check(label + ": expected Regular/Accessory policy", product.get("activationPolicy") == expected_policy)
        status = status_entry(product)
        check(label + ": enabled status-menu entry remains", len(status) == 1 and status[0].get("AXEnabled") is True)
        if opened:
            check(label + ": same visible normal-size panel", len(visible(product)) == 1 and
                  visible(product)[0].get("kCGWindowBounds", {}).get("Width", 0) >= 600 and
                  [w.get("kCGWindowNumber") for w in windows(product)] == expected_windows)
        else:
            check(label + ": panel hidden", len(visible(product)) == 0)
        check(label + ": reliable Dock presence matches lifecycle",
              dock_reliable(data, "present" if opened else "absent-in-readable-sample"))
        check(label + ": screenshot exists", (root / (label + ".png")).is_file())

    for label in ["04-reopen", "08-open-from-full-screen", "08c-reopen-from-full-screen-after-close",
                  "desktops/07-reopened-from-second-desktop", "desktops/12-reopened-from-first-desktop",
                  "manual-group/07-reopen-manual-group-after-close"]:
        action = read(label + "-menu-select-action.json")
        check(label + ": real current AX menu mouse selection",
              action.get("inputPath") == "mouse-at-current-visible-AX-menu-item-center")
    check("Dock click only while Regular", read("04c-dock-open-action.json").get("action") == "dock-open")

    # Native fullscreen: both the delegate event and real AX/window evidence
    # must exist. Maximizing a normal window cannot satisfy these checks.
    companion_log = [json.loads(line) for line in (root / "companion.jsonl").read_text().splitlines() if line.strip()]
    check("Companion entered actual native fullscreen", any(e.get("event") == "did-enter-full-screen" and e.get("fullScreen") is True for e in companion_log))
    check("Companion exited actual native fullscreen", any(e.get("event") == "did-exit-full-screen" and e.get("fullScreen") is False for e in companion_log))
    for label in ["07-companion-full-screen", "08b-native-full-screen-after-close"]:
        companion = app(read(label + ".json"), "org.yomado.qa.Companion")
        check(label + ": current fullscreen fixture is active", companion.get("active") is True and
              any(w.get("AXFullScreen") is True for w in companion.get("axWindows", [])) and
              len(visible(companion, "YOMADO QA COMPANION")) == 1)
        check(label + ": screenshot exists", (root / (label + ".png")).is_file())
    desktops = read("desktops/02-two-desktops-ax.json")
    check("two actual ordinary Desktops in Mission Control", desktops.get("desktopCount") == 2)
    for label, ordinal in [("desktops/03-select-second-action.json", 2),
                           ("desktops/06-closed-panel-second-desktop-selection.json", 2),
                           ("desktops/11-select-first-action.json", 1)]:
        action = read(label)
        check(label + ": native observed Desktop selection", action.get("desktopCount") == 2 and
              action.get("action") == f"AXPress-observed-Desktop-{ordinal}" and
              action.get("target", {}).get("AXDescription", "").startswith("exit to Desktop"))
    for label in ["desktops/05-existing-panel-space-ax.json", "desktops/08-reopened-panel-space-ax.json",
                  "desktops/13-reopened-panel-space-ax.json"]:
        check(label + ": Mission Control remained inspectable", read(label).get("desktopCount") == 2)

    minimized = app(read("stage-manager-off/06-minimized-stage-manager-off.json"))
    check("Stage Manager off genuinely minimized", any(w.get("AXMinimized") is True for w in minimized.get("axWindows", [])))
    restored = app(read("stage-manager-off/08-restored-after-minimize.json"))
    check("menu restored genuinely minimized panel", any(w.get("AXMinimized") is False for w in restored.get("axWindows", [])) and len(visible(restored)) == 1)
    controls = tree_matches(read("stage-manager-off/02-control-center-value.json"), lambda n: n.get("AXDescription") == "Stage Manager" and n.get("AXRole") == "AXCheckBox")
    check("actual Control Center Stage Manager off", bool(controls) and all(n.get("AXValue") == 0 for n in controls))
    check("manual group collected without blocked guard", read("manual-group-result.json").get("exitCode") == 0)

    timeline = [json.loads(line) for line in (root / "dock-timeline.jsonl").read_text().splitlines()]
    samples = [s for s in timeline if s.get("recordType") == "sample"]
    running = [s for s in samples if s.get("yomadoPID", -1) > 0]
    check("timeline began before product launch", bool(samples) and samples[0].get("yomadoPID") == -1)
    check("single unchanged PID throughout lifecycle", bool(running) and {s.get("yomadoPID") for s in running} == {expected_pid})
    check("both Regular and Accessory observed in timeline", {0, 1}.issubset({s.get("yomadoActivationPolicy") for s in running}))
    # Check stable phases rather than imposing the previous always-Regular rule.
    # Unknown Dock reads cannot establish absence: require positive controls and
    # at least one definitive observation in every measured quiet interval.
    for interval_file in sorted(root.rglob("*.interval.json")):
        interval = json.loads(interval_file.read_text())
        start = json.loads((interval_file.parent / interval["start"]).read_text())
        end = json.loads((interval_file.parent / interval["end"]).read_text())
        a, b = start["monotonicUptimeSeconds"], end["monotonicUptimeSeconds"]
        subset = [s for s in running if s["sampleStartUptimeSeconds"] >= a and s["sampleEndUptimeSeconds"] <= b]
        expected = interval["expectedActivationPolicy"]
        name = str(interval_file.relative_to(root))
        check(name + ": bounded stable interval sampled", b > a and bool(subset))
        check(name + ": expected policy throughout stable phase", bool(subset) and
              all(s.get("yomadoActivationPolicy") == expected for s in subset) and
              app(start).get("activationPolicy") == expected and app(end).get("activationPolicy") == expected)
        definitive = [s for s in subset if s.get("dock", {}).get("yomadoIconObservation") != "unknown"]
        wanted = "present" if expected == 0 else "absent-in-readable-sample"
        check(name + ": definitive Dock observation matches phase", bool(definitive) and
              all(dock_reliable(s, wanted) for s in definitive))
        interval_summary.append({"interval": name, "expectedActivationPolicy": expected, "samples": len(subset),
                                 "unknownDockSamples": len(subset) - len(definitive), "start": a, "end": b})
    check("quiet intervals cover all asserted open and closed states", len(interval_summary) == len(open_labels) + len(closed_labels))
    check("timeline completed by requested stop", bool(timeline) and timeline[-1].get("reason") == "requested-stop")
    check("timeline covers final stable phase", bool(interval_summary) and timeline[-1].get("endUptimeSeconds", 0) >= max(i["end"] for i in interval_summary))
except Exception as error:
    checks.append({"name": "complete expected evidence", "passed": False, "errorType": type(error).__name__, "detail": str(error)})

result = {"checks": checks, "passed": sum(c["passed"] for c in checks), "failed": sum(not c["passed"] for c in checks),
          "stableIntervals": interval_summary,
          "activationPolicyBoundary": "same PID/window; Regular while open and Accessory while closed; sampled quiet intervals required; transition samples retained without pretending fixed 0.1-second observation coverage",
          "acceptanceVerdict": "requires independent screenshots and real Space/group behavior review; structural checks alone do not prove visual grouping"}
print(json.dumps(result, indent=2))
sys.exit(0 if result["failed"] == 0 else 1)
