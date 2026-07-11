import AppKit
import SwiftUI

@MainActor
final class PreferencesHostingController<Content: View>: NSHostingController<Content> {
    override func viewDidLayout() {
        super.viewDidLayout()
        let targetSize = self.view.fittingSize
        if self.preferredContentSize != targetSize {
            self.preferredContentSize = targetSize
        }
        
        if let window = self.view.window {
            let currentSize = window.contentRect(forFrameRect: window.frame).size
            if abs(currentSize.height - targetSize.height) > 1.0 || abs(currentSize.width - targetSize.width) > 1.0 {
                DispatchQueue.main.async {
                    guard let window = self.view.window else { return }
                    let currentSize = window.contentRect(forFrameRect: window.frame).size
                    let latestTarget = self.view.fittingSize
                    if abs(currentSize.height - latestTarget.height) > 1.0 || abs(currentSize.width - latestTarget.width) > 1.0 {
                        var frame = window.frame
                        let newContentRect = NSRect(origin: window.frame.origin, size: latestTarget)
                        let newFrame = window.frameRect(forContentRect: newContentRect)
                        let deltaY = frame.size.height - newFrame.size.height
                        frame.origin.y += deltaY
                        frame.size = newFrame.size
                        window.setFrame(frame, display: true, animate: false)
                    }
                }
            }
        }
    }
}

@MainActor
final class PreferencesWindowController: NSObject, NSWindowDelegate {
    static let shared = PreferencesWindowController()
    
    private var window: NSWindow?
    
    func show() {
        // SoundShade is an accessory (.accessory activation policy) app — that
        // policy makes NSApp.activate(ignoringOtherApps:) unreliable for
        // bringing a window forward (the classic "works every other click"
        // symptom). Temporarily switching to .regular while the window is open
        // makes WindowServer treat us like a normal app for focus purposes,
        // which is the standard fix menu-bar-only apps use for this.
        NSApp.setActivationPolicy(.regular)

        DispatchQueue.main.async { [weak self] in
            self?.presentWindow()
        }
    }

    private func presentWindow() {
        NSApp.activate(ignoringOtherApps: true)

        if let window = window {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let view = PreferencesView()
            .environmentObject(AudioEngine.shared)
            .environmentObject(BrightnessEngine.shared)

        let controller = PreferencesHostingController(rootView: view)

        let w = NSWindow(
            contentRect: NSRect(origin: .zero, size: controller.view.fittingSize),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        w.delegate = self
        w.title = "SoundShade"
        w.contentViewController = controller
        w.center()
        w.isReleasedWhenClosed = false

        self.window = w

        w.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        // Revert to accessory (no Dock icon) now that the window is gone.
        NSApp.setActivationPolicy(.accessory)
    }
}
