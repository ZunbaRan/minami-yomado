import AppKit
import ApplicationServices

guard ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true",
      ProcessInfo.processInfo.environment["RUNNER_ENVIRONMENT"] == "github-hosted" else {
    fputs("REFUSED: disposable hosted runner only\n", stderr); exit(64)
}

func read(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success ? value : nil
}
func children(_ element: AXUIElement) -> [AXUIElement] { read(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] }
func string(_ element: AXUIElement, _ key: String) -> String { read(element, key) as? String ?? "" }
func fail(_ reason: String) -> Never { fputs("Desktop action refused: \(reason)\n", stderr); exit(1) }
func find(_ root: AXUIElement, identifier: String) -> AXUIElement? {
    var pending = [(root, 0)]
    var matches: [AXUIElement] = []
    var visited = 0
    while let (node, depth) = pending.popLast() {
        visited += 1
        if visited > 1600 || depth > 14 { fail("incomplete system UI traversal") }
        if string(node, "AXIdentifier") == identifier { matches.append(node) }
        pending += children(node).map { ($0, depth + 1) }
    }
    if matches.count > 1 { fail("ambiguous native control: \(identifier)") }
    return matches.first
}
func describe(_ node: AXUIElement) -> [String: Any] {
    var result: [String: Any] = [:]
    for key in [kAXRoleAttribute, kAXTitleAttribute, kAXDescriptionAttribute, "AXIdentifier"] {
        result[key] = string(node, key)
    }
    for key in [kAXEnabledAttribute, kAXSelectedAttribute, kAXFocusedAttribute] {
        if let value = read(node, key) as? NSNumber { result[key] = value }
    }
    return result
}
func press(_ node: AXUIElement) {
    guard (read(node, kAXEnabledAttribute) as? NSNumber)?.boolValue == true else { fail("control disabled or unknown") }
    var names: CFArray?
    guard AXUIElementCopyActionNames(node, &names) == .success,
          (names as? [String] ?? []).contains(kAXPressAction) else { fail("native AXPress action unavailable") }
    let result = AXUIElementPerformAction(node, kAXPressAction as CFString)
    if result != .success { fail("native AXPress returned \(result.rawValue)") }
}

guard AXIsProcessTrusted(), let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
    fail("Dock/Accessibility unavailable")
}
let root = AXUIElementCreateApplication(dock.processIdentifier)
guard let mission = find(root, identifier: "mc"),
      let spaces = find(mission, identifier: "mc.spaces.list"),
      let add = find(mission, identifier: "mc.spaces.add") else { fail("observed Mission Control identifiers unavailable") }
let desktops = children(spaces).filter {
    string($0, kAXRoleAttribute) == kAXButtonRole
        && string($0, kAXDescriptionAttribute).hasPrefix("exit to Desktop")
}
let args = Array(CommandLine.arguments.dropFirst())
var result: [String: Any] = ["desktopCount": desktops.count, "desktops": desktops.map(describe), "addControl": describe(add)]
switch args.first ?? "inspect" {
case "inspect": result["action"] = "none"
case "create-second":
    guard desktops.count == 1 else { fail("expected exactly one existing ordinary Desktop") }
    result["action"] = "AXPress-observed-mc.spaces.add"
    press(add)
case "select":
    guard args.count == 2, let ordinal = Int(args[1]), desktops.count == 2,
          ordinal >= 1, ordinal <= desktops.count else { fail("expected exactly two observed Desktops and ordinal 1 or 2") }
    result["action"] = "AXPress-observed-Desktop-\(ordinal)"
    result["target"] = describe(desktops[ordinal - 1])
    press(desktops[ordinal - 1])
default: fail("unknown action")
}
let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
print(String(data: data, encoding: .utf8)!)
