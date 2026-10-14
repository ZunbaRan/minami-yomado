import AppKit
import ApplicationServices

guard ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true",
      ProcessInfo.processInfo.environment["RUNNER_ENVIRONMENT"] == "github-hosted" else { exit(64) }
func fail(_ message: String) -> Never { fputs("Space switching setup refused: \(message)\n", stderr); exit(1) }
func read(_ node: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(node, name as CFString, &value) == .success ? value : nil
}
func text(_ node: AXUIElement, _ name: String) -> String { read(node, name) as? String ?? "" }
func label(_ node: AXUIElement) -> String {
    var parts = [text(node, kAXTitleAttribute), text(node, kAXDescriptionAttribute)]
    if let titleNode = read(node, kAXTitleUIElementAttribute), CFGetTypeID(titleNode) == AXUIElementGetTypeID() {
        parts.append(text(titleNode as! AXUIElement, kAXValueAttribute))
        parts.append(text(titleNode as! AXUIElement, kAXTitleAttribute))
    }
    return parts.joined(separator: " ")
}
let mode = CommandLine.arguments.last ?? ""
guard ["default", "off"].contains(mode), AXIsProcessTrusted() else { fail("expected default/off and Accessibility access") }
let expectedLabel = "When switching to an application, switch to a Space with open windows for the application"
let oldPIDs = Set(NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences").map(\.processIdentifier))
guard let settingsURL = URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension"),
      NSWorkspace.shared.open(settingsURL) else { fail("cannot open Desktop & Dock settings") }
var setting: AXUIElement?
var settingsApp: NSRunningApplication?
for _ in 0..<60 {
    if let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences").first {
        settingsApp = app
        var pending = [(AXUIElementCreateApplication(app.processIdentifier), 0)]
        var matches: [AXUIElement] = []
        var count = 0
        while let (node, depth) = pending.popLast() {
            count += 1
            if count > 10000 || depth > 35 { fail("settings tree exceeds bounded traversal") }
            let role = text(node, kAXRoleAttribute)
            if [kAXCheckBoxRole, "AXSwitch"].contains(role), label(node).contains(expectedLabel) { matches.append(node) }
            pending += (read(node, kAXChildrenAttribute) as? [AXUIElement] ?? []).map { ($0, depth + 1) }
        }
        if matches.count > 1 { fail("ambiguous Space switching control") }
        if let match = matches.first { setting = match; break }
    }
    Thread.sleep(forTimeInterval: 0.25)
}
guard let setting, let settingsApp,
      (read(setting, kAXEnabledAttribute) as? NSNumber)?.boolValue == true,
      let before = read(setting, kAXValueAttribute) as? NSNumber else { fail("named Space switching control unavailable or unreadable") }
let expected = mode == "off" ? 0 : 1
if mode == "off", before.intValue != 0 {
    guard AXUIElementPerformAction(setting, kAXPressAction as CFString) == .success else { fail("native setting press failed") }
    Thread.sleep(forTimeInterval: 0.5)
}
guard let after = read(setting, kAXValueAttribute) as? NSNumber, after.intValue == expected else {
    fail("actual checkbox value does not match requested mode; do not infer success from preferences")
}
let result: [String: Any] = ["mode": mode, "label": expectedLabel, "role": text(setting, kAXRoleAttribute),
    "beforeValue": before, "afterValue": after, "settingsPID": settingsApp.processIdentifier,
    "settingsStartedByThisInvocation": !oldPIDs.contains(settingsApp.processIdentifier),
    "source": "actual System Settings accessibility checkbox", "requiresRuntimeBehaviorReview": true]
let data = try! JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
print(String(data: data, encoding: .utf8)!)
