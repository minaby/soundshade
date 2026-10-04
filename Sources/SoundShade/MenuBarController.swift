import AppKit
import SwiftUI

// MARK: - Menu Bar Controller
// Uses a borderless NSPanel instead of NSPopover: the design is a rounded,
// arrow-less card, and the panel lets us anchor the top edge under the icon
// while the height changes between tabs.

@MainActor
final class MenuBarController {

    private var statusItem: NSStatusItem?
    private var panel: NSPanel?
    private var eventMonitor: Any?

    private let audio = AudioEngine.shared
    private let brightness = BrightnessEngine.shared
    private let displayMode = DisplayModeEngine.shared

    /// True while a task (e.g. driver install, which shows a system auth dialog)
    /// needs the panel to stay open even though focus moved elsewhere.
    private var isBusy = false
    private let panelLayout = PanelLayout()
    /// Last content size reported by the SwiftUI view. SwiftUI only reports
    /// *changes*, so this is the source of truth when re-opening the panel.
    private var lastContentSize: CGSize = .zero

    private var screenChangeRecreateWorkItem: DispatchWorkItem?
    private var pendingSetupRetry: DispatchWorkItem?
    /// Bumped on every teardown so a retry scheduled by a previous setup pass
    /// can tell it has been superseded and bail out instead of adding a
    /// second status item.
    private var setupGeneration = 0

