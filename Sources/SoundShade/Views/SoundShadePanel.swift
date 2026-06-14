import SwiftUI
import ServiceManagement

// MARK: - Main Panel View

struct SoundShadePanel: View {
    @EnvironmentObject var audio: AudioEngine
    @EnvironmentObject var brightness: BrightnessEngine

    @State private var showInstallAlert = false
    @State private var alertMessage = ""
    @State private var isInstalling = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ═══════════════════════════════════════════
            // SECTION 1: SOUND OUTPUT
            // ═══════════════════════════════════════════
            SectionHeader(title: "Sound Output")
                .padding(.top, 14)
                .padding(.horizontal, 16)

            if !audio.isDriverInstalled {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.system(size: 11))
                        Text("Audio driver required for external screens.")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Button(action: {
                        isInstalling = true
                        Task {
                            do {
                                try await audio.installDriver()
                                isInstalling = false
                            } catch {
                                isInstalling = false
                                if error.localizedDescription.contains("canceled") || error.localizedDescription.contains("Canceled") || error.localizedDescription.contains("User canceled") {
                                    alertMessage = "Installation was cancelled. SoundShade needs administrator permissions to register the audio driver."
                                } else {
                                    alertMessage = "Error: \(error.localizedDescription)\n\nPlease make sure SoundShade is running from the '/Applications' folder and that you enter the correct administrator password when prompted."
                                }
                                showInstallAlert = true
                            }
                        }
                    }) {
                        HStack(spacing: 4) {
                            if isInstalling {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(isInstalling ? "Installing..." : "Install Audio Driver")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(isInstalling ? Color.gray : Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .disabled(isInstalling)
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 6)
            }

            // Device list
            VStack(spacing: 1) {
                ForEach(audio.outputDevices) { device in
                    DeviceRowView(
                        device: device,
                        isSelected: device.id == audio.activeDisplayDeviceID,
                        onSelect: { audio.setDefaultDevice(device) }
                    )
                }
            }
            .padding(.top, 4)

            // Volume control — shown below the device list
            if audio.supportsVolumeControl {
                HStack(spacing: 10) {
                    Button(action: { audio.setMuted(!audio.isMuted) }) {
                        Image(systemName: audio.isMuted ? "speaker.slash.fill" : volumeIcon)
                            .font(.system(size: 13))
                            .foregroundStyle(audio.isMuted ? .secondary : Color.accentColor)
                            .frame(width: 18)
                    }
                    .buttonStyle(.plain)
                    .help(audio.isMuted ? "Unmute" : "Mute")

                    Slider(value: Binding(
                        get: { Double(audio.volume) },
                        set: { audio.setVolume(Float($0)) }
                    ))
                    .disabled(audio.isMuted)

                    Text("\(Int(audio.volume * 100))%")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 32, alignment: .trailing)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 10)
            } else {
                // HDMI/DP: no hardware volume
                HStack(spacing: 6) {
                    Image(systemName: "speaker.slash")
                        .font(.system(size: 11))
                    Text("Volume not available for this device")
                        .font(.system(size: 11))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 10)
            }

            // Smart Bypass badge
            if audio.activeDevice?.isBluetooth == true {
                HStack(spacing: 4) {
                    Image(systemName: "bolt.shield")
                        .font(.system(size: 10))
                    Text("Bluetooth — macOS controls volume natively")
                        .font(.system(size: 10))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }

            // ═══════════════════════════════════════════
            // SECTION 2: BRIGHTNESS
            // ═══════════════════════════════════════════
            if brightness.isAvailable {
                Divider()

                SectionHeader(title: "Brightness")
                    .padding(.top, 14)
                    .padding(.horizontal, 16)

                // Display list
                VStack(spacing: 1) {
                    ForEach(brightness.displays) { display in
                        DisplayRowView(
                            display: display,
                            isSelected: display.id == brightness.selectedDisplayID,
                            onSelect: { brightness.selectDisplay(display) }
                        )
                    }
                }
                .padding(.top, 4)

                // Brightness slider — for selected display
                if let sel = brightness.selectedDisplay, !sel.isBuiltIn {
                    HStack(spacing: 10) {
                        Image(systemName: "sun.min")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 18)

                        Slider(value: Binding(
                            get: { brightness.brightness },
                            set: { brightness.setBrightness($0) }
                        ))

                        Text("\(Int(brightness.brightness * 100))%")
                            .font(.system(size: 11, weight: .medium).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 32, alignment: .trailing)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 10)
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "sun.slash")
                            .font(.system(size: 11))
                        Text("Select an external display to adjust brightness")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .padding(.bottom, 10)
                }
            }

            // ═══════════════════════════════════════════
            // FOOTER
            // ═══════════════════════════════════════════
            Divider()

            VStack(spacing: 0) {
                MenuFooterButton(label: "Preferences...", icon: "gearshape") {
                    PreferencesWindowController.shared.show()
                }

                Divider()

                MenuFooterButton(label: "Quit SoundShade", icon: "power") {
                    NSApp.terminate(nil)
                }
            }
            .padding(.bottom, 8)
        }
        .frame(width: 290)
        .alert("Driver Installation Failed", isPresented: $showInstallAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
    }

    // MARK: - Helpers

    private var volumeIcon: String {
        let v = audio.volume
        if audio.isMuted || v == 0 { return "speaker.slash.fill" }
        if v < 0.33 { return "speaker.wave.1.fill" }
        if v < 0.66 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }
}

// MARK: - Section Header

struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.bottom, 2)
    }
}

// MARK: - Footer Button

struct MenuFooterButton: View {
    let label: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .foregroundStyle(.primary)
    }
}
