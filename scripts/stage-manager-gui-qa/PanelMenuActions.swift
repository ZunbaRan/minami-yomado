import AppKit
import ApplicationServices

guard ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true",
      ProcessInfo.processInfo.environment["RUNNER_ENVIRONMENT"] == "github-hosted" else {
    fputs("REFUSED: disposable hosted runner only\n", stderr); exit(64)
}
func fail(_ reason: String) -> Never { fputs("Panel menu action refused: \(reason)\n", stderr); exit(1) }
func read(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success ? value : nil
}
func string(_ element: AXUIElement, _ key: String) -> String { read(element, key) as? String ?? "" }
func children(_ element: AXUIElement) -> [AXUIElement] { read(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] }
func find(_ root: AXUIElement, matching: (AXUIElement) -> Bool) -> AXUIElement? {
    var pending = [(root, 0)]
    var matches: [AXUIElement] = []
    var visited = 0
    while let (node, depth) = pending.popLast() {
        visited += 1
        if visited > 1200 || depth > 14 { fail("incomplete app accessibility traversal") }
        if matching(node) { matches.append(node) }
        pending += children(node).map { ($0, depth + 1) }
    }
    if matches.count > 1 { fail("ambiguous menu control") }
    return matches.first
}
func bounds(_ node: AXUIElement) -> CGRect? {
    guard let position = read(node, kAXPositionAttribute), let dimensions = read(node, kAXSizeAttribute),
          CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(dimensions) == AXValueGetTypeID() else { return nil }
    let p = position as! AXValue, s = dimensions as! AXValue
    var origin = CGPoint.zero, size = CGSize.zero
    guard AXValueGetType(p) == .cgPoint, AXValueGetType(s) == .cgSize,
          AXValueGetValue(p, .cgPoint, &origin), AXValueGetValue(s, .cgSize, &size),
          origin.x.isFinite, origin.y.isFinite, size.width.isFinite, size.height.isFinite,
          size.width > 0, size.height > 0 else { return nil }
    return CGRect(origin: origin, size: size)
}
func describe(_ node: AXUIElement) -> [String: Any] {
    ["role": string(node, kAXRoleAttribute), "subrole": string(node, kAXSubroleAttribute),
     "title": string(node, kAXTitleAttribute), "description": string(node, kAXDescriptionAttribute),
     "identifier": string(node, "AXIdentifier"),
     "enabled": (read(node, kAXEnabledAttribute) as? NSNumber)?.boolValue ?? false,
     "nonzeroSize": bounds(node) != nil]
}
func moveMouse(_ point: CGPoint) {
    guard CGDisplayBounds(CGMainDisplayID()).contains(point),
          let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left) else {
        fail("mouse move point or event invalid")
    }
    move.post(tap: .cghidEventTap)
}
func clickMouse(_ point: CGPoint) {
    guard CGDisplayBounds(CGMainDisplayID()).contains(point),
          let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
          let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) else {
        fail("mouse click point or events invalid")
    }
    down.setIntegerValueField(.mouseEventClickState, value: 1)
    up.setIntegerValueField(.mouseEventClickState, value: 1)
    down.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 0.08)
    up.post(tap: .cghidEventTap)
}

let args = Array(CommandLine.arguments.dropFirst())
guard args.count == 2, let pid = Int32(args[0]), pid > 0,
      let app = NSRunningApplication(processIdentifier: pid), app.bundleIdentifier == "dev.chekusu.yomado",
      AXIsProcessTrusted() else { fail("expected the owned Yomado PID, command and Accessibility access") }
let root = AXUIElementCreateApplication(pid)
func menuExtra() -> AXUIElement? {
    // This exact role/subrole/description was observed in real app artifacts.
    find(root) { string($0, kAXRoleAttribute) == kAXMenuBarItemRole
        && string($0, kAXSubroleAttribute) == "AXMenuExtra"
        && string($0, kAXDescriptionAttribute) == "yomado · 夜窗" }
}
guard let extra = menuExtra() else { fail("observed yomado status-menu control is unavailable") }
var record: [String: Any] = ["pid": pid, "command": args[1], "statusMenu": describe(extra),
                            "startUptimeSeconds": ProcessInfo.processInfo.systemUptime]
