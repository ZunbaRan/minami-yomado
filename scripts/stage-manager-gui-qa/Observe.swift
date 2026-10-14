import AppKit
import ApplicationServices

guard ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true",
      ProcessInfo.processInfo.environment["RUNNER_ENVIRONMENT"] == "github-hosted" else {
    fputs("REFUSED: disposable hosted runner only\n", stderr)
    exit(64)
}
let ownedBundleIDs = ["dev.chekusu.yomado", "org.yomado.qa.Companion", "org.yomado.qa.Reference"]

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
    for name in [kAXRoleAttribute, kAXSubroleAttribute, kAXTitleAttribute, kAXDescriptionAttribute, "AXIdentifier"] {
        if let value = stringAttribute(element, name) { result[name] = value }
    }
    for name in [kAXFocusedAttribute, kAXMainAttribute, kAXMinimizedAttribute, "AXFullScreen", kAXEnabledAttribute, kAXValueAttribute] {
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

func dockObservation() -> [String: Any] {
    guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
        return ["dockProcessFound": false, "dockReadable": false, "walkComplete": false,
                "regularCompanionPositiveControl": false, "yomadoItems": [], "companionItems": [],
                "errors": ["dock-not-running"], "yomadoIconObservation": "unknown"]
    }
    let companion = NSRunningApplication.runningApplications(withBundleIdentifier: ownedBundleIDs[1]).first
    let yomado = NSRunningApplication.runningApplications(withBundleIdentifier: ownedBundleIDs[0]).first
    let trusted = AXIsProcessTrusted()
    var pending = [(AXUIElementCreateApplication(dock.processIdentifier), 0)]
    var yomadoItems: [[String: Any]] = []
    var companionItems: [[String: Any]] = []
    var errors: [String] = []
    var rootChildrenReadable = false
    var truncated = false
    var visited = 0
    while !pending.isEmpty {
        if visited >= 1600 { truncated = true; break }
        let (node, depth) = pending.removeLast()
        visited += 1
        var roleValue: CFTypeRef?
        let roleError = AXUIElementCopyAttributeValue(node, kAXRoleAttribute as CFString, &roleValue)
        let role = roleValue as? String ?? "unknown"
        if roleError != .success { errors.append("role-read-error-\(roleError.rawValue)-depth-\(depth)") }
        if role == "AXDockItem" {
            var titleValue: CFTypeRef?
            let titleError = AXUIElementCopyAttributeValue(node, kAXTitleAttribute as CFString, &titleValue)
            let title = titleValue as? String ?? ""
            if titleError != .success { errors.append("dock-item-title-error-\(titleError.rawValue)") }
            let dockURL = attribute(node, "AXURL") as? URL
            let matchesYomadoURL = dockURL != nil && dockURL?.standardizedFileURL == yomado?.bundleURL?.standardizedFileURL
            let matchesCompanionURL = dockURL != nil && dockURL?.standardizedFileURL == companion?.bundleURL?.standardizedFileURL
            if title.lowercased() == "yomado" || matchesYomadoURL {
                yomadoItems.append(["title": title, "role": role, "matchesRunningBundleURL": matchesYomadoURL])
            }
            let companionTitles = ["QA Companion", "Companion", companion?.localizedName ?? ""].filter { !$0.isEmpty }
            if matchesCompanionURL || companionTitles.contains(title) {
                companionItems.append(["title": title, "role": role, "matchesRunningBundleURL": matchesCompanionURL])
            }
        }
        var childrenValue: CFTypeRef?
        let childrenError = AXUIElementCopyAttributeValue(node, kAXChildrenAttribute as CFString, &childrenValue)
        if childrenError == .success {
            guard let children = childrenValue as? [AXUIElement] else {
                errors.append("invalid-children-value-depth-\(depth)"); continue
            }
            if depth == 0 { rootChildrenReadable = !children.isEmpty }
            if depth >= 12 && !children.isEmpty {
                truncated = true
            } else {
                pending += children.map { ($0, depth + 1) }
            }
        } else if depth == 0 || (childrenError != .attributeUnsupported && childrenError != .noValue) {
            errors.append("children-read-error-\(childrenError.rawValue)-depth-\(depth)")
        }
    }
    let readable = trusted && rootChildrenReadable && errors.isEmpty
    let complete = !truncated && pending.isEmpty && errors.isEmpty
    let positiveControl = companion?.activationPolicy == .regular && !companionItems.isEmpty
    let observation = !yomadoItems.isEmpty ? "present"
        : readable && complete && positiveControl ? "absent-in-readable-sample" : "unknown"
    return ["dockProcessFound": true, "dockReadable": readable, "walkComplete": complete,
            "walkTruncated": truncated, "visitedNodeCount": visited,
            "regularCompanionPositiveControl": positiveControl,
            "yomadoItems": yomadoItems, "companionItems": companionItems,
            "errors": errors, "yomadoIconObservation": observation]
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
        var menuBudget = 180
        result["axMenuBars"] = elements(element, kAXChildrenAttribute).filter {
            stringAttribute($0, kAXRoleAttribute) == kAXMenuBarRole
        }.map { tree($0, depth: 5, budget: &menuBudget) }
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
    for bundleID in ["com.apple.controlcenter", "com.apple.dock", "com.apple.systempreferences", "com.apple.WindowManager"] {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { continue }
        var budget = 1600
        let root = AXUIElementCreateApplication(app.processIdentifier)
        var windowBudget = 1600
        result.append(["bundleIdentifier": bundleID, "pid": app.processIdentifier,
            "tree": tree(root, depth: 12, budget: &budget),
            "windows": elements(root, kAXWindowsAttribute).map { tree($0, depth: 12, budget: &windowBudget) }])
    }
    let cg = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
    let windows = cg.map { entry in
        entry.filter { [kCGWindowOwnerName as String, kCGWindowOwnerPID as String, kCGWindowName as String,
            kCGWindowNumber as String, kCGWindowBounds as String, kCGWindowLayer as String].contains($0.key) }
    }
    writeJSON(["axTrusted": AXIsProcessTrusted(), "systemUI": result, "onScreenWindowOwners": windows])
} else if args.first == "pid", args.count == 2 {
    guard ownedBundleIDs.contains(args[1]),
          let app = NSRunningApplication.runningApplications(withBundleIdentifier: args[1]).first else { exit(1) }
    print(app.processIdentifier)
} else if args.first == "timeline" {
    let duration = min(240, max(1, Double(args.dropFirst().first ?? "15") ?? 15))
    let stopFile = args.count > 2 ? args[2] : nil
    let start = ProcessInfo.processInfo.systemUptime
    var previousSampleStart: Double?
    var index = 0
    var stoppedByFile = false
    while ProcessInfo.processInfo.systemUptime - start < duration {
        if let stopFile, FileManager.default.fileExists(atPath: stopFile) { stoppedByFile = true; break }
        let sampleStart = ProcessInfo.processInfo.systemUptime
        let yomado = NSRunningApplication.runningApplications(withBundleIdentifier: ownedBundleIDs[0]).first
        let dock = dockObservation()
        let sampleEnd = ProcessInfo.processInfo.systemUptime
        let actualInterval: Any = previousSampleStart.map { (sampleStart - $0) as Any } ?? NSNull()
        writeJSON(["recordType": "sample", "sampleIndex": index, "sampleStartUptimeSeconds": sampleStart,
                   "sampleEndUptimeSeconds": sampleEnd, "elapsedSeconds": sampleStart - start,
                   "actualIntervalFromPreviousSampleStartSeconds": actualInterval,
                   "requestedSleepAfterSampleSeconds": 0.1, "axTrusted": AXIsProcessTrusted(),
                   "dock": dock,
                   "yomadoActivationPolicy": yomado?.activationPolicy.rawValue ?? -1])
        previousSampleStart = sampleStart
        index += 1
        Thread.sleep(forTimeInterval: 0.1)
    }
    writeJSON(["recordType": "timeline-end", "sampleCount": index,
               "endUptimeSeconds": ProcessInfo.processInfo.systemUptime,
               "reason": stoppedByFile ? "requested-stop" : "duration-limit",
               "elapsedSeconds": ProcessInfo.processInfo.systemUptime - start])
} else {
    let applications = ownedBundleIDs.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0) }
    writeJSON(["timestamp": ISO8601DateFormatter().string(from: Date()),
               "monotonicUptimeSeconds": ProcessInfo.processInfo.systemUptime,
               "axTrusted": AXIsProcessTrusted(), "screenCapturePreflight": CGPreflightScreenCaptureAccess(),
               "screensHaveSeparateSpaces": NSScreen.screensHaveSeparateSpaces,
               "stageManagerPreference": UserDefaults(suiteName: "com.apple.WindowManager")?.object(forKey: "GloballyEnabled") ?? "unset",
               "applications": applications.map { applicationRecord($0, includeTree: true) },
               "dock": dockObservation(),
               "groupingVerdict": "requires screenshot review; preferences and window flags are not a pass"])
}
