import AppKit

// A separate, regular app provides a recognizable Stage Manager/full-screen
// fixture. No production app or user document is modified by this helper.
let environment = ProcessInfo.processInfo.environment
guard environment["GITHUB_ACTIONS"] == "true",
      environment["RUNNER_ENVIRONMENT"] == "github-hosted",
      let controlDirectory = environment["YM_QA_CONTROL_DIRECTORY"] else {
    fputs("REFUSED: disposable hosted runner only\n", stderr)
    exit(64)
}

final class CompanionDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let controlDirectory: String
    init(controlDirectory: String) {
        self.controlDirectory = controlDirectory
        super.init()
    }
    var window: NSWindow!
    var timer: Timer?
    var lastCommand = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        let reference = Bundle.main.bundleIdentifier == "org.yomado.qa.Reference"
        window = NSWindow(contentRect: NSRect(x: 160, y: 180, width: 640, height: 440),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = reference ? "YOMADO QA REFERENCE" : "YOMADO QA COMPANION"
        window.collectionBehavior = [.primary, .fullScreenPrimary]
        window.backgroundColor = reference
            ? NSColor(calibratedRed: 0.06, green: 0.18, blue: 0.48, alpha: 1)
            : NSColor(calibratedRed: 0.42, green: 0.08, blue: 0.13, alpha: 1)
        window.delegate = self
        window.isReleasedWhenClosed = false
        let title = NSTextField(labelWithString: "\(reference ? "REFERENCE" : "COMPANION")\nSeparate regular application\nStage Manager fixture")
        title.font = NSFont.systemFont(ofSize: 30, weight: .semibold)
        title.textColor = .white
        title.alignment = .center
        title.maximumNumberOfLines = 3
        title.frame = NSRect(x: 20, y: 100, width: 600, height: 220)
        title.autoresizingMask = [.width, .height]
        window.contentView?.addSubview(title)
        show()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.readCommand()
        }
        record("launched")
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func record(_ event: String) {
        let object: [String: Any] = ["event": event,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "windowNumber": window.windowNumber,
            "bundleIdentifier": Bundle.main.bundleIdentifier ?? "unknown",
            "appActive": NSApp.isActive,
            "screensHaveSeparateSpaces": NSScreen.screensHaveSeparateSpaces,
            "visible": window.isVisible,
            "fullScreen": window.styleMask.contains(.fullScreen),
            "frame": NSStringFromRect(window.frame)]
        if let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
           let line = String(data: data, encoding: .utf8) {
            print(line)
            fflush(stdout)
        }
    }

    func readCommand() {
        let url = URL(fileURLWithPath: controlDirectory).appendingPathComponent("command.json")
        guard let data = try? Data(contentsOf: url),
              let value = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let nonce = value["nonce"], nonce != lastCommand,
              let command = value["command"] else { return }
        lastCommand = nonce
        switch command {
        case "show": show()
        case "enter-full-screen":
            show()
            if !window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }
        case "exit-full-screen":
            if window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }
        case "quit": NSApp.terminate(nil)
        default: record("unknown-command"); return
        }
        record(command)
    }

    func windowDidEnterFullScreen(_ notification: Notification) { record("did-enter-full-screen") }
    func windowDidExitFullScreen(_ notification: Notification) { record("did-exit-full-screen") }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
let delegate = CompanionDelegate(controlDirectory: controlDirectory)
app.setActivationPolicy(.regular)
app.delegate = delegate
app.run()
