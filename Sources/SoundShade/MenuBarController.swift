import AppKit
import SwiftUI

// MARK: - Menu Bar Controller
// Uses NSPanel + NSVisualEffectView instead of NSPopover to avoid the
// popover arrow overlapping the status bar icon.

@MainActor
final class MenuBarController {

    private var statusItem: NSStatusItem?
    private var panel: NSPanel?
    private var eventMonitor: Any?

    private let audio = AudioEngine.shared
    private let brightness = BrightnessEngine.shared

    init() {
        setupStatusItem()
    }

    // MARK: - Setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let button = statusItem?.button else { return }
        
        if let url = Bundle.appResources.url(forResource: "StatusIcon", withExtension: "svg"),
           let image = NSImage(contentsOf: url) {
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = true   // template => auto black/white per menu bar appearance
            button.image = image
        } else {
            button.image = NSImage(systemSymbolName: "speaker.wave.2.fill",
                                   accessibilityDescription: "SoundShade")
            button.image?.isTemplate = true
        }
        
        button.action = #selector(togglePanel)
        button.target = self
    }

    // MARK: - Panel

    private func makePanel() -> NSPanel {
        let panelView = SoundShadePanel()
            .environmentObject(audio)
            .environmentObject(brightness)

        let hosting = NSHostingView(rootView: panelView)
        hosting.translatesAutoresizingMaskIntoConstraints = false

        // Visual effect background — same material as system menus
        let effectView = NSVisualEffectView()
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.material = .popover
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 10
        effectView.layer?.masksToBounds = true

        effectView.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: effectView.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: effectView.bottomAnchor),
        ])

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 290, height: 100),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        p.contentView = effectView
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .popUpMenu
        p.collectionBehavior = [.transient, .ignoresCycle, .moveToActiveSpace]
        p.animationBehavior = .utilityWindow

        return p
    }

    // MARK: - Toggle

    @objc private func togglePanel() {
        if let p = panel, p.isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        if panel == nil { panel = makePanel() }
        guard let p = panel,
              let button = statusItem?.button,
              let buttonWindow = button.window else { return }

        // Refresh data on open
        audio.refresh()
        brightness.refresh()

        // Size the panel to fit content
        p.contentView?.layoutSubtreeIfNeeded()
        let fittingSize = p.contentView?.fittingSize ?? NSSize(width: 290, height: 400)
        let panelWidth = max(290, fittingSize.width)
        let panelHeight = max(100, fittingSize.height)

        // Position: flush below the menu bar, horizontally centered on icon
        let buttonRect = button.convert(button.bounds, to: nil)
        let screenRect = buttonWindow.convertToScreen(buttonRect)

        // Keep within screen bounds
        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        var x = screenRect.midX - panelWidth / 2
        x = max(screenFrame.minX + 4, min(x, screenFrame.maxX - panelWidth - 4))

        let y = screenRect.minY  // top-left origin = bottom of menu bar item

        p.setFrame(NSRect(x: x, y: y - panelHeight, width: panelWidth, height: panelHeight),
                   display: false)
        p.makeKeyAndOrderFront(nil)

        // Dismiss on click outside
        eventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            self?.hidePanel()
        }
    }

    private func hidePanel() {
        panel?.orderOut(nil)
        if let m = eventMonitor {
            NSEvent.removeMonitor(m)
            eventMonitor = nil
        }
    }
}
