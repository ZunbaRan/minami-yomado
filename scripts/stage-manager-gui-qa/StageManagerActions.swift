import AppKit
import ApplicationServices

guard ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true",
      ProcessInfo.processInfo.environment["RUNNER_ENVIRONMENT"] == "github-hosted" else { exit(64) }
func fail(_ reason: String) -> Never { fputs("Stage Manager action refused: \(reason)\n", stderr); exit(1) }
func attr(_ node: AXUIElement, _ name: String) -> CFTypeRef? {
    var result: CFTypeRef?
    guard AXUIElementCopyAttributeValue(node, name as CFString, &result) == .success else { return nil }
    return result
}
func match(_ root: AXUIElement, role: String, description: String, attribute: String = kAXDescriptionAttribute) -> AXUIElement? {
    var pending = [(root, 0)], found: [AXUIElement] = [], visited = 0
    while let (node, depth) = pending.popLast() {
        visited += 1
        if visited > 1600 || depth > 14 { fail("incomplete AX traversal") }
        if attr(node, kAXRoleAttribute) as? String == role,
           attr(node, attribute) as? String == description { found.append(node) }
        pending += ((attr(node, kAXChildrenAttribute) as? [AXUIElement]) ?? []).map { ($0, depth+1) }
    }
    if found.count > 1 { fail("ambiguous control") }
    return found.first
}
func press(_ node: AXUIElement) {
    guard (attr(node, kAXEnabledAttribute) as? NSNumber)?.boolValue != false,
          AXUIElementPerformAction(node, kAXPressAction as CFString) == .success else { fail("AXPress failed") }
}
if CommandLine.arguments.last == "finish-onboarding" {
    guard let manager = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.WindowManager").first else { fail("Window Manager absent") }
    let managerRoot = AXUIElementCreateApplication(manager.processIdentifier)
    // This exact system-owned title/button was visible in the previous CI
    // screenshots; re-read it and use its native accessibility action.
    func onboardingButton() -> AXUIElement? {
        match(managerRoot, role: kAXButtonRole, description: "Turn On Stage Manager", attribute: kAXTitleAttribute)
            ?? match(managerRoot, role: kAXButtonRole, description: "Turn On Stage Manager")
    }
    manager.activate(options: [])
    Thread.sleep(forTimeInterval: 1)
    var candidate: AXUIElement?
    for _ in 0..<20 {
        if let button = onboardingButton(),
           (attr(button, kAXEnabledAttribute) as? NSNumber)?.boolValue == true { candidate = button; break }
        Thread.sleep(forTimeInterval: 0.25)
    }
    if let button = candidate {
        press(button); Thread.sleep(forTimeInterval: 2)
        if onboardingButton() != nil { fail("onboarding remains after native action") }
        print("Completed observed Stage Manager onboarding with native AXPress"); exit(0)
    }
    // The system intro was visible but had no AX windows/buttons. The prior
    // real 1024x768 capture showed exactly this 640x600 window at (192,84),
    // with the Turn On button centered at (726,647). Permit only that observed
    // geometry in the empty disposable guest; a changed layout must stop.
    func observedIntro() -> [String: Any]? {
        let all = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        let matches = all.filter { item in
            guard let b = item[kCGWindowBounds as String] as? [String: NSNumber] else { return false }
            return abs((b["X"]?.doubleValue ?? -10000)-192)<2
                && abs((b["Y"]?.doubleValue ?? -10000)-84)<2
                && abs((b["Width"]?.doubleValue ?? 0)-640)<2
                && abs((b["Height"]?.doubleValue ?? 0)-600)<2
        }
        return matches.count == 1 ? matches[0] : nil
    }
    guard CGDisplayBounds(CGMainDisplayID()).size == CGSize(width: 1024, height: 768),
          let intro = observedIntro() else { fail("AX unavailable and observed intro geometry does not match") }
    let record = intro.filter { [kCGWindowOwnerName as String, kCGWindowOwnerPID as String,
        kCGWindowName as String, kCGWindowBounds as String].contains($0.key) }
    let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
    print("Observed intro mouse fallback: " + String(data: data, encoding: .utf8)!)
    for _ in 0..<2 {
        if observedIntro() == nil { break }
        let point = CGPoint(x: 726, y: 647)
        guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
              let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) else { fail("mouse event construction failed") }
        down.post(tap: .cghidEventTap); Thread.sleep(forTimeInterval: 0.08); up.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 2)
    }
    guard observedIntro() == nil else { fail("observed intro remains after bounded mouse action") }
    print("Observed intro dismissed; actual regular-app grouping still requires visual verification"); exit(0)
}
guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.controlcenter").first,
      AXIsProcessTrusted() else { fail("Control Center or AX unavailable") }
let root = AXUIElementCreateApplication(app.processIdentifier)
if match(root, role: kAXCheckBoxRole, description: "Stage Manager") == nil {
    guard let opener = match(root, role: kAXMenuBarItemRole, description: "Control Center") else { fail("observed Control Center opener absent") }
    press(opener); Thread.sleep(forTimeInterval: 1)
}
guard let toggle = match(root, role: kAXCheckBoxRole, description: "Stage Manager"),
      (attr(toggle, kAXEnabledAttribute) as? NSNumber)?.boolValue == true,
      let previous = attr(toggle, kAXValueAttribute) as? NSNumber else { fail("observed enabled Stage Manager switch/value absent") }
let desired = CommandLine.arguments.last == "on"
if previous.boolValue != desired { press(toggle) }
Thread.sleep(forTimeInterval: 0.5)
print("Stage Manager request=\(desired ? "on" : "off") previousAXValue=\(previous) action=\(previous.boolValue == desired ? "unchanged" : "AXPress")")
