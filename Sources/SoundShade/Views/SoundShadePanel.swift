import SwiftUI
import ServiceManagement

// MARK: - Design tokens (Figma "Dzapps" → SoundShade panel)

private enum DS {
    static let bg = Color(red: 0x20 / 255, green: 0x20 / 255, blue: 0x20 / 255)          // N800 bg
    static let border = Color(red: 0x27 / 255, green: 0x27 / 255, blue: 0x27 / 255)
    static let card = Color(red: 0x27 / 255, green: 0x27 / 255, blue: 0x27 / 255)        // N750 bg+
    static let disabled = Color(red: 0x60 / 255, green: 0x60 / 255, blue: 0x60 / 255)    // N600
    static let secondary = Color(red: 0xB5 / 255, green: 0xB5 / 255, blue: 0xB5 / 255)   // N200
    static let primary = Color(red: 0x48 / 255, green: 0x8E / 255, blue: 0xF9 / 255)     // primary
    static let primaryApp = Color(red: 0x06 / 255, green: 0x72 / 255, blue: 0xFF / 255)  // primary-app
    static let trackBg = Color(red: 0x3F / 255, green: 0x40 / 255, blue: 0x41 / 255)
    static let checkboxOff = Color(red: 0x45 / 255, green: 0x45 / 255, blue: 0x46 / 255)
    static let thumb = Color(white: 0.72)
    static let error = Color(red: 1.0, green: 0.42, blue: 0.42)
}

// MARK: - Icons (SVGs exported from Figma, tinted as templates)

private struct SVGIcon: View {
    let name: String
    var size: CGFloat = 24
    var color: Color = .white

    private static var cache: [String: NSImage] = [:]

    private var image: NSImage? {
        if let cached = Self.cache[name] { return cached }
        guard let url = Bundle.appResources.url(forResource: name, withExtension: "svg", subdirectory: "Icons"),
              let img = NSImage(contentsOf: url) else { return nil }
        img.isTemplate = true
        Self.cache[name] = img
        return img
    }

    var body: some View {
        if let image {
            Image(nsImage: image)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .foregroundStyle(color)
        } else {
            Color.clear.frame(width: size, height: size)
        }
    }
}

// MARK: - Reusable controls

private struct DSCheckbox: View {
    @Binding var isOn: Bool
    var label: String? = nil
    var labelOpacity: Double = 1

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(isOn ? DS.primaryApp : DS.checkboxOff)
                    .frame(width: 16, height: 16)
                    .overlay {
                        if isOn { SVGIcon(name: "check", size: 14) }
                    }
                if let label {
                    Text(label)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(labelOpacity))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct DSSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var step: Double? = nil

    private let thumbSize: CGFloat = 20

    var body: some View {
        GeometryReader { geo in
            let usable = max(1, geo.size.width - thumbSize)
            let frac = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
            let x = min(max(frac, 0), 1) * usable
            ZStack(alignment: .leading) {
                Capsule().fill(DS.trackBg).frame(height: 3)
                Capsule().fill(DS.primary).frame(width: x + thumbSize / 2, height: 3)
                Circle()
                    .fill(DS.thumb)
                    .frame(width: thumbSize, height: thumbSize)
                    .offset(x: x)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { g in
                    let f = min(max((g.location.x - thumbSize / 2) / usable, 0), 1)
                    var v = range.lowerBound + Double(f) * (range.upperBound - range.lowerBound)
                    if let step { v = (v / step).rounded() * step }
                    value = min(max(v, range.lowerBound), range.upperBound)
                }
            )
        }
        .frame(height: 20)
    }
}

/// Tooltip shown while hovering a section label's info icon.
private struct PanelTip: Equatable {
    enum Edge { case below, above }
    enum Align { case leading, trailing }
    let id: String
    let text: String
    var edge: Edge = .below
    var align: Align = .leading
}

private struct TipAnchorKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

private struct SectionLabel: View {
    let text: String
    var tip: PanelTip? = nil
    var onTip: ((PanelTip?) -> Void)? = nil

