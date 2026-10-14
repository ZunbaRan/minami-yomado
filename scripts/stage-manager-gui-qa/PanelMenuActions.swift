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
func nonzeroSize(_ node: AXUIElement) -> Bool {
    guard let value = read(node, kAXSizeAttribute), CFGetTypeID(value) == AXValueGetTypeID() else { return false }
    let ax = value as! AXValue
    guard AXValueGetType(ax) == .cgSize else { return false }
    var size = CGSize.zero
    return AXValueGetValue(ax, .cgSize, &size) && size.width > 0 && size.height > 0
}
func describe(_ node: AXUIElement) -> [String: Any] {
    ["role": string(node, kAXRoleAttribute), "subrole": string(node, kAXSubroleAttribute),
     "title": string(node, kAXTitleAttribute), "description": string(node, kAXDescriptionAttribute),
     "identifier": string(node, "AXIdentifier"),
     "enabled": (read(node, kAXEnabledAttribute) as? NSNumber)?.boolValue ?? false,
     "nonzeroSize": nonzeroSize(node)]
}
func press(_ node: AXUIElement) {
    guard (read(node, kAXEnabledAttribute) as? NSNumber)?.boolValue == true else { fail("control is disabled or unknown") }
    var names: CFArray?
    guard AXUIElementCopyActionNames(node, &names) == .success,
          (names as? [String] ?? []).contains(kAXPressAction) else { fail("native AXPress unavailable") }
    let error = AXUIElementPerformAction(node, kAXPressAction as CFString)
    if error != .success { fail("native AXPress returned \(error.rawValue)") }
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
    press(extra)
case "select-open-panel":
    var target: AXUIElement?
    for _ in 0..<30 {
        if let currentExtra = menuExtra(), let item = find(currentExtra, matching: {
            string($0, kAXRoleAttribute) == kAXMenuItemRole
                && string($0, kAXTitleAttribute) == "打开控制面板"
        }), nonzeroSize(item), (read(item, kAXEnabledAttribute) as? NSNumber)?.boolValue == true {
            target = item; break
        }
        Thread.sleep(forTimeInterval: 0.1)
    }
    guard let target else { fail("actual visible Open Control Panel menu item did not become available") }
    record["selectedItem"] = describe(target)
    press(target)
default: fail("unsupported command")
}
record["endUptimeSeconds"] = ProcessInfo.processInfo.systemUptime
record["nativeActionResult"] = "success"
let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
print(String(data: data, encoding: .utf8)!)
