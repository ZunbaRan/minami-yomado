import AppKit
import ApplicationServices
import ScreenCaptureKit
import ImageIO
import UniformTypeIdentifiers
import CryptoKit

guard ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true",
      ProcessInfo.processInfo.environment["RUNNER_ENVIRONMENT"] == "github-hosted" else {
    fputs("REFUSED: disposable hosted runner only\n", stderr); exit(64)
}
func fail(_ reason: String) -> Never { fputs("Persistence QA: \(reason)\n", stderr); exit(1) }
func emit(_ value: Any) {
    guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
          let text = String(data: data, encoding: .utf8) else { fail("invalid JSON evidence") }
    print(text)
}
func rect(_ frame: CGRect) -> [Double] { [frame.minX, frame.minY, frame.width, frame.height] }
func inventory() -> [[String: Any]] {
    var IDs = [CGDirectDisplayID](repeating: 0, count: 128), count: UInt32 = 0
    guard CGGetOnlineDisplayList(128, &IDs, &count) == .success, count < 128 else { fail("display inventory unavailable") }
    return IDs.prefix(Int(count)).sorted().map { id in
        var row: [String: Any] = ["id": id, "main": CGDisplayIsMain(id) != 0,
            "active": CGDisplayIsActive(id) != 0, "bounds": rect(CGDisplayBounds(id)),
            "rotation": CGDisplayRotation(id), "mirrors": CGDisplayMirrorsDisplay(id),
            "inMirrorSet": CGDisplayIsInMirrorSet(id) != 0,
            "vendor": CGDisplayVendorNumber(id), "model": CGDisplayModelNumber(id),
            "serial": CGDisplaySerialNumber(id)]
        if let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() {
            row["uuid"] = CFUUIDCreateString(nil, uuid) as String
        }
        if let mode = CGDisplayCopyDisplayMode(id) {
            row["mode"] = ["width": mode.width, "height": mode.height,
                "pixelWidth": mode.pixelWidth, "pixelHeight": mode.pixelHeight,
                "refresh": mode.refreshRate, "flags": mode.ioFlags,
                "desktopUsable": mode.isUsableForDesktopGUI()] as [String: Any]
        }
        return row
    }
}
func attr(_ node: AXUIElement, _ key: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(node, key as CFString, &value) == .success ? value : nil
}
func label(_ node: AXUIElement, _ key: String) -> String { attr(node, key) as? String ?? "" }
func nodes(_ root: AXUIElement) -> [AXUIElement] {
    var pending = [(root, 0)], found: [AXUIElement] = []
    while let (node, depth) = pending.popLast() {
        if found.contains(where: { CFEqual($0, node) }) { continue }
        guard found.count < 1500, depth < 18 else { fail("AX traversal bound exceeded") }
        found.append(node)
        for key in [kAXChildrenAttribute, kAXWindowsAttribute, "AXSheets"] {
            pending += (attr(node, key) as? [AXUIElement] ?? []).map { ($0, depth + 1) }
        }
    }
    return found
}
func axBounds(_ node: AXUIElement) -> CGRect? {
    guard let p = attr(node, kAXPositionAttribute), let s = attr(node, kAXSizeAttribute),
          CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
    var position = CGPoint.zero, size = CGSize.zero
    guard AXValueGetValue(p as! AXValue, .cgPoint, &position),
          AXValueGetValue(s as! AXValue, .cgSize, &size), size.width > 0, size.height > 0 else { return nil }
    return CGRect(origin: position, size: size)
}
func ancestors(_ node: AXUIElement) -> [AXUIElement] {
    var current = node, result: [AXUIElement] = []
    for _ in 0..<24 {
        guard let value = attr(current, kAXParentAttribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return result }
        let parent = value as! AXUIElement
        guard !CFEqual(parent, node), !result.contains(where: { CFEqual($0, parent) }) else { fail("AX parent cycle") }
        result.append(parent)
        if label(parent, kAXRoleAttribute) == kAXApplicationRole { return result }
        current = parent
    }
    fail("AX parent traversal bound exceeded")
}
func clippingEvidence(_ node: AXUIElement) -> [[String: Any]] {
    var result: [[String: Any]] = []
    for ancestor in ancestors(node) {
        let role = label(ancestor, kAXRoleAttribute)
        if [kAXScrollAreaRole, kAXWindowRole, kAXMenuRole].contains(role) {
            result.append(["role": role, "bounds": axBounds(ancestor).map(rect) ?? []])
        }
        // Native popup menus are separate surfaces. Their owner window and
        // its scroll views are not clipping ancestors of the popup surface.
        if role == kAXMenuRole { break }
    }
    return result
}
func isWithinOnlineDisplay(_ frame: CGRect) -> Bool {
    var displays = [CGDirectDisplayID](repeating: 0, count: 128), count: UInt32 = 0
    guard CGGetOnlineDisplayList(128, &displays, &count) == .success, count < 128 else { return false }
    return displays.prefix(Int(count)).contains { CGDisplayIsActive($0) != 0 && CGDisplayBounds($0).contains(frame) }
}
func fullyVisible(_ node: AXUIElement) -> Bool {
    guard let frame = axBounds(node), isWithinOnlineDisplay(frame),
          (attr(node, "AXHidden") as? NSNumber)?.boolValue != true else { return false }
    for ancestor in ancestors(node) {
        if (attr(ancestor, "AXHidden") as? NSNumber)?.boolValue == true { return false }
        let role = label(ancestor, kAXRoleAttribute)
        if role == kAXMenuRole {
            // Validate the live popup's own viewport, then stop before its
            // owning NSWindow. A menu may legitimately extend past that window.
            guard let menuFrame = axBounds(ancestor), menuFrame.contains(frame) else { return false }
            return true
        }
        if role == kAXWindowRole && (attr(ancestor, kAXMinimizedAttribute) as? NSNumber)?.boolValue == true { return false }
        if role == kAXScrollAreaRole || role == kAXWindowRole {
            guard let clip = axBounds(ancestor), clip.contains(frame) else { return false }
        }
    }
    return true
}
func ownedApp(_ pid: pid_t, _ bundle: String) -> NSRunningApplication {
    guard let app = NSRunningApplication(processIdentifier: pid), app.bundleIdentifier == bundle, !app.isTerminated else {
        fail("owned process identity unavailable")
    }
    return app
}
func windows(_ pid: pid_t) -> [[String: Any]] {
    (CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []).filter {
        ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid
            && ($0[kCGWindowLayer as String] as? NSNumber)?.intValue == 0
    }.compactMap { row in
        guard let value = row[kCGWindowBounds as String] as? [String: Any],
              let frame = CGRect(dictionaryRepresentation: value as CFDictionary) else { return nil }
        return ["id": row[kCGWindowNumber as String] ?? 0, "bounds": rect(frame),
                "onscreen": row[kCGWindowIsOnscreen as String] ?? false,
                "title": row[kCGWindowName as String] ?? ""]
    }
}
func select(_ root: AXUIElement, _ command: String, requireVisible: Bool = true) -> AXUIElement? {
    let matches = nodes(root).filter { node in
        let role = label(node, kAXRoleAttribute), title = label(node, kAXTitleAttribute)
        let descriptions = [title, label(node, kAXDescriptionAttribute), label(node, kAXHelpAttribute)]
        guard (attr(node, kAXEnabledAttribute) as? NSNumber)?.boolValue == true,
              axBounds(node) != nil, !requireVisible || fullyVisible(node) else { return false }
        switch command {
        case "add-menu": return role == kAXButtonRole && descriptions.contains(where: {
            $0 == "添加虚拟屏" || $0 == "添加或启动虚拟屏"
        })
        case "new-display": return role == kAXMenuItemRole && title == "新增虚拟屏"
        case "manage-menu": return role == kAXButtonRole && descriptions.contains(where: { $0.hasPrefix("管理 虚拟屏 ") })
        case "rename": return role == kAXMenuItemRole && title == "重命名…"
        case "cancel-rename": return role == kAXButtonRole && title == "取消"
        default: return false
        }
    }
    guard matches.count <= 1 else { fail("ambiguous owned app control for \(command)") }
    return matches.first
}
func action(_ pid: pid_t, _ command: String) {
    _ = ownedApp(pid, "dev.chekusu.yomado")
    guard AXIsProcessTrusted() else { fail("Accessibility permission unavailable") }
    let root = AXUIElementCreateApplication(pid)
    var adjustments: [[String: Any]] = []
    if command == "manage-menu", let clipped = select(root, command, requireVisible: false), !fullyVisible(clipped) {
        // A small hosted desktop can clip the card's bottom toolbar behind
        // the panel footer. Enlarge only this owned, ordinary product panel;
        // never click coordinates that are outside an ancestor's viewport.
        guard let panel = ancestors(clipped).first(where: { label($0, kAXRoleAttribute) == kAXWindowRole }),
              label(panel, kAXTitleAttribute) == "yomado", let oldFrame = axBounds(panel),
              CGDisplayBounds(CGMainDisplayID()).contains(oldFrame) else { fail("clipped control has no safely resizable owned panel") }
        var owner: pid_t = 0, settable = DarwinBoolean(false)
        guard AXUIElementGetPid(panel, &owner) == .success, owner == pid,
              AXUIElementIsAttributeSettable(panel, kAXSizeAttribute as CFString, &settable) == .success,
              settable.boolValue else { fail("owned panel size is not settable") }
        let availableHeight = CGDisplayBounds(CGMainDisplayID()).maxY - oldFrame.minY - 16
        var requested = CGSize(width: oldFrame.width, height: min(oldFrame.height + 160, availableHeight))
        guard requested.height > oldFrame.height + 1, let size = AXValueCreate(.cgSize, &requested) else {
            fail("insufficient on-screen space to reveal card control")
        }
        let before = clippingEvidence(clipped)
        let beforeControl = axBounds(clipped).map(rect) ?? []
        let outcome = AXUIElementSetAttributeValue(panel, kAXSizeAttribute as CFString, size)
        adjustments.append(["kind": "resize-owned-product-panel", "oldBounds": rect(oldFrame),
                            "requestedSize": [requested.width, requested.height],
                            "beforeControlBounds": beforeControl, "beforeAncestorClips": before,
                            "AXResult": outcome.rawValue])
        guard outcome == .success else { emit(["adjustments": adjustments]); fail("owned panel resize was refused") }
    }
    var selected: AXUIElement?
    for _ in 0..<45 {
        selected = select(root, command)
        if selected != nil { break }
        Thread.sleep(forTimeInterval: 0.1)
    }
    guard selected != nil, let current = select(root, command), let frame = axBounds(current) else {
        emit(["unavailableCommand": command, "ax": nodes(root).map {
            ["role": label($0, kAXRoleAttribute), "title": label($0, kAXTitleAttribute),
             "description": label($0, kAXDescriptionAttribute), "bounds": axBounds($0).map(rect) ?? [],
             "ancestorClips": clippingEvidence($0)] as [String: Any]
        }, "adjustments": adjustments]); fail("expected visible control not found")
    }
    let point = CGPoint(x: frame.midX, y: frame.midY)
    for type in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
        guard let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else {
            fail("unable to construct bounded mouse event")
        }
        event.setIntegerValueField(.mouseEventClickState, value: 1)
        event.post(tap: .cghidEventTap); Thread.sleep(forTimeInterval: 0.1)
    }
    emit(["command": command, "pid": pid, "point": [point.x, point.y],
          "controlBounds": rect(frame), "ancestorClips": clippingEvidence(current),
          "adjustments": adjustments, "result": "sent; result requires observation"])
}
func waitFor<T>(_ operation: (@escaping (T?, Error?) -> Void) -> Void) -> T {
    var done = false, result: T?, error: Error?
    operation { value, failure in result = value; error = failure; done = true }
    let deadline = Date().addingTimeInterval(12)
    while !done && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
    guard done, let result else { fail("capture unavailable: \(error?.localizedDescription ?? "timeout")") }
    return result
}
func sample(_ pid: pid_t, _ fixturePID: pid_t, _ displayID: CGDirectDisplayID, _ statePath: String, _ imagePath: String?) {
    let product = ownedApp(pid, "dev.chekusu.yomado")
    _ = ownedApp(fixturePID, "org.yomado.qa.VirtualPersistence")
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: statePath)),
          let state = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          (state["pid"] as? NSNumber)?.int32Value == fixturePID,
          let windowID = (state["windowID"] as? NSNumber)?.uint32Value,
          let window = windows(fixturePID).first(where: { ($0["id"] as? NSNumber)?.uint32Value == windowID }) else {
        fail("fixture state does not match a live owned window")
    }
    var result: [String: Any] = ["uptime": ProcessInfo.processInfo.systemUptime,
        "productPID": pid, "activationPolicy": product.activationPolicy.rawValue,
        "productWindows": windows(pid), "fixturePID": fixturePID,
        "fixtureWindow": window, "fixtureState": state, "displays": inventory()]
    if let imagePath {
        guard CGPreflightScreenCaptureAccess() else { fail("screen capture unavailable") }
        let content: SCShareableContent = waitFor { SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true, completionHandler: $0) }
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else { fail("target not present in actual capture inventory") }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = display.width; config.height = display.height; config.showsCursor = false
        let image: CGImage = waitFor { SCScreenshotManager.captureImage(contentFilter: filter, configuration: config, completionHandler: $0) }
        guard let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: imagePath) as CFURL, UTType.png.identifier as CFString, 1, nil) else { fail("PNG destination unavailable") }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination), let box = window["bounds"] as? [Double], box.count == 4 else { fail("capture could not be saved") }
        let windowBounds = CGRect(x: box[0], y: box[1], width: box[2], height: box[3])
        let displayBounds = CGDisplayBounds(displayID)
        guard displayBounds.contains(windowBounds), (window["onscreen"] as? NSNumber)?.boolValue == true else { fail("fixture not visibly inside product-created display") }
        let scaleX = CGFloat(image.width) / displayBounds.width, scaleY = CGFloat(image.height) / displayBounds.height
        let cropRect = CGRect(x: (windowBounds.minX - displayBounds.minX + 30) * scaleX,
                              y: (windowBounds.minY - displayBounds.minY + 70) * scaleY,
                              width: (windowBounds.width - 60) * scaleX,
                              height: (windowBounds.height - 120) * scaleY).integral
        guard let crop = image.cropping(to: cropRect), let provider = crop.dataProvider,
              let bytes = provider.data as Data? else { fail("fixture pixel crop unavailable") }
        result["image"] = ["width": image.width, "height": image.height,
            "fixtureCrop": rect(cropRect), "fixtureSHA256": SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(),
            "distinctBytes": Set(bytes).count, "path": URL(fileURLWithPath: imagePath).lastPathComponent]
    }
    emit(result)
}

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else { fail("missing command") }
switch command {
case "inventory": emit(inventory())
case "pid":
    guard args.count == 2, ["dev.chekusu.yomado", "org.yomado.qa.VirtualPersistence"].contains(args[1]) else { fail("unsupported bundle") }
    let apps = NSRunningApplication.runningApplications(withBundleIdentifier: args[1]).filter { !$0.isTerminated }
    guard apps.count == 1 else { fail("expected exactly one owned application") }; print(apps[0].processIdentifier)
case "sample":
    guard args.count == 5 || args.count == 6, let pid = Int32(args[1]), let fixturePID = Int32(args[2]),
          let displayID = UInt32(args[3]) else { fail("sample arguments invalid") }
    sample(pid, fixturePID, displayID, args[4], args.count == 6 ? args[5] : nil)
case "panel-state":
    guard args.count == 2, let pid = Int32(args[1]) else { fail("missing PID") }
    let product = ownedApp(pid, "dev.chekusu.yomado")
    emit(["activationPolicy": product.activationPolicy.rawValue, "windows": windows(pid),
          "ax": nodes(AXUIElementCreateApplication(pid)).map {
              ["role": label($0, kAXRoleAttribute), "title": label($0, kAXTitleAttribute), "description": label($0, kAXDescriptionAttribute)]
          }])
default:
    guard args.count == 2, let pid = Int32(args[1]),
          ["add-menu", "new-display", "manage-menu", "rename", "cancel-rename"].contains(command) else { fail("unsupported command") }
    action(pid, command)
}