    var body: some View {
        HStack(spacing: tip == nil ? 0 : 2) {
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(DS.secondary)
            if tip != nil {
                SVGIcon(name: "info", size: 12, color: DS.secondary)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            guard let tip else { return }
            onTip?(hovering ? tip : nil)
        }
        .anchorPreference(key: TipAnchorKey.self, value: .bounds) { anchor in
            tip.map { [$0.id: anchor] } ?? [:]
        }
    }
}

private struct TipBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.white)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(10)
            .frame(width: 240, alignment: .leading)
            .background(Color(red: 0x37 / 255, green: 0x37 / 255, blue: 0x38 / 255), in: RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.3), radius: 8, y: 2)
    }
}

private struct Card<Content: View>: View {
    var padding: CGFloat = 8
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.card, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct SliderCard: View {
    let leadingIcon: String
    var trailingIcon: String? = nil
    var onLeadingTap: (() -> Void)? = nil
    @Binding var value: Double

    var body: some View {
        Card {
            HStack(spacing: 8) {
                Button { onLeadingTap?() } label: {
                    Image(systemName: leadingIcon)
                        .font(.system(size: 15))
                        .foregroundStyle(DS.disabled)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .allowsHitTesting(onLeadingTap != nil)

                DSSlider(value: $value)

                if let trailingIcon {
                    Image(systemName: trailingIcon)
                        .font(.system(size: 15))
                        .foregroundStyle(DS.disabled)
                        .frame(width: 24, height: 24)
                }
            }
        }
    }
}

/// Wraps children onto new lines when they no longer fit the proposed width.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 16

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, width: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            width = max(width, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Panel

/// Space the host panel can occupy; the controller updates it each time the panel opens.
@MainActor
final class PanelLayout: ObservableObject {
    @Published var maxHeight: CGFloat = 700
}

struct SoundShadePanel: View {
    private enum Tab: String, CaseIterable, Identifiable {
        case sound, monitor, system
        var id: Self { self }
        var title: String {
            switch self {
            case .sound: return "Sound"
            case .monitor: return "Monitor"
            case .system: return "System"
            }
        }
        var icon: String {
            switch self {
            case .sound: return "tab-sound"
            case .monitor: return "tab-monitor"
            case .system: return "tab-system"
            }
        }
    }

    @EnvironmentObject var audio: AudioEngine
    @EnvironmentObject var brightness: BrightnessEngine
    @EnvironmentObject var displayMode: DisplayModeEngine
    @EnvironmentObject var layout: PanelLayout

    /// True while a task is running that must survive the panel losing focus (driver install).
    var onBusyChange: (Bool) -> Void = { _ in }

    /// Reopens on whichever tab was used last (persisted across launches).
    @AppStorage("panelSelectedTab") private var tab: Tab = .sound
    @State private var showHiddenDevices = false
    @State private var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled
    @State private var isInstalling = false
    @State private var installError: String?
    /// Bumped to re-read UserDefaults-backed hidden-device list.
    @State private var hiddenRevision = 0
    @State private var activeTip: PanelTip?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            tabBar
            // Panel padding (32) + tab bar (51) + spacing (24) come off the available height.
            // Content that fits is laid out normally; taller content scrolls instead of
            // running off the screen.
            ViewThatFits(in: .vertical) {
                tabContent
                ScrollView(.vertical, showsIndicators: false) { tabContent }
            }
            .frame(maxHeight: max(160, layout.maxHeight - 107))
        }
        .padding(16)
        .frame(width: 400, alignment: .topLeading)
        .background(DS.bg, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(DS.border, lineWidth: 1))
        .fixedSize(horizontal: false, vertical: true)
        .overlayPreferenceValue(TipAnchorKey.self) { anchors in
            GeometryReader { proxy in
                if let tip = activeTip, let anchor = anchors[tip.id] {
                    let r = proxy[anchor]
                    TipBubble(text: tip.text)
                        .frame(
                            maxWidth: .infinity, maxHeight: .infinity,
                            alignment: Alignment(
                                horizontal: tip.align == .leading ? .leading : .trailing,
                                vertical: tip.edge == .below ? .top : .bottom
                            )
                        )
                        .padding(tip.align == .leading ? .leading : .trailing,
                                 tip.align == .leading ? r.minX : proxy.size.width - r.maxX)
                        .padding(tip.edge == .below ? .top : .bottom,
                                 tip.edge == .below ? r.maxY + 6 : proxy.size.height - r.minY + 6)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { launchAtLogin = SMAppService.mainApp.status == .enabled }
        .onChange(of: isInstalling) { onBusyChange($0) }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch tab {
        case .sound: soundTab
        case .monitor: monitorTab
        case .system: systemTab
        }
    }

    // MARK: Tab bar

    private var tabBar: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(Tab.allCases) { t in
                Button { tab = t; activeTip = nil } label: {
                    VStack(spacing: 6) {
                        SVGIcon(name: t.icon, size: 24)
                        Text(t.title)
                            .font(.system(size: 11))
                            .foregroundStyle(.white)
                    }
                    .padding(4)
                    .frame(maxWidth: .infinity)
                    .background(tab == t ? DS.primaryApp : .clear, in: RoundedRectangle(cornerRadius: 8))
                    .contentShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Sound tab

    private var soundTab: some View {
        let devices = audio.allOutputDevices
        let hidden = hiddenUIDs
        // The active output is never tucked away, even if it was hidden earlier.
        let visible = devices.filter { !hidden.contains($0.uid) || $0.id == audio.activeDisplayDeviceID }
        let hiddenDevices = devices.filter { !visible.contains($0) }

        return VStack(alignment: .leading, spacing: 24) {
            if !audio.isDriverInstalled { driverBanner }

            // Always shown so the panel doesn't jump; dimmed and inert when the active
            // output handles its own volume (bypass / no software control).
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Volume")
                SliderCard(
                    leadingIcon: audio.isMuted ? "speaker.slash" : "speaker",
                    trailingIcon: "speaker.wave.3",
                    onLeadingTap: { audio.setMuted(!audio.isMuted) },
                    value: Binding(
                        get: { Double(audio.volume) },
                        set: { audio.setVolume(Float($0)) }
                    )
                )
                .opacity(audio.supportsVolumeControl ? 1 : 0.4)
                .allowsHitTesting(audio.supportsVolumeControl)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 32) {
                    SectionLabel(text: "Choose output")
                    Spacer(minLength: 0)
                    if audio.isDriverInstalled {
                        SectionLabel(
                            text: "Bypass Vol. Control",
                            tip: PanelTip(
                                id: "bypass",
                                text: "Sends audio straight to this device and uses its own volume control, instead of SoundShade's. Turn it on for speakers or receivers with a physical volume knob.",
                                edge: .below,
                                align: .trailing
                            ),
                            onTip: { activeTip = $0 }
                        )
                    }
                    SectionLabel(text: "Hide")
                }

                outputTable(visible, isHiddenGroup: false)

                if !hiddenDevices.isEmpty {
                    if showHiddenDevices {
                        outputTable(hiddenDevices, isHiddenGroup: true)
                    }
                    Button { showHiddenDevices.toggle() } label: {
                        Text(showHiddenDevices ? "Hide hidden devices" : "Show hidden devices")
                            .font(.system(size: 13))
                            .foregroundStyle(DS.primaryApp)
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                SectionLabel(
                    text: "Volume sensitivity",
                    tip: PanelTip(
                        id: "sensitivity",
                        text: "Sets how quiet the lowest volume gets. Slide toward Louder if sound is too quiet or distorts at low volume; toward Quieter for finer control at low volume.",
                        edge: .above,
                        align: .leading
                    ),
                    onTip: { activeTip = $0 }
                )
                Card {
                    VStack(spacing: 4) {
                        DSSlider(
                            value: Binding(
                                get: { Double(audio.minVolumeDB) },
                                set: { audio.setMinVolumeDB(Float($0)) }
                            ),
                            range: -60...(-20),
                            step: 1
                        )
                        HStack {
                            Text("Quieter").frame(maxWidth: .infinity, alignment: .leading)
                            Text("Balanced").frame(maxWidth: .infinity)
                            Text("Louder").frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .font(.system(size: 10))
                        .foregroundStyle(DS.secondary)
                    }
                }
            }
        }
    }

    private func outputTable(_ devices: [AudioDevice], isHiddenGroup: Bool) -> some View {
        Card {
            VStack(spacing: 0) {
                if devices.isEmpty {
                    Text("No audio devices found")
                        .font(.system(size: 12))
                        .foregroundStyle(DS.secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
                ForEach(devices) { device in
                    outputRow(device, isHiddenGroup: isHiddenGroup)
                }
            }
        }
    }

    private func outputRow(_ device: AudioDevice, isHiddenGroup: Bool) -> some View {
        let isActive = device.id == audio.activeDisplayDeviceID
        let canBypass = !device.isBuiltIn && !device.isBluetooth && audio.isDriverInstalled
        return HStack(spacing: 0) {
            Button { audio.setDefaultDevice(device) } label: {
                HStack(spacing: 6) {
                    Image(systemName: isActive ? "speaker.wave.2" : "speaker")
                        .font(.system(size: 15))
                        .foregroundStyle(isActive ? .white : DS.secondary)
                        .frame(width: 32, height: 32)
                        .background(isActive ? DS.primaryApp : DS.card, in: Circle())
                    Text(device.name)
                        .font(.system(size: 13))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            if canBypass {
                DSCheckbox(
                    isOn: Binding(
                        get: { audio.isVolumeRoutingBypassed(device.uid) },
                        set: { audio.setVolumeRoutingBypassed($0, for: device.uid) }
                    ),
                    label: "Bypass"
                )
            }

            Color.clear.frame(width: 32, height: 1)

            Button { setHidden(!isHiddenGroup, device) } label: {
                SVGIcon(name: isHiddenGroup ? "eye" : "eye-slash", size: 24, color: DS.secondary)
                    .opacity(isActive ? 0.35 : 1)
            }
            .buttonStyle(.plain)
            .disabled(isActive)
            .help(isActive ? "The active output can't be hidden" : (isHiddenGroup ? "Show this device" : "Hide this device"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var hiddenUIDs: Set<String> {
        _ = hiddenRevision
        return Set(UserDefaults.standard.stringArray(forKey: "disabledSoundDeviceUIDs") ?? [])
    }

    private func setHidden(_ hide: Bool, _ device: AudioDevice) {
        var uids = UserDefaults.standard.stringArray(forKey: "disabledSoundDeviceUIDs") ?? []
        if hide {
            if !uids.contains(device.uid) { uids.append(device.uid) }
        } else {
            uids.removeAll { $0 == device.uid }
        }
        UserDefaults.standard.set(uids, forKey: "disabledSoundDeviceUIDs")
        hiddenRevision += 1
        audio.refresh()
    }

    // MARK: Monitor tab

    private var monitorTab: some View {
        let externals = brightness.allDisplays.filter { !$0.isBuiltIn }
        return VStack(alignment: .leading, spacing: 24) {
            if externals.isEmpty {
                Text("No external displays found")
                    .font(.system(size: 12))
                    .foregroundStyle(DS.secondary)
            }
            ForEach(externals) { display in
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "Brightness of \(display.name)")
                    SliderCard(
                        leadingIcon: "sun.min",
                        value: Binding(
                            get: { brightness.knownBrightness(for: display) },
                            set: { brightness.setBrightness($0, for: display) }
                        )
                    )
                }
            }

            if displayMode.isAvailable {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "Mirroring")
                    FlowLayout(spacing: 16) {
                        ForEach(displayMode.displays) { display in
                            ModeCard(
                                icons: ["mirror"],
                                caption: "Mirror",
                                name: display.name,
                                selected: displayMode.mode == .single(display.id)
                            ) { displayMode.selectMode(.single(display.id)) }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "Extended")
                    let count = displayMode.displays.count
                    ModeCard(
                        icons: (0..<max(count, 2)).map { $0 == 0 ? "monitor-a" : "monitor-b" },
                        caption: displayMode.mode == .extended ? "Extending" : "Extend",
                        name: "\(Self.numberWord(max(count, 2))) monitors",
                        selected: displayMode.mode == .extended
                    ) { displayMode.selectMode(.extended) }
                }
            }
        }
    }

    private static func numberWord(_ n: Int) -> String {
        let words = ["Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight"]
        return n < words.count ? words[n] : "\(n)"
    }

    // MARK: System tab

    private var systemTab: some View {
        VStack(spacing: 16) {
            SVGIcon(name: "app-icon", size: 80, color: .white)

            VStack(spacing: 4) {
                Text("SoundShade \(Bundle.main.appVersion)")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.8))
                Button {
                    if let url = URL(string: "https://minaby.com/tools") { NSWorkspace.shared.open(url) }
                } label: {
                    Text("minaby.com/tools")
                        .font(.system(size: 11))
                        .foregroundStyle(DS.primary.opacity(0.8))
                }
                .buttonStyle(.plain)
            }

            DSCheckbox(
                isOn: Binding(
                    get: { launchAtLogin },
                    set: { enable in
                        do {
                            if enable { try SMAppService.mainApp.register() }
                            else { try SMAppService.mainApp.unregister() }
                            launchAtLogin = enable
                        } catch {
                            print("Start at login error: \(error)")
                        }
                    }
                ),
                label: "Start at login",
                labelOpacity: 0.8
            )

            HStack(spacing: 8) {
                if !audio.isDriverInstalled {
                    PanelButton(
                        icon: isInstalling ? nil : "install",
                        iconSize: 16,
                        title: isInstalling ? "Installing..." : "Install driver",
                        busy: isInstalling,
                        action: installDriver
                    )
                    .disabled(isInstalling)
                }
                PanelButton(icon: "refresh", iconSize: 12, title: "Refresh devices") {
                    audio.refresh()
                    brightness.refresh()
                    displayMode.refresh(with: brightness.allDisplays)
                }
                PanelButton(systemIcon: "power", title: "Quit") { NSApp.terminate(nil) }
            }

            if let installError, audio.isDriverInstalled == false {
                Text(installError)
                    .font(.system(size: 11))
                    .foregroundStyle(DS.error)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var driverBanner: some View {
        Card(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Text("Volume control needs the SoundShade audio driver.")
                        .font(.system(size: 12))
                        .foregroundStyle(DS.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    PanelButton(
                        icon: isInstalling ? nil : "install",
                        iconSize: 16,
                        title: isInstalling ? "Installing..." : "Install",
                        busy: isInstalling,
                        fill: DS.checkboxOff,
                        action: installDriver
                    )
                    .disabled(isInstalling)
                }
                if let installError {
                    Text(installError)
                        .font(.system(size: 11))
                        .foregroundStyle(DS.error)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func installDriver() {
        isInstalling = true
        installError = nil
        Task {
            do {
                try await audio.installDriver()
                isInstalling = false
            } catch {
                isInstalling = false
                if error.localizedDescription.localizedCaseInsensitiveContains("canceled") {
                    installError = "Installation was cancelled. SoundShade needs administrator permissions to register the audio driver."
                } else {
                    installError = "Driver installation failed: \(error.localizedDescription). Make sure SoundShade is running from /Applications and enter the administrator password when prompted."
                }
            }
        }
    }
}

private struct PanelButton: View {
    var icon: String? = nil
    var systemIcon: String? = nil
    var iconSize: CGFloat = 16
    let title: String
    var busy = false
    var fill: Color = DS.card
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if busy {
                    ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 16, height: 16)
                } else if let icon {
                    SVGIcon(name: icon, size: iconSize)
                } else if let systemIcon {
                    Image(systemName: systemIcon).font(.system(size: 12)).foregroundStyle(.white)
                }
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(fill, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

private struct ModeCard: View {
    let icons: [String]
    let caption: String
    let name: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                HStack(spacing: 4) {
                    ForEach(Array(icons.enumerated()), id: \.offset) { _, icon in
                        SVGIcon(name: icon, size: 40, color: selected || icon != "mirror" ? .white : DS.disabled)
                    }
                }
                VStack(spacing: 4) {
                    Text(caption)
                        .font(.system(size: 13))
                        .foregroundStyle(selected ? DS.primaryApp : DS.secondary)
                    Text(name)
                        .font(.system(size: 14))
                        .foregroundStyle(selected ? DS.primaryApp : .white)
                }
                .multilineTextAlignment(.center)
            }
            .padding(16)
            .frame(height: 117)
            .background(DS.card, in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: 16).strokeBorder(DS.primaryApp, lineWidth: 2)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

extension Bundle {
    /// User-facing version from Info.plist (CFBundleShortVersionString), format YYMMDD.HHmm e.g. "260628.1406".
    var appVersion: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }
}
