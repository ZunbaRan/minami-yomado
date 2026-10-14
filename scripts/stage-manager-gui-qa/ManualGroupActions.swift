import AppKit
import ApplicationServices

guard ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true",
      ProcessInfo.processInfo.environment["RUNNER_ENVIRONMENT"] == "github-hosted" else { exit(64) }
func fail(_ reason: String) -> Never { fputs("Manual grouping refused: \(reason)\n", stderr); exit(78) }
func output(_ value: [String: Any]) {
    let data = try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    print(String(data: data, encoding: .utf8)!); fflush(stdout)
}
func rect(_ window: [String: Any]) -> CGRect? {
    guard let b = window[kCGWindowBounds as String] as? [String: NSNumber],
          let x = b["X"]?.doubleValue, let y = b["Y"]?.doubleValue,
          let w = b["Width"]?.doubleValue, let h = b["Height"]?.doubleValue,
          x.isFinite, y.isFinite, w.isFinite, h.isFinite, w > 0, h > 0 else { return nil }
    return CGRect(x: x, y: y, width: w, height: h)
}
func describe(_ app: NSRunningApplication?, title: String, windows: [[String: Any]]) -> [String: Any] {
    guard let app else { return ["running": false] }
    let owned = windows.filter {
        ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == app.processIdentifier
            && $0[kCGWindowName as String] as? String == title
            && ($0[kCGWindowLayer as String] as? NSNumber)?.intValue == 0
    }.map { item -> [String: Any] in
        var result: [String: Any] = [:]
        for key in [kCGWindowNumber, kCGWindowName, kCGWindowBounds, kCGWindowIsOnscreen, kCGWindowLayer] {
            if let value = item[key as String] { result[key as String] = value }
        }
        return result
    }
    return ["running": true, "pid": app.processIdentifier, "active": app.isActive,
            "activationPolicy": app.activationPolicy.rawValue, "windows": owned]
}
let windows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
let product = NSRunningApplication.runningApplications(withBundleIdentifier: "dev.chekusu.yomado").first
let companion = NSRunningApplication.runningApplications(withBundleIdentifier: "org.yomado.qa.Companion").first
let y = describe(product, title: "yomado", windows: windows)
let c = describe(companion, title: "YOMADO QA COMPANION", windows: windows)
let yw = (y["windows"] as? [[String: Any]] ?? []).filter { ($0[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue == true }
let cw = (c["windows"] as? [[String: Any]] ?? []).filter { ($0[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue == true }
let display = CGDisplayBounds(CGMainDisplayID())
let productFrame = yw.count == 1 ? rect(yw[0]) : nil
let companionFrame = cw.count == 1 ? rect(cw[0]) : nil
var ready = false
if let p = productFrame, let c = companionFrame {
    // Real preceding captures showed the regular app's original CGWindow
    // transformed into a left-rail 72x97 thumbnail at (15,351). Revalidate the
    // current identity and shape; never reuse that old absolute point.
    ready = AXIsProcessTrusted() && product?.isActive == true
        && p.width >= 600 && p.height >= 300 && display.contains(p)
        && c.width >= 40 && c.width <= 120 && c.height >= 50 && c.height <= 160
        && c.minX >= display.minX && c.maxX <= display.minX + 150 && display.contains(c)
}
output(["product": y, "companion": c, "thumbnailDragPreconditionsMet": ready,
        "monotonicUptimeSeconds": ProcessInfo.processInfo.systemUptime,
        "groupVerdict": "requires before/after screenshots and subsequent group-switch evidence"])
guard CommandLine.arguments.last == "drag-companion-into-yomado" else { exit(0) }
guard ready, let p = productFrame, let c = companionFrame else {
    fail("expected active central Yomado and uniquely identified left-rail Companion thumbnail; discovery evidence recorded")
}
let from = CGPoint(x: c.midX, y: c.midY)
let to = CGPoint(x: p.midX, y: p.midY)
func event(_ type: CGEventType, _ point: CGPoint) -> CGEvent {
    guard let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else {
        fail("mouse event allocation failed")
    }
    return e
}
// Construct before pressing so an allocation failure cannot leave a held mouse.
let move = event(.mouseMoved, from), down = event(.leftMouseDown, from), up = event(.leftMouseUp, to)
let drag = (1...24).map { index -> CGEvent in
    let t = CGFloat(index) / 24
    return event(.leftMouseDragged, CGPoint(x: from.x + (to.x-from.x)*t, y: from.y + (to.y-from.y)*t))
}
move.post(tap: .cghidEventTap); Thread.sleep(forTimeInterval: 0.3)
down.post(tap: .cghidEventTap); Thread.sleep(forTimeInterval: 0.2)
for e in drag { e.post(tap: .cghidEventTap); Thread.sleep(forTimeInterval: 0.04) }
Thread.sleep(forTimeInterval: 0.3); up.post(tap: .cghidEventTap)
output(["action": "observed-Companion-thumbnail-dragged-into-current-Yomado-stage",
        "from": [from.x, from.y], "to": [to.x, to.y],
        "actionResult": "mouse-posted-grouping-must-be-visually-verified",
        "monotonicUptimeSeconds": ProcessInfo.processInfo.systemUptime])
