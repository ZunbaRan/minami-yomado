import AppKit
import ApplicationServices
import ScreenCaptureKit
import ImageIO
import UniformTypeIdentifiers

guard ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true",
      ProcessInfo.processInfo.environment["RUNNER_ENVIRONMENT"] == "github-hosted" else {
    fputs("REFUSED: disposable hosted runner only\n", stderr); exit(64)
}
var geometryEvidence: [String: Any] = [:]
struct DisplayGeometry {
    let id: CGDirectDisplayID
    let frame: CGRect
    var json: [String: Any] {
        ["id": id, "main": CGDisplayIsMain(id) != 0,
         "bounds": [frame.minX, frame.minY, frame.width, frame.height]]
    }
}
func displays() -> [DisplayGeometry] {
    var ids = [CGDirectDisplayID](repeating: 0, count: 128), count: UInt32 = 0
    guard CGGetOnlineDisplayList(128, &ids, &count) == .success, count < 128 else { return [] }
    return ids.prefix(Int(count)).filter { CGDisplayIsActive($0) != 0 }.map {
        DisplayGeometry(id: $0, frame: CGDisplayBounds($0))
    }.filter { !$0.frame.isEmpty && !$0.frame.isInfinite && !$0.frame.isNull }
}
func displayContaining(_ frame: CGRect) -> DisplayGeometry? {
    let matches = displays().filter { $0.frame.contains(frame) }
    return matches.count == 1 ? matches[0] : nil
}
func revealDisplay(for frame: CGRect) -> DisplayGeometry? {
    if let visible = displayContaining(frame) { return visible }
    // A hidden menu extra is reported just above its display. Associate it
    // only when the observed horizontal interval and adjacent top edge give
    // exactly one answer; never substitute the primary display's coordinates.
    let matches = displays().filter {
        frame.minX >= $0.frame.minX && frame.maxX <= $0.frame.maxX
            && frame.minY < $0.frame.minY
            && $0.frame.minY - frame.minY <= max(128, frame.height * 4)
    }
    return matches.count == 1 ? matches[0] : nil
}
func captureFailureImages(in directory: URL) -> [[String: Any]] {
    guard CGPreflightScreenCaptureAccess() else { return [["error": "screen capture unavailable"]] }
    var content: SCShareableContent?, done = false
    SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { value, _ in
        content = value; done = true
    }
    var deadline = Date().addingTimeInterval(3)
    while !done && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
    guard let content else { return [["error": "capture inventory unavailable"]] }
    var results: [[String: Any]] = []
    for display in content.displays.prefix(4) {
        let configuration = SCStreamConfiguration()
        configuration.width = display.width; configuration.height = display.height; configuration.showsCursor = true
        var image: CGImage?, completed = false
        SCScreenshotManager.captureImage(contentFilter: SCContentFilter(display: display, excludingWindows: []),
                                        configuration: configuration) { value, _ in image = value; completed = true }
        deadline = Date().addingTimeInterval(2)
        while !completed && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        let name = "menu-failure-\(ProcessInfo.processInfo.processIdentifier)-display-\(display.displayID).png"
        if let image, let target = CGImageDestinationCreateWithURL(directory.appendingPathComponent(name) as CFURL,
                                                                 UTType.png.identifier as CFString, 1, nil) {
            CGImageDestinationAddImage(target, image, nil)
            results.append(["displayID": display.displayID, "image": name, "saved": CGImageDestinationFinalize(target)])
        } else {
            results.append(["displayID": display.displayID, "error": "capture did not complete"])
        }
    }
    return results
}
func fail(_ reason: String) -> Never {
    geometryEvidence["error"] = reason
    geometryEvidence["latestOnlineDisplayBounds"] = displays().map { $0.json }
    if let path = ProcessInfo.processInfo.environment["YM_QA_MENU_FAILURE_DIRECTORY"] {
        let directory = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        geometryEvidence["screenshots"] = captureFailureImages(in: directory)
        if let data = try? JSONSerialization.data(withJSONObject: geometryEvidence, options: [.sortedKeys, .prettyPrinted]) {
            try? data.write(to: directory.appendingPathComponent("menu-failure-\(ProcessInfo.processInfo.processIdentifier).json"))
        }
    }
    if let data = try? JSONSerialization.data(withJSONObject: geometryEvidence, options: [.sortedKeys]),
       let text = String(data: data, encoding: .utf8) { print(text) }
    fputs("Panel menu action refused: \(reason)\n", stderr); exit(1)
}
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
     "nonzeroSize": bounds(node) != nil,
     "bounds": bounds(node).map { [$0.minX, $0.minY, $0.width, $0.height] } ?? []]
}
func moveMouse(_ point: CGPoint) {
    guard displays().contains(where: { $0.frame.contains(point) }),
          let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left) else {
        fail("mouse move point or event invalid")
    }
    move.post(tap: .cghidEventTap)
}
func clickMouse(_ point: CGPoint) {
    guard displays().contains(where: { $0.frame.contains(point) }),
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
geometryEvidence = ["pid": pid, "command": args[1], "initialOnlineDisplayBounds": displays().map { $0.json }]
func menuExtra() -> AXUIElement? {
    // This exact role/subrole/description was observed in real app artifacts.
    find(root) { string($0, kAXRoleAttribute) == kAXMenuBarItemRole
        && string($0, kAXSubroleAttribute) == "AXMenuExtra"
        && string($0, kAXDescriptionAttribute) == "yomado · 夜窗" }
}
guard let extra = menuExtra() else { fail("observed yomado status-menu control is unavailable") }
var record: [String: Any] = ["pid": pid, "command": args[1], "statusMenu": describe(extra),
                            "startUptimeSeconds": ProcessInfo.processInfo.systemUptime]
geometryEvidence["initialStatusMenu"] = describe(extra)
switch args[1] {
case "open":
    // AXPress on this menu extra enters a tracking loop and returned
    // cannotComplete in the real run. Click the current AX-reported icon
    // bounds instead, matching a person's actual status-bar entry path.
    guard let initial = bounds(extra) else { fail("status icon geometry unavailable") }
    guard let initialDisplay = revealDisplay(for: initial) else { fail("observed status icon cannot be uniquely associated with an online display") }
    geometryEvidence["initialAssociatedDisplay"] = initialDisplay.json
    if initial.minY < initialDisplay.frame.minY {
        // The actual full-screen run reported y=-59. Reveal the native hidden
        // menu bar at this same observed x, then discard that stale geometry.
        let hover = CGPoint(x: initial.midX, y: initialDisplay.frame.minY + 1)
        moveMouse(hover)
        record["menuBarReveal"] = ["hoverPoint": [hover.x, hover.y],
                                   "initialAXBounds": [initial.minX, initial.minY, initial.width, initial.height]]
    }
    var visibleIcon: AXUIElement?
    for _ in 0..<40 {
        if let current = menuExtra() {
            geometryEvidence["latestStatusMenu"] = describe(current)
            if let frame = bounds(current), let liveDisplay = displayContaining(frame),
               (read(current, kAXEnabledAttribute) as? NSNumber)?.boolValue == true {
                geometryEvidence["latestAssociatedDisplay"] = liveDisplay.json
                visibleIcon = current; break
            }
        }
        Thread.sleep(forTimeInterval: 0.1)
    }
    guard let visibleIcon, let visibleFrame = bounds(visibleIcon), displayContaining(visibleFrame) != nil else {
        fail("status icon did not become fully visible after bounded menu-bar reveal")
    }
    moveMouse(CGPoint(x: visibleFrame.midX, y: visibleFrame.midY))
    Thread.sleep(forTimeInterval: 0.3)
    guard let current = menuExtra(), let finalFrame = bounds(current), let finalDisplay = displayContaining(finalFrame),
          (read(current, kAXEnabledAttribute) as? NSNumber)?.boolValue == true else { fail("status icon changed before click") }
    let point = CGPoint(x: finalFrame.midX, y: finalFrame.midY)
    moveMouse(point)
    clickMouse(point)
    record["inputPath"] = "mouse-at-current-AX-status-icon-center"
    record["observedPoint"] = [point.x, point.y]
    record["clickedDisplay"] = finalDisplay.json
case "select-open-panel":
    var target: AXUIElement?
    for _ in 0..<30 {
        if let currentExtra = menuExtra() {
            geometryEvidence["latestStatusMenu"] = describe(currentExtra)
            if let item = find(currentExtra, matching: {
                string($0, kAXRoleAttribute) == kAXMenuItemRole
                    && string($0, kAXTitleAttribute) == "打开控制面板"
            }) {
                geometryEvidence["latestOpenPanelMenuItem"] = describe(item)
                if let frame = bounds(item), let liveDisplay = displayContaining(frame),
                   (read(item, kAXEnabledAttribute) as? NSNumber)?.boolValue == true {
                    geometryEvidence["latestAssociatedDisplay"] = liveDisplay.json
                    target = item; break
                }
            }
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
    }), let finalFrame = bounds(current), let finalDisplay = displayContaining(finalFrame),
          (read(current, kAXEnabledAttribute) as? NSNumber)?.boolValue == true else { fail("menu item changed before actual click") }
    let point = CGPoint(x: finalFrame.midX, y: finalFrame.midY)
    moveMouse(point)
    clickMouse(point)
    record["inputPath"] = "mouse-at-current-visible-AX-menu-item-center"
    record["observedPoint"] = [point.x, point.y]
    record["clickedDisplay"] = finalDisplay.json
default: fail("unsupported command")
}
record["endUptimeSeconds"] = ProcessInfo.processInfo.systemUptime
record["actionResult"] = "mouse-posted-result-must-be-verified"
record["geometryEvidence"] = geometryEvidence
let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
print(String(data: data, encoding: .utf8)!)
