import SwiftUI
import ServiceManagement

struct PreferencesView: View {
    @EnvironmentObject var audio: AudioEngine
    @EnvironmentObject var brightness: BrightnessEngine
    
    @State private var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled
    @State private var showHelpPopover: Bool = false
    @State private var showInstallAlert: Bool = false
    @State private var alertMessage: String = ""
    @State private var isInstalling: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Main content area in Rows
            VStack(alignment: .leading, spacing: 20) {
                // ROW 1: Logo & Sensitivity (Left) + Preferences (Right)
                HStack(alignment: .top, spacing: 40) {
                    // Left Column Top: Logo + Low-volume sensitivity
                    HStack(alignment: .top, spacing: 16) {
                        if let url = Bundle.appResources.url(forResource: "StatusIcon", withExtension: "svg"),
                           let nsImage = NSImage(contentsOf: url) {
                            Image(nsImage: nsImage)
                                .renderingMode(.template)   // tint with foreground => theme aware
                                .resizable()
                                .scaledToFit()
                                .frame(width: 72, height: 72)
                                .foregroundStyle(.primary)
                                .opacity(0.5)
                        } else {
                            Image(systemName: "speaker.wave.3.bubble.left.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 72, height: 72)
                                .foregroundColor(.secondary)
                        }
                        
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .center, spacing: 4) {
                                Text("Low-volume sensitivity")
                                    .font(.system(size: 13, weight: .regular))
                                
                                Button(action: { showHelpPopover.toggle() }) {
                                    Image(systemName: "info.circle")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Click to see details about Low-volume sensitivity.")
                                .popover(isPresented: $showHelpPopover, arrowEdge: .trailing) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Low-volume sensitivity")
                                            .font(.system(size: 11, weight: .bold))
                                        Text("Adjusts the quietest volume level of the software attenuation box. Slide towards Louder if audio clips or sounds too quiet at low settings.")
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(10)
                                    .frame(width: 220)
                                }
                            }
                            
                            Slider(value: Binding(
                                get: { Double(audio.minVolumeDB) },
                                set: { audio.setMinVolumeDB(Float($0)) }
                            ), in: -60.0...(-20.0), step: 1.0)
                            .frame(width: 190)
                            
                            HStack {
                                Text("Quietest")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("Balanced")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("Louder")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }
                            .frame(width: 190)
                        }
                    }
                    .frame(width: 290, alignment: .topLeading)
                    
                    // Right Column Top: Preferences (Header) + Start at login (Checkbox)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Preferences")
                            .font(.system(size: 16, weight: .bold))
                        
                        Toggle("Start at login", isOn: Binding(
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
                        ))
                        .toggleStyle(.checkbox)
                        .font(.system(size: 13))
                    }
                    .frame(width: 250, alignment: .topLeading)
                }
                
                // ROW 2: Sound Devices (Left) + Brightness Devices (Right)
                HStack(alignment: .top, spacing: 40) {
                    // Left Column Bottom: Sound devices
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Sound devices")
                            .font(.system(size: 16, weight: .bold))
                            .padding(.bottom, 2)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            if audio.allOutputDevices.isEmpty {
                                Text("No audio devices found")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            } else {
                                ForEach(audio.allOutputDevices) { device in
                                    let isEnabled = {
                                        let uids = UserDefaults.standard.stringArray(forKey: "enabledSoundDeviceUIDs")
                                        return uids == nil || uids!.contains(device.uid)
                                    }()
                                    VStack(alignment: .leading, spacing: 2) {
                                        Toggle(device.name, isOn: Binding(
                                            get: { isEnabled },
                                            set: { enabled in
                                                var uids = UserDefaults.standard.stringArray(forKey: "enabledSoundDeviceUIDs") ?? audio.allOutputDevices.map { $0.uid }
                                                if enabled {
                                                    if !uids.contains(device.uid) { uids.append(device.uid) }
                                                } else {
                                                    uids.removeAll { $0 == device.uid }
                                                }
                                                UserDefaults.standard.set(uids, forKey: "enabledSoundDeviceUIDs")
                                                audio.refresh()
                                            }
                                        ))
                                        .toggleStyle(.checkbox)
                                        .font(.system(size: 13))

                                        // External devices can opt out of the software-volume
                                        // proxy and route directly (volume handled by hardware).
                                        if isEnabled, !device.isBuiltIn, !device.isBluetooth, audio.isDriverInstalled {
                                            Toggle("Bypass software volume", isOn: Binding(
                                                get: { audio.isVolumeRoutingBypassed(device.uid) },
                                                set: { audio.setVolumeRoutingBypassed($0, for: device.uid) }
                                            ))
                                            .toggleStyle(.checkbox)
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                            .padding(.leading, 18)
                                            .help("Route audio directly to this device instead of through SoundShade's software volume. Use when the device (e.g. powered speakers or an AVR) has its own volume control.")
                                        }
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.leading, 88)
                    .frame(width: 290, alignment: .topLeading)
                    
                    // Right Column Bottom: Brightness control devices
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Brightness control devices")
                            .font(.system(size: 16, weight: .bold))
                            .padding(.bottom, 2)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            if brightness.allDisplays.isEmpty {
                                Text("No displays found")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            } else {
                                ForEach(brightness.allDisplays) { display in
                                    Toggle(display.name, isOn: Binding(
                                        get: {
                                            let names = UserDefaults.standard.stringArray(forKey: "enabledDisplayNames")
                                            return names == nil || names!.contains(display.name)
                                        },
                                        set: { enabled in
                                            var names = UserDefaults.standard.stringArray(forKey: "enabledDisplayNames") ?? brightness.allDisplays.map { $0.name }
                                            if enabled {
                                                if !names.contains(display.name) { names.append(display.name) }
                                            } else {
                                                names.removeAll { $0 == display.name }
                                            }
                                            UserDefaults.standard.set(names, forKey: "enabledDisplayNames")
                                            brightness.refresh()
                                        }
                                    ))
                                    .toggleStyle(.checkbox)
                                    .font(.system(size: 13))
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(width: 250, alignment: .topLeading)
                }
            }
            .padding(.top, 24)
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
            
            Divider()
            
            // Footer area
            HStack(alignment: .center) {
                // Left
                VStack(alignment: .leading, spacing: 2) {
                    Text("SoundShade")
                        .font(.system(size: 11, weight: .semibold))
                    Text("by Dizzy · v\(Bundle.main.appVersion)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Right (Link + Refresh Button group)
                HStack(spacing: 20) {
                    Button("minaby.com/tools") {
                        if let url = URL(string: "https://minaby.com/tools") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 12))
                    
                    if !audio.isDriverInstalled {
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
                            HStack(spacing: 6) {
                                if isInstalling {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    if let url = Bundle.appResources.url(forResource: "InstallIcon", withExtension: "svg"),
                                       let nsImage = NSImage(contentsOf: url) {
                                        Image(nsImage: nsImage)
                                            .renderingMode(.template)
                                            .foregroundColor(.primary)
                                    } else {
                                        Image(systemName: "square.and.arrow.down")
                                    }
                                }
                                Text(isInstalling ? "Installing..." : "Install driver")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isInstalling)
                    }
                    
                    Button(action: {
                        audio.refresh()
                        brightness.refresh()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                            Text("Refresh devices")
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 24)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.3))
        }
        .frame(width: 620)
        .frame(minHeight: 280, maxHeight: .infinity)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
        .alert("Driver Installation Failed", isPresented: $showInstallAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
    }
}

extension Bundle {
    /// User-facing version from Info.plist (CFBundleShortVersionString), format YYMMDD.HHmm e.g. "260628.1406".
    var appVersion: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }
}
