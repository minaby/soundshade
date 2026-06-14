import AppKit

// MARK: - App Delegate
// Note: @MainActor is NOT on the class — NSApplicationDelegate callbacks
// are already invoked on the main thread by AppKit. Marking individual
// methods @MainActor is sufficient and avoids Swift 6 init isolation errors.

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate?
    private var menuBarController: MenuBarController?

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("SoundShade Debug: applicationDidFinishLaunching called")
        NSApp.setActivationPolicy(.accessory)
        ProcessInfo.processInfo.disableAutomaticTermination("Keep menu bar app running without windows")
        menuBarController = MenuBarController()
    }

    @objc func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        NSLog("SoundShade Debug: applicationShouldTerminateAfterLastWindowClosed called")
        return false
    }
}

// MARK: - Entry Point
let delegate = AppDelegate()
AppDelegate.shared = delegate
let app = NSApplication.shared
app.delegate = delegate
app.run()
