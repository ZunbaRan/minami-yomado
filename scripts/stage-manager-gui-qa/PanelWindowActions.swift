import AppKit
import ApplicationServices

guard ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true",
      ProcessInfo.processInfo.environment["RUNNER_ENVIRONMENT"] == "github-hosted" else { exit(64) }
func fail(_ message: String) -> Never { fputs("Panel window action refused: \(message)\n", stderr); exit(1) }
func read(_ node: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(node, name as CFString, &value) == .success ? value : nil
}
func text(_ node: AXUIElement, _ name: String) -> String { read(node, name) as? String ?? "" }
func rect(_ node: AXUIElement) -> CGRect? {
    guard let p = read(node, kAXPositionAttribute), CFGetTypeID(p) == AXValueGetTypeID(),
          let s = read(node, kAXSizeAttribute), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
    var point = CGPoint.zero, size = CGSize.zero
    guard AXValueGetValue(p as! AXValue, .cgPoint, &point), AXValueGetValue(s as! AXValue, .cgSize, &size),
          point.x.isFinite, point.y.isFinite, size.width > 0, size.height > 0 else { return nil }
    return CGRect(origin: point, size: size)
}
func unique(_ root: AXUIElement, matching predicate: (AXUIElement) -> Bool) -> AXUIElement {
    var pending = [(root, 0)], matches: [AXUIElement] = [], count = 0
    while let (node, depth) = pending.popLast() {
        count += 1
        if count > 1500 || depth > 16 { fail("bounded tree traversal incomplete") }
        if predicate(node) { matches.append(node) }
        pending += (read(node, kAXChildrenAttribute) as? [AXUIElement] ?? []).map { ($0, depth + 1) }
    }
    guard matches.count == 1 else { fail("expected one exact current control, found \(matches.count)") }
    return matches[0]
}
let args = Array(CommandLine.arguments.dropFirst())
guard args.count == 2, let pid = Int32(args[0]),
      let product = NSRunningApplication(processIdentifier: pid), product.bundleIdentifier == "dev.chekusu.yomado",
      AXIsProcessTrusted() else { fail("expected owned Yomado PID and Accessibility access") }
let target: AXUIElement
switch args[1] {
case "minimize":
    let app = AXUIElementCreateApplication(pid)
    let windows = (read(app, kAXWindowsAttribute) as? [AXUIElement] ?? []).filter { text($0, kAXTitleAttribute) == "yomado" }
    guard windows.count == 1 else { fail("expected one owned panel") }
    target = unique(windows[0]) { text($0, kAXRoleAttribute) == kAXButtonRole && text($0, kAXSubroleAttribute) == kAXMinimizeButtonSubrole }
    guard (read(target, kAXEnabledAttribute) as? NSNumber)?.boolValue == true else { fail("minimize button is disabled") }
case "dock-open":
    guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first,
          let productURL = product.bundleURL?.standardizedFileURL else { fail("Dock or running bundle URL unavailable") }
    target = unique(AXUIElementCreateApplication(dock.processIdentifier)) {
        guard text($0, kAXRoleAttribute) == "AXDockItem", text($0, kAXSubroleAttribute) == "AXApplicationDockItem",
              text($0, kAXTitleAttribute) == "yomado", let url = read($0, kAXURLAttribute) as? URL else { return false }
        return url.standardizedFileURL == productURL
    }
default: fail("unsupported action")
}
guard let initial = rect(target), CGDisplayBounds(CGMainDisplayID()).contains(initial),
      let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                         mouseCursorPosition: CGPoint(x: initial.midX, y: initial.midY), mouseButton: .left) else { fail("control is not currently visible") }
move.post(tap: .cghidEventTap)
Thread.sleep(forTimeInterval: 0.3)
guard let current = rect(target), CGDisplayBounds(CGMainDisplayID()).contains(current), !product.isTerminated else { fail("control changed before click") }
let point = CGPoint(x: current.midX, y: current.midY)
guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
      let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) else { fail("event creation failed") }
down.setIntegerValueField(.mouseEventClickState, value: 1); up.setIntegerValueField(.mouseEventClickState, value: 1)
down.post(tap: .cghidEventTap); Thread.sleep(forTimeInterval: 0.08); up.post(tap: .cghidEventTap)
let data = try! JSONSerialization.data(withJSONObject: ["pid": pid, "action": args[1],
    "role": text(target, kAXRoleAttribute), "subrole": text(target, kAXSubroleAttribute), "title": text(target, kAXTitleAttribute),
    "observedPoint": [point.x, point.y], "inputPath": "real mouse click at current exact AX control",
    "actionResult": "input sent; verify actual state and screenshot"], options: [.sortedKeys])
print(String(data: data, encoding: .utf8)!)