switch args[1] {
case "open":
    // AXPress on this menu extra enters a tracking loop and returned
    // cannotComplete in the real run. Click the current AX-reported icon
    // bounds instead, matching a person's actual status-bar entry path.
    guard let initial = bounds(extra) else { fail("status icon geometry unavailable") }
    let display = CGDisplayBounds(CGMainDisplayID())
    if initial.minY < display.minY {
        // The actual full-screen run reported y=-59. Reveal the native hidden
        // menu bar at this same observed x, then discard that stale geometry.
        let hover = CGPoint(x: initial.midX, y: display.minY + 1)
        moveMouse(hover)
        record["menuBarReveal"] = ["hoverPoint": [hover.x, hover.y],
                                   "initialAXBounds": [initial.minX, initial.minY, initial.width, initial.height]]
    }
    var visibleIcon: AXUIElement?
    for _ in 0..<40 {
        if let current = menuExtra(), let frame = bounds(current), display.contains(frame),
           (read(current, kAXEnabledAttribute) as? NSNumber)?.boolValue == true {
            visibleIcon = current; break
        }
        Thread.sleep(forTimeInterval: 0.1)
    }
    guard let visibleIcon, let visibleFrame = bounds(visibleIcon), display.contains(visibleFrame) else {
        fail("status icon did not become fully visible after bounded menu-bar reveal")
    }
    moveMouse(CGPoint(x: visibleFrame.midX, y: visibleFrame.midY))
    Thread.sleep(forTimeInterval: 0.3)
    guard let current = menuExtra(), let finalFrame = bounds(current), display.contains(finalFrame),
          (read(current, kAXEnabledAttribute) as? NSNumber)?.boolValue == true else { fail("status icon changed before click") }
    let point = CGPoint(x: finalFrame.midX, y: finalFrame.midY)
    moveMouse(point)
    clickMouse(point)
    record["inputPath"] = "mouse-at-current-AX-status-icon-center"
    record["observedPoint"] = [point.x, point.y]
case "select-open-panel":
    var target: AXUIElement?
    for _ in 0..<30 {
        if let currentExtra = menuExtra(), let item = find(currentExtra, matching: {
            string($0, kAXRoleAttribute) == kAXMenuItemRole
                && string($0, kAXTitleAttribute) == "打开控制面板"
        }), let frame = bounds(item), CGDisplayBounds(CGMainDisplayID()).contains(frame),
           (read(item, kAXEnabledAttribute) as? NSNumber)?.boolValue == true {
            target = item; break
        }
        Thread.sleep(forTimeInterval: 0.1)
    }
    guard let target else { fail("actual visible Open Control Panel menu item did not become available") }
    record["selectedItem"] = describe(target)
    guard let frame = bounds(target) else { fail("selected menu item geometry unavailable") }
    moveMouse(CGPoint(x: frame.midX, y: frame.midY))
    Thread.sleep(forTimeInterval: 0.2)
    guard let currentExtra = menuExtra(), let current = find(currentExtra, matching: {
        string($0, kAXRoleAttribute) == kAXMenuItemRole && string($0, kAXTitleAttribute) == "打开控制面板"
    }), let finalFrame = bounds(current), CGDisplayBounds(CGMainDisplayID()).contains(finalFrame),
          (read(current, kAXEnabledAttribute) as? NSNumber)?.boolValue == true else { fail("menu item changed before actual click") }
    let point = CGPoint(x: finalFrame.midX, y: finalFrame.midY)
    moveMouse(point)
    clickMouse(point)
    record["inputPath"] = "mouse-at-current-visible-AX-menu-item-center"
    record["observedPoint"] = [point.x, point.y]
default: fail("unsupported command")
}
record["endUptimeSeconds"] = ProcessInfo.processInfo.systemUptime
record["actionResult"] = "mouse-posted-result-must-be-verified"
let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
print(String(data: data, encoding: .utf8)!)
