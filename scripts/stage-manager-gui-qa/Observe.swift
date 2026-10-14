import AppKit
import ApplicationServices

guard ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true",
      ProcessInfo.processInfo.environment["RUNNER_ENVIRONMENT"] == "github-hosted" else {
    fputs("REFUSED: disposable hosted runner only\n", stderr)
    exit(64)
}
let ownedBundleIDs = ["dev.chekusu.yomado", "org.yomado.qa.Companion"]

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var result: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else { return nil }
    return result
}

func elements(_ element: AXUIElement, _ name: String) -> [AXUIElement] {
    attribute(element, name) as? [AXUIElement] ?? []
}

func stringAttribute(_ element: AXUIElement, _ name: String) -> String? {
    attribute(element, name) as? String
}

func tree(_ element: AXUIElement, depth: Int, budget: inout Int) -> [String: Any] {
    guard depth >= 0, budget > 0 else { return ["truncated": true] }
    budget -= 1
    var result: [String: Any] = [:]
    for name in [kAXRoleAttribute, kAXSubroleAttribute, kAXTitleAttribute, kAXDescriptionAttribute] {
        if let value = stringAttribute(element, name) { result[name] = value }
    }
    for name in [kAXFocusedAttribute, kAXMainAttribute, kAXMinimizedAttribute, "AXFullScreen"] {
        if let value = attribute(element, name) as? NSNumber { result[name] = value }
    }
    for name in [kAXPositionAttribute, kAXSizeAttribute] {
        if let value = attribute(element, name), CFGetTypeID(value) == AXValueGetTypeID() {
            let ax = value as! AXValue
            if AXValueGetType(ax) == .cgPoint {
                var point = CGPoint.zero
                if AXValueGetValue(ax, .cgPoint, &point) { result[name] = [point.x, point.y] }
            } else if AXValueGetType(ax) == .cgSize {
                var size = CGSize.zero
                if AXValueGetValue(ax, .cgSize, &size) { result[name] = [size.width, size.height] }
            }
        }
    }
    if depth > 0 {
        result["children"] = elements(element, kAXChildrenAttribute).prefix(80).map {
            tree($0, depth: depth - 1, budget: &budget)
        }
    }
    return result
}

func dockYomadoItems() -> [[String: Any]] {
    guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return [] }
    var pending = [(AXUIElementCreateApplication(dock.processIdentifier), 0)]
    var result: [[String: Any]] = []
    var visited = 0
    while let (node, depth) = pending.popLast(), visited < 400 {
        visited += 1
        let title = stringAttribute(node, kAXTitleAttribute) ?? ""
        if title.lowercased() == "yomado" {
            result.append(["title": title, "role": stringAttribute(node, kAXRoleAttribute) ?? "unknown"])
        }
        if depth < 5 { pending += elements(node, kAXChildrenAttribute).map { ($0, depth + 1) } }
    }
    return result
}

func applicationRecord(_ app: NSRunningApplication, includeTree: Bool) -> [String: Any] {
    let pid = app.processIdentifier
    var result: [String: Any] = ["pid": pid, "bundleIdentifier": app.bundleIdentifier ?? "unknown",
        "active": app.isActive, "hidden": app.isHidden, "terminated": app.isTerminated,
        "activationPolicy": app.activationPolicy.rawValue]
    let windowInfo = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
    result["cgWindows"] = windowInfo.filter { ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid }.map { info in
        var filtered: [String: Any] = [:]
        for key in [kCGWindowNumber, kCGWindowName, kCGWindowBounds, kCGWindowLayer, kCGWindowIsOnscreen, kCGWindowAlpha] {
            if let value = info[key as String] { filtered[key as String] = value }
        }
        return filtered
    }
    if includeTree {
        var budget = 500
        let element = AXUIElementCreateApplication(pid)
        result["axWindows"] = elements(element, kAXWindowsAttribute).map { tree($0, depth: 6, budget: &budget) }
    }
    return result
}

func writeJSON(_ object: Any) {
    do {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        print(String(data: data, encoding: .utf8)!)
        fflush(stdout)
    } catch { fputs("JSON serialization failed\n", stderr); exit(1) }
}

let args = Array(CommandLine.arguments.dropFirst())
if args.first == "system-ui" {
    // Only the fresh runner's system UI relevant to enabling Stage Manager or
    // inspecting Mission Control. This is not a dump of arbitrary app content.
    var result: [[String: Any]] = []
    for bundleID in ["com.apple.controlcenter", "com.apple.dock", "com.apple.systempreferences"] {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { continue }
        var budget = 1600
        result.append(["bundleIdentifier": bundleID,
            "tree": tree(AXUIElementCreateApplication(app.processIdentifier), depth: 12, budget: &budget)])
    }
    writeJSON(["axTrusted": AXIsProcessTrusted(), "systemUI": result])
} else if args.first == "pid", args.count == 2 {
    guard ownedBundleIDs.contains(args[1]),
          let app = NSRunningApplication.runningApplications(withBundleIdentifier: args[1]).first else { exit(1) }
    print(app.processIdentifier)
} else if args.first == "timeline" {
    let duration = min(60, max(1, Double(args.dropFirst().first ?? "15") ?? 15))
    let start = Date()
    while Date().timeIntervalSince(start) < duration {
        let yomado = NSRunningApplication.runningApplications(withBundleIdentifier: ownedBundleIDs[0]).first
        writeJSON(["elapsedSeconds": Date().timeIntervalSince(start), "axTrusted": AXIsProcessTrusted(),
                   "yomadoDockItems": dockYomadoItems(),
                   "yomadoActivationPolicy": yomado?.activationPolicy.rawValue ?? -1])
        Thread.sleep(forTimeInterval: 0.1)
    }
} else {
    let applications = ownedBundleIDs.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0) }
    writeJSON(["timestamp": ISO8601DateFormatter().string(from: Date()),
               "axTrusted": AXIsProcessTrusted(), "screenCapturePreflight": CGPreflightScreenCaptureAccess(),
               "screensHaveSeparateSpaces": NSScreen.screensHaveSeparateSpaces,
               "stageManagerPreference": UserDefaults(suiteName: "com.apple.WindowManager")?.object(forKey: "GloballyEnabled") ?? "unset",
               "applications": applications.map { applicationRecord($0, includeTree: true) },
               "yomadoDockItems": dockYomadoItems(),
               "groupingVerdict": "requires screenshot review; preferences and window flags are not a pass"])
}
