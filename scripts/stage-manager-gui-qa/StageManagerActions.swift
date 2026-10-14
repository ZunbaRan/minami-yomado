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
func match(_ root: AXUIElement, role: String, description: String) -> AXUIElement? {
    var pending = [(root, 0)], found: [AXUIElement] = [], visited = 0
    while let (node, depth) = pending.popLast() {
        visited += 1
        if visited > 1600 || depth > 14 { fail("incomplete AX traversal") }
        if attr(node, kAXRoleAttribute) as? String == role,
           attr(node, kAXDescriptionAttribute) as? String == description { found.append(node) }
        pending += ((attr(node, kAXChildrenAttribute) as? [AXUIElement]) ?? []).map { ($0, depth+1) }
    }
    if found.count > 1 { fail("ambiguous control") }
    return found.first
}
func press(_ node: AXUIElement) {
    guard (attr(node, kAXEnabledAttribute) as? NSNumber)?.boolValue != false,
          AXUIElementPerformAction(node, kAXPressAction as CFString) == .success else { fail("AXPress failed") }
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
