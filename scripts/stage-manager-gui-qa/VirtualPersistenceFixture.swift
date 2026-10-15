import AppKit

guard ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true",
      ProcessInfo.processInfo.environment["RUNNER_ENVIRONMENT"] == "github-hosted",
      let directory = ProcessInfo.processInfo.environment["YM_QA_PERSISTENCE_DIRECTORY"] else {
    fputs("REFUSED: disposable hosted runner and fixture directory required\n", stderr); exit(64)
}

final class CounterView: NSView {
    var counter = 0
    override func draw(_ dirtyRect: NSRect) {
        let hue = CGFloat(counter % 31) / 31.0
        NSColor(calibratedHue: hue, saturation: 0.8, brightness: 0.72, alpha: 1).setFill()
        bounds.fill()
        let text = "YOMADO QA PERSISTENCE\nFRAME \(counter)"
        let style = NSMutableParagraphStyle(); style.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 28, weight: .bold),
            .foregroundColor: NSColor.white, .paragraphStyle: style
        ]
        (text as NSString).draw(in: bounds.insetBy(dx: 20, dy: 65), withAttributes: attributes)
    }
}

final class FixtureDelegate: NSObject, NSApplicationDelegate {
    let directory: String
    init(directory: String) { self.directory = directory; super.init() }
    var window: NSWindow!
    var view: CounterView!
    var timer: Timer?
    var lastNonce = ""
    let started = ProcessInfo.processInfo.systemUptime
    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 140, y: 120, width: 480, height: 300),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "YOMADO QA PERSISTENCE"
        window.isReleasedWhenClosed = false
        // This test fixture remains visible while the product panel changes
        // activation policy. Space/full-screen navigation is tested separately.
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        view = CounterView(frame: NSRect(x: 0, y: 0, width: 480, height: 300))
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
        tick()
    }
    func tick() {
        if ProcessInfo.processInfo.systemUptime - started > 240 { NSApp.terminate(nil); return }
        let control = URL(fileURLWithPath: directory).appendingPathComponent("command.json")
        if let data = try? Data(contentsOf: control),
           let command = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let nonce = command["nonce"] as? String, nonce != lastNonce {
            lastNonce = nonce
            if command["command"] as? String == "place-on-existing-display",
               let requestedID = (command["displayID"] as? NSNumber)?.uint32Value,
               let screen = NSScreen.screens.first(where: {
                   ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == requestedID
               }) {
                let frame = NSRect(x: screen.visibleFrame.minX + 100,
                                   y: screen.visibleFrame.minY + 100, width: 480, height: 328)
                window.setFrame(frame, display: true)
                window.orderFront(nil)
            } else if command["command"] as? String == "quit" {
                NSApp.terminate(nil); return
            }
        }
        view.counter += 1
        view.needsDisplay = true; view.displayIfNeeded()
        let frame = window.frame
        let record: [String: Any] = [
            "pid": ProcessInfo.processInfo.processIdentifier,
            "windowID": window.windowNumber,
            "counter": view.counter,
            "uptime": ProcessInfo.processInfo.systemUptime,
            "frameAppKit": [frame.minX, frame.minY, frame.width, frame.height],
            "visible": window.isVisible,
            "placementNonce": lastNonce,
            "fixtureCollectionBehavior": "canJoinAllSpaces,fullScreenAuxiliary"
        ]
        if let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("fixture-state.json"), options: .atomic)
        }
    }
}

let application = NSApplication.shared
application.setActivationPolicy(.regular)
let delegate = FixtureDelegate(directory: directory)
application.delegate = delegate
application.run()
