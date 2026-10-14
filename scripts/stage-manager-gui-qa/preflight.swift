import AppKit
import ApplicationServices
import Metal

// Run only in the disposable GitHub-hosted test machine, never on a developer desktop.
guard ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true",
      ProcessInfo.processInfo.environment["RUNNER_ENVIRONMENT"] == "github-hosted" else {
    fatalError("This probe requires a disposable GitHub-hosted runner")
}
let session = CGSessionCopyCurrentDictionary() as? [String: Any] ?? [:]
let state: [String: Any] = [
    "osVersion": ProcessInfo.processInfo.operatingSystemVersionString,
    "onConsole": session["kCGSessionOnConsoleKey"] ?? false,
    "loginDone": session["kCGSessionLoginDoneKey"] ?? false,
    "screenLocked": session["CGSSessionScreenIsLocked"] ?? false,
    "screenCount": NSScreen.screens.count,
    "separateSpaces": NSScreen.screensHaveSeparateSpaces,
    "screens": NSScreen.screens.map { ["width": $0.frame.width, "height": $0.frame.height, "scale": $0.backingScaleFactor] },
    "accessibilityTrusted": AXIsProcessTrusted(),
    "captureAuthorized": CGPreflightScreenCaptureAccess(),
    "metalDevices": MTLCopyAllDevices().map { $0.name },
    "stageManagerPreference": UserDefaults(suiteName: "com.apple.WindowManager")?.object(forKey: "GloballyEnabled") ?? "unset",
    "dockRunning": !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").isEmpty
]
let data = try JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys])
print(String(decoding: data, as: UTF8.self))
