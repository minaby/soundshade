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
    private let displayMode = DisplayModeEngine.shared

    // MARK: - Multi-monitor flyout state

    private var flyoutPanel: NSPanel?
    private var multiMonitorRowFrame: CGRect = .zero
    private var isRowHovered = false
    private var isFlyoutHovered = false
    private var pendingFlyoutHide: DispatchWorkItem?

    private var screenChangeRecreateWorkItem: DispatchWorkItem?

    init() {
        setupStatusItem()

        // Powering off / mirroring a display (DisplayModeEngine) reconfigures the
        // screen list. The scene-based status item can end up registered
        // (isVisible=1) yet not actually rendered anywhere — toggling isVisible
        // back on doesn't fix that, so fully tear down and recreate it instead.
        // Debounced because a single mirror/power change can fire this notification
        // more than once in quick succession.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleScreenParametersChanged()
            }
        }
    }

    private func handleScreenParametersChanged() {
        screenChangeRecreateWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.recreateStatusItem()
        }
        screenChangeRecreateWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }

    private func recreateStatusItem() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItem = nil
        setupStatusItem()
    }

    // MARK: - Setup

    private func setupStatusItem(attempt: Int = 0) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item

        // Persist the item's position across relaunches and keep it visible. Helps
        // it survive login-time races and menu-bar reshuffles after reboot.
        item.autosaveName = "com.soundshade.statusitem"
        item.isVisible = true
        item.behavior = []

        guard let button = item.button else {
            // The button can briefly be nil if we launch before the menu bar is
            // ready (e.g. as a login item). Retry a few times instead of giving up.
            if attempt < 10 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.setupStatusItem(attempt: attempt + 1)
                }
            }
            return
        }

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
        let panelView = SoundShadePanel(
            onMultiMonitorRowFrame: { [weak self] frame in
                self?.multiMonitorRowFrame = frame
                if self?.isRowHovered == true {
                    self?.positionFlyout()
                }
            },
            onMultiMonitorHoverChange: { [weak self] hovering in
                self?.handleRowHoverChange(hovering)
            },
            onDismissPanel: { [weak self] in
                self?.hidePanel()
            }
        )
            .environmentObject(audio)
            .environmentObject(brightness)
            .environmentObject(displayMode)

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
        displayMode.refresh(with: brightness.allDisplays)

        // Size the panel to fit content
        p.contentView?.layoutSubtreeIfNeeded()
        let fittingSize = p.contentView?.fittingSize ?? NSSize(width: 290, height: 400)
        let panelWidth = max(290, fittingSize.width)
        let panelHeight = max(100, fittingSize.height)

        // Position: flush below the menu bar, horizontally centered on icon
        let buttonRect = button.convert(button.bounds, to: nil)
        let screenRect = buttonWindow.convertToScreen(buttonRect)

        // Keep within bounds of whichever screen the menu bar button actually sits
        // on — NSScreen.main can point elsewhere (e.g. after DisplayModeEngine
        // mirrors/powers off a display), which would clamp the panel off-screen.
        let screenFrame = NSScreen.screen(containing: screenRect.origin)?.visibleFrame
            ?? buttonWindow.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? .zero
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
        hideFlyout()
    }

    // MARK: - Multi-monitor Flyout

    private func handleRowHoverChange(_ hovering: Bool) {
        isRowHovered = hovering
        if hovering {
            pendingFlyoutHide?.cancel()
            showFlyout()
        } else {
            scheduleFlyoutHideCheck()
        }
    }

    private func handleFlyoutHoverChange(_ hovering: Bool) {
        isFlyoutHovered = hovering
        if hovering {
            pendingFlyoutHide?.cancel()
        } else {
            scheduleFlyoutHideCheck()
        }
    }

    private func scheduleFlyoutHideCheck() {
        pendingFlyoutHide?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if !self.isRowHovered && !self.isFlyoutHovered {
                self.hideFlyout()
            }
        }
        pendingFlyoutHide = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
    }

    private func makeFlyoutPanel() -> NSPanel {
        let flyoutView = MultiMonitorFlyoutView(
            displays: displayMode.displays,
            mode: displayMode.mode,
            onSelect: { [weak self] mode in
                self?.displayMode.selectMode(mode)
                self?.hideFlyout()
                self?.hidePanel()
            },
            onHoverChange: { [weak self] hovering in
                self?.handleFlyoutHoverChange(hovering)
            }
        )

        let hosting = NSHostingView(rootView: flyoutView)
        hosting.translatesAutoresizingMaskIntoConstraints = false

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
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 100),
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

    private func showFlyout() {
        if flyoutPanel == nil { flyoutPanel = makeFlyoutPanel() }
        else { rebuildFlyoutContent() }
        positionFlyout()
        flyoutPanel?.orderFront(nil)
    }

    private func rebuildFlyoutContent() {
        // Re-create content so the option list reflects the latest displays/mode
        // (e.g. after a selection) without tearing down the panel itself.
        guard let p = flyoutPanel else { return }
        let flyoutView = MultiMonitorFlyoutView(
            displays: displayMode.displays,
            mode: displayMode.mode,
            onSelect: { [weak self] mode in
                self?.displayMode.selectMode(mode)
                self?.hideFlyout()
                self?.hidePanel()
            },
            onHoverChange: { [weak self] hovering in
                self?.handleFlyoutHoverChange(hovering)
            }
        )
        let hosting = NSHostingView(rootView: flyoutView)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        guard let effectView = p.contentView else { return }
        effectView.subviews.forEach { $0.removeFromSuperview() }
        effectView.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: effectView.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: effectView.bottomAnchor),
        ])
    }

    private func positionFlyout() {
        guard let p = flyoutPanel, let mainPanel = panel, multiMonitorRowFrame != .zero else { return }

        p.contentView?.layoutSubtreeIfNeeded()
        let fittingSize = p.contentView?.fittingSize ?? NSSize(width: 240, height: 80)

        let mainFrame = mainPanel.frame  // screen coords, AppKit y-up
        // multiMonitorRowFrame is in SwiftUI's panelSpace: y-down, origin at top of content.
        let rowTopFromContentTop = multiMonitorRowFrame.minY
        let rowTopScreenY = mainFrame.maxY - rowTopFromContentTop

        let x = mainFrame.maxX - 2  // slight overlap, like a native submenu
        let y = rowTopScreenY - fittingSize.height

        p.setFrame(NSRect(x: x, y: y, width: fittingSize.width, height: fittingSize.height), display: true)
    }

    private func hideFlyout() {
        pendingFlyoutHide?.cancel()
        isRowHovered = false
        isFlyoutHovered = false
        flyoutPanel?.orderOut(nil)
    }
}

private extension NSScreen {
    static func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) }
    }
}