    /// A single cable swap or mirror change emits didChangeScreenParameters
    /// several times; wait for the burst to settle before rebuilding.
    private static let screenChangeDebounce: TimeInterval = 1.0

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
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.screenChangeDebounce, execute: workItem)
    }

    private func recreateStatusItem() {
        teardownStatusItem()
        setupStatusItem()
    }

    private func teardownStatusItem() {
        // Invalidate any retry still in flight, otherwise it fires after the
        // rebuild and registers a second, orphaned item.
        pendingSetupRetry?.cancel()
        pendingSetupRetry = nil
        setupGeneration &+= 1

        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItem = nil
    }

    // MARK: - Setup

    private func setupStatusItem(attempt: Int = 0) {
        let generation = setupGeneration
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // Persist the item's position across relaunches and keep it visible. Helps
        // it survive login-time races and menu-bar reshuffles after reboot.
        item.autosaveName = "com.soundshade.statusitem"
        item.isVisible = true
        item.behavior = []

        guard let button = item.button else {
            // The button can briefly be nil if we launch before the menu bar is
            // ready (e.g. as a login item). Hand this item back before retrying:
            // an item left registered without a button keeps its menu bar slot for
            // the lifetime of the process, and repeated screen changes would stack
            // up invisible items until the bar runs out of room.
            NSStatusBar.system.removeStatusItem(item)
            guard attempt < 10 else { return }
            let retry = DispatchWorkItem { [weak self] in
                guard let self, self.setupGeneration == generation else { return }
                self.pendingSetupRetry = nil
                self.setupStatusItem(attempt: attempt + 1)
            }
            pendingSetupRetry = retry
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: retry)
            return
        }

        // Only publish the item once it is known-good.
        statusItem = item

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

        button.action = #selector(statusItemClicked)
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    // MARK: - Panel

    private func makePanel() -> NSPanel {
        let panelView = SoundShadePanel(
            onBusyChange: { [weak self] busy in
                self?.isBusy = busy
            }
        )
            .environmentObject(audio)
            .environmentObject(brightness)
            .environmentObject(displayMode)
            .environmentObject(panelLayout)

        let hosting = SizingHostingView(rootView: AnyView(panelView))
        hosting.sizingOptions = [.intrinsicContentSize]
        hosting.autoresizingMask = [.width, .height]
        hosting.onSizeChange = { [weak self] size in self?.resizePanel(to: size) }

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 100))
        hosting.frame = container.bounds
        container.addSubview(hosting)

        let p = KeyablePanel(
            contentRect: container.frame,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        p.contentView = container
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .popUpMenu
        p.collectionBehavior = [.transient, .ignoresCycle, .moveToActiveSpace]
        p.animationBehavior = .utilityWindow
        p.onCancel = { [weak self] in self?.hidePanel() }

        return p
    }

    /// Keeps the top edge (just under the menu bar icon) fixed and grows/shrinks downward.
    private func resizePanel(to size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        lastContentSize = size
        guard let p = panel else { return }
        let old = p.frame
        guard abs(old.height - size.height) > 0.5 || abs(old.width - size.width) > 0.5 else { return }
        let frame = NSRect(x: old.minX, y: old.maxY - size.height, width: size.width, height: size.height)
        p.setFrame(frame, display: true)
    }

    // MARK: - Toggle

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePanel()
        }
    }

    private func showContextMenu() {
        hidePanel()
        guard let item = statusItem else { return }
        let menu = NSMenu()
        let refresh = NSMenuItem(title: "Refresh Devices", action: #selector(refreshDevices), keyEquivalent: "")
        refresh.target = self
        menu.addItem(refresh)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit SoundShade", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        // Attach only for this click so left-click keeps opening the panel.
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    @objc private func refreshDevices() {
        audio.refresh()
        brightness.refresh()
        displayMode.refresh(with: brightness.allDisplays)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func togglePanel() {
        if let p = panel, p.isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    /// Opens the panel under the menu bar icon (also used when the app is re-launched).
    func showPanel() {
        if panel == nil { panel = makePanel() }
        guard let p = panel,
              let button = statusItem?.button,
              let buttonWindow = button.window else { return }

        // Never let the panel run past the bottom of the screen the icon is on.
        let iconScreen = NSScreen.screen(containing: buttonWindow.convertToScreen(button.convert(button.bounds, to: nil)).origin)?.visibleFrame
            ?? buttonWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        panelLayout.maxHeight = max(300, buttonWindow.convertToScreen(button.convert(button.bounds, to: nil)).minY - iconScreen.minY - 8)

        // Refresh data on open
        audio.refresh()
        brightness.refresh()
        displayMode.refresh(with: brightness.allDisplays)

        // Size the panel to fit content
        p.contentView?.layoutSubtreeIfNeeded()
        let fitting = p.contentView?.subviews.first?.fittingSize
        if let f = fitting, f.height > 0 { lastContentSize = f }
        let panelWidth: CGFloat = 400
        let panelHeight = lastContentSize.height > 0 ? lastContentSize.height : max(100, fitting?.height ?? p.frame.height)

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

        // Dismiss on click outside (global monitors only see events for other apps).
        if eventMonitor == nil {
            eventMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown]
            ) { [weak self] _ in
                guard let self, !self.isBusy else { return }
                self.hidePanel()
            }
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

/// Borderless panels can't become key by default; being key lets hover tooltips
/// work and Esc close the panel, without activating the app (.nonactivatingPanel).
private final class KeyablePanel: NSPanel {
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

/// Reports the SwiftUI content's ideal size every time it changes (tab switch,
/// list growing/shrinking) so the panel can follow it.
private final class SizingHostingView: NSHostingView<AnyView> {
    var onSizeChange: ((CGSize) -> Void)?
    private var lastReported: CGSize = .zero

    // NSHostingView doesn't reliably call invalidateIntrinsicContentSize() when the
    // SwiftUI content changes size, but it does re-run layout(), so check there.
    override func layout() {
        super.layout()
        let size = fittingSize
        guard size.width > 0, size.height > 0, size != lastReported else { return }
        lastReported = size
        // Resize the window synchronously, in the same layout pass that changed the
        // content. Deferring it a runloop turn shows one frame of new content in
        // the old-size window (the visible "jump" when switching tabs).
        onSizeChange?(size)
    }
}

private extension NSScreen {
    static func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) }
    }
}
