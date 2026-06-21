//
//  AudioEngine.swift
//  SoundShade
//
//  Created by Dizzy (minaby.com).
//  Licensed under GNU GPLv3.
//
//  This file includes integration with "ProxyAudioDevice" (https://github.com/dancharon/ProxyAudioDevice),
//  a lightweight CoreAudio HAL audio plug-in template.
//  The compiled HAL driver is bundled within the application resources.
//

import Foundation
import CoreAudio
import AudioToolbox

// MARK: - Audio Engine

@MainActor
final class AudioEngine: ObservableObject {
    static let shared = AudioEngine()

    @Published var outputDevices: [AudioDevice] = []
    @Published var allOutputDevices: [AudioDevice] = []
    @Published var defaultDeviceID: AudioObjectID = 0
    @Published var activeDisplayDeviceID: AudioObjectID = 0
    @Published var volume: Float = 0.5
    @Published var isMuted: Bool = false
    @Published var supportsVolumeControl: Bool = true
    @Published var isDriverInstalled: Bool = false
    @Published var minVolumeDB: Float = -45.0

    private let proxyDeviceUID = "ProxyAudioDevice_UID"
    private let proxyBoxUID = "ProxyAudioBox_UID"

    private var propertyListenerID: AudioObjectPropertyListenerProc?
    private var listenerRegistered = false

    init() {
        NSLog("SoundShade: App Main Bundle URL: \(Bundle.main.bundleURL)")
        if let moduleURL = Bundle.appResources.url(forResource: "ProxyAudioDevice", withExtension: "driver") {
            NSLog("SoundShade: Found driver at: \(moduleURL.path)")
        } else {
            NSLog("SoundShade: Driver NOT found via Bundle.module")
        }
        
        let path = "/Library/Audio/Plug-Ins/HAL/ProxyAudioDevice.driver"
        let exists = FileManager.default.fileExists(atPath: path)
        NSLog("SoundShade: Driver is installed at destination: \(exists)")
        
        refresh()
        startListening()
    }

    // MARK: - Public API

    func refresh() {
        let allIDs = getAllDeviceIDs()
        let realDefaultDeviceID = getDefaultOutputDeviceID()
        defaultDeviceID = realDefaultDeviceID
        
        let proxyID = allIDs.first { getDeviceUID($0) == proxyDeviceUID }
        isDriverInstalled = proxyID != nil
        
        if isDriverInstalled {
            minVolumeDB = readMinVolumeDB()
        }
        
        // Build output devices list, excluding the Proxy Audio Device itself
        let allOutput = allIDs
            .filter { isOutputDevice($0) }
            .map { buildDevice($0) }
            .filter { $0.uid != proxyDeviceUID }
        
        allOutputDevices = allOutput
        
        let enabledUIDs = UserDefaults.standard.stringArray(forKey: "enabledSoundDeviceUIDs")
        let hasSavedEnabled = enabledUIDs != nil
        let actualEnabledUIDs = enabledUIDs ?? []
        
        outputDevices = allOutput.filter { !hasSavedEnabled || actualEnabledUIDs.contains($0.uid) }
        
        if realDefaultDeviceID == proxyID, let proxy = proxyID {
            // If the proxy is active, the actual active device is the proxy's target
            if let targetUID = getProxyTargetUID(),
               let targetID = allIDs.first(where: { getDeviceUID($0) == targetUID }) {
                activeDisplayDeviceID = targetID
            } else {
                activeDisplayDeviceID = realDefaultDeviceID
            }
            supportsVolumeControl = true
            volume = getVolume(for: proxy)
            isMuted = getMuted(for: proxy)
        } else {
            activeDisplayDeviceID = realDefaultDeviceID
            supportsVolumeControl = deviceSupportsVolume(realDefaultDeviceID)
            volume = supportsVolumeControl ? getVolume(for: realDefaultDeviceID) : getSystemVolume()
            isMuted = getMuted(for: realDefaultDeviceID)
        }
        
        // Update selection in list
        outputDevices = outputDevices.map {
            var d = $0
            d.isDefault = (d.id == activeDisplayDeviceID)
            return d
        }
        
        allOutputDevices = allOutputDevices.map {
            var d = $0
            d.isDefault = (d.id == activeDisplayDeviceID)
            return d
        }
    }

    func setDefaultDevice(_ device: AudioDevice) {
        if device.isBuiltIn || isBluetooth(device.id) {
            // Built-in speaker or Bluetooth: route directly
            guard setDefaultOutputDeviceID(device.id) else { return }
            _ = setDefaultSystemOutputDeviceID(device.id)
        } else {
            // External screen: route via Proxy Audio Device for software volume,
            // unless the user bypassed it for this device (e.g. they have speakers
            // with their own volume control and want bit-perfect passthrough).
            let proxyID = getAllDeviceIDs().first(where: { getDeviceUID($0) == proxyDeviceUID })
            if !isVolumeRoutingBypassed(device.uid), let proxyID {
                configureProxyDevice(targetUID: device.uid)
                guard setDefaultOutputDeviceID(proxyID) else { return }
                _ = setDefaultSystemOutputDeviceID(proxyID)
            } else {
                // Direct routing: proxy not installed, or bypassed by the user.
                guard setDefaultOutputDeviceID(device.id) else { return }
                _ = setDefaultSystemOutputDeviceID(device.id)
            }
        }
        refresh()
    }

    // MARK: - Per-device volume routing bypass

    private let bypassedUIDsKey = "bypassedSoundDeviceUIDs"

    /// Whether the user opted this device out of the software-volume proxy,
    /// routing audio directly so volume is controlled by the hardware instead.
    func isVolumeRoutingBypassed(_ uid: String) -> Bool {
        (UserDefaults.standard.stringArray(forKey: bypassedUIDsKey) ?? []).contains(uid)
    }

    func setVolumeRoutingBypassed(_ bypassed: Bool, for uid: String) {
        var uids = UserDefaults.standard.stringArray(forKey: bypassedUIDsKey) ?? []
        if bypassed {
            if !uids.contains(uid) { uids.append(uid) }
        } else {
            uids.removeAll { $0 == uid }
        }
        UserDefaults.standard.set(uids, forKey: bypassedUIDsKey)

        // Re-apply routing now if the changed device is the active one.
        if let active = activeDevice, active.uid == uid {
            setDefaultDevice(active)
        } else {
            objectWillChange.send()
        }
    }

    func setVolume(_ value: Float) {
        if isBluetooth(defaultDeviceID) {
            // Smart Bypass: AirPods / BT — let macOS handle natively
            setSystemVolume(value)
            volume = value
            return
        }
        guard supportsVolumeControl else {
            // HDMI/DP devices (e.g. Dell U2723QE) have no CoreAudio volume properties.
            return
        }
        let didSet = setDeviceVolume(value, for: defaultDeviceID)
        if !didSet {
            setSystemVolume(value)
        }
        volume = value
    }

    func setMuted(_ muted: Bool) {
        setDeviceMuted(muted, for: defaultDeviceID)
        isMuted = muted
    }

    var activeDevice: AudioDevice? {
        outputDevices.first { $0.id == activeDisplayDeviceID }
    }

    // MARK: - CoreAudio Helpers

    private func getAllDeviceIDs() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
        ) == noErr else { return [] }

        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var ids = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids
        ) == noErr else { return [] }
        return ids
    }

    private func isOutputDevice(_ id: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr && size > 0
    }

    func deviceSupportsVolume(_ id: AudioObjectID) -> Bool {
        if isBluetooth(id) { return true }  // BT uses system volume
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectHasProperty(id, &address) {
            var writable: DarwinBoolean = false
            AudioObjectIsPropertySettable(id, &address, &writable)
            if writable.boolValue { return true }
        }
        return false
    }

    private func buildDevice(_ id: AudioObjectID) -> AudioDevice {
        AudioDevice(
            id: id,
            name: getDeviceName(id),
            uid: getDeviceUID(id),
            transportType: getTransportType(id),
            isDefault: (id == defaultDeviceID)
        )
    }

    private func getDeviceName(_ id: AudioObjectID) -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<CFString?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name) == noErr,
              let n = name?.takeRetainedValue() else { return "Unknown Device" }
        return n as String
    }

    private func getDeviceUID(_ id: AudioObjectID) -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uid: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<CFString?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &uid) == noErr,
              let u = uid?.takeRetainedValue() else { return "" }
        return u as String
    }

    private func getTransportType(_ id: AudioObjectID) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(id, &address, 0, nil, &size, &transport)
        return transport
    }

    func isBluetooth(_ id: AudioObjectID) -> Bool {
        let t = getTransportType(id)
        return t == kAudioDeviceTransportTypeBluetooth || t == kAudioDeviceTransportTypeBluetoothLE
    }

    private func getDefaultOutputDeviceID() -> AudioObjectID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioObjectID = 0
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        return deviceID
    }

    @discardableResult
    private func setDefaultOutputDeviceID(_ id: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = id
        let size = UInt32(MemoryLayout<AudioObjectID>.size)
        return AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, size, &device
        ) == noErr
    }

    @discardableResult
    private func setDefaultSystemOutputDeviceID(_ id: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = id
        let size = UInt32(MemoryLayout<AudioObjectID>.size)
        return AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, size, &device
        ) == noErr
    }

    private func getVolume(for id: AudioObjectID) -> Float {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectHasProperty(id, &address) {
            var vol: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(id, &address, 0, nil, &size, &vol) == noErr {
                return vol
            }
        }
        // Fallback: read system output volume (for devices like Dell USB-C)
        return getSystemVolume()
    }

    // Returns true if volume was successfully set
    @discardableResult
    private func setDeviceVolume(_ value: Float, for id: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(id, &address) else { return false }
        var writable: DarwinBoolean = false
        AudioObjectIsPropertySettable(id, &address, &writable)
        guard writable.boolValue else { return false }
        var vol = value
        let size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectSetPropertyData(id, &address, 0, nil, size, &vol) == noErr
    }

    private func getMuted(for id: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(id, &address) else { return false }
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(id, &address, 0, nil, &size, &muted)
        return muted != 0
    }

    private func setDeviceMuted(_ muted: Bool, for id: AudioObjectID) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(id, &address) else { return }
        var value: UInt32 = muted ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectSetPropertyData(id, &address, 0, nil, size, &value)
    }

    // MARK: - System Output Volume (software attenuation fallback)
    // When the default output device has no settable volume (e.g. Dell USB-C),
    // we control the System Output Device's volume instead.
    // macOS routes both output streams through the same software gain stage.

    private func getSystemOutputDeviceID() -> AudioObjectID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var id: AudioObjectID = 0
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id
        )
        return id
    }

    private func setSystemVolume(_ value: Float) {
        let sysID = getSystemOutputDeviceID()
        let target = sysID != 0 ? sysID : defaultDeviceID

        // Set volume on ch0 (master) of the system output device
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(target, &address) else { return }
        var writable: DarwinBoolean = false
        AudioObjectIsPropertySettable(target, &address, &writable)
        guard writable.boolValue else { return }
        var vol = value
        let size = UInt32(MemoryLayout<Float32>.size)
        AudioObjectSetPropertyData(target, &address, 0, nil, size, &vol)
    }

    private func getSystemVolume() -> Float {
        let sysID = getSystemOutputDeviceID()
        let target = sysID != 0 ? sysID : defaultDeviceID
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(target, &address) else { return 0.5 }
        var vol: Float32 = 0.5
        var size = UInt32(MemoryLayout<Float32>.size)
        AudioObjectGetPropertyData(target, &address, 0, nil, &size, &vol)
        return vol
    }

    // MARK: - Property Listener (live updates)

    private func startListening() {
        // Polling-based approach: refresh on every menu open (see MenuBarController)
        // Full C callback listener requires bridging beyond Swift 6 actor isolation
        listenerRegistered = true
    }

    nonisolated private func stopListening() {
        // No-op: no real C listener registered
    }

    // MARK: - Proxy Driver Helpers
    
    private func getBoxID(for uid: String) -> AudioObjectID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslateUIDToBox,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var boxID: AudioObjectID = 0
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var uidCF = uid as CFString
        
        let status = withUnsafePointer(to: &uidCF) { uidPtr in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                UInt32(MemoryLayout<CFString>.size),
                uidPtr,
                &size,
                &boxID
            )
        }
        return status == noErr ? boxID : 0
    }
    
    private func setIdentifyValue(boxID: AudioObjectID, value: Int32) -> Bool {
        var val = value
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyIdentify,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectSetPropertyData(
            boxID,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<Int32>.size),
            &val
        )
        return status == noErr
    }
    
    private func setBoxObjectName(boxID: AudioObjectID, name: String) -> Bool {
        var nameCF = name as CFString
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = withUnsafePointer(to: &nameCF) { namePtr in
            AudioObjectSetPropertyData(
                boxID,
                &address,
                0,
                nil,
                UInt32(MemoryLayout<CFString>.size),
                namePtr
            )
        }
        return status == noErr
    }
    
    private func getBoxObjectName(boxID: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = AudioObjectGetPropertyData(
            boxID,
            &address,
            0,
            nil,
            &size,
            &name
        )
        guard status == noErr, let n = name?.takeRetainedValue() else { return nil }
        return n as String
    }
    
    func configureProxyDevice(targetUID: String) {
        let boxID = getBoxID(for: proxyBoxUID)
        guard boxID != 0 else { return }
        
        // Identify ourselves as the configurator
        _ = setIdentifyValue(boxID: boxID, value: getpid())
        
        // Set target output device
        _ = setBoxObjectName(boxID: boxID, name: "outputDevice=\(targetUID)")
    }
    
    func getProxyTargetUID() -> String? {
        let boxID = getBoxID(for: proxyBoxUID)
        guard boxID != 0 else { return nil }
        
        // Identify ourselves as the configurator
        _ = setIdentifyValue(boxID: boxID, value: getpid())
        
        // Request the outputDevice configuration type (-1)
        _ = setIdentifyValue(boxID: boxID, value: -1)
        
        return getBoxObjectName(boxID: boxID)
    }

    func installDriver() async throws {
        guard let driverURL = Bundle.appResources.url(forResource: "ProxyAudioDevice", withExtension: "driver") else {
            throw NSError(domain: "SoundShade", code: 1, userInfo: [NSLocalizedDescriptionKey: "ProxyAudioDevice.driver template not found in bundle resources."])
        }
        
        let tempSharedPath = "/Users/Shared/ProxyAudioDevice.driver"
        let destinationPath = "/Library/Audio/Plug-Ins/HAL/ProxyAudioDevice.driver"
        
        // 1. Copy to /Users/Shared first (runs with user's TCC permissions)
        let fm = FileManager.default
        if fm.fileExists(atPath: tempSharedPath) {
            try? fm.removeItem(atPath: tempSharedPath)
        }
        
        do {
            try fm.copyItem(atPath: driverURL.path, toPath: tempSharedPath)
        } catch {
            throw NSError(domain: "SoundShade", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to copy driver to /Users/Shared: \(error.localizedDescription)"])
        }
        
        // 2. Run AppleScript to copy from /Users/Shared to /Library/Audio/Plug-Ins/HAL/ as root
        let script = """
        do shell script "rm -rf '\(destinationPath)' && cp -R '\(tempSharedPath)' '\(destinationPath)' && chown -R root:wheel '\(destinationPath)' && rm -rf '\(tempSharedPath)' && killall coreaudiod" with administrator privileges
        """
        
        var errorDict: NSDictionary?
        let appleScript = NSAppleScript(source: script)
        _ = appleScript?.executeAndReturnError(&errorDict)
        
        if let error = errorDict {
            let message = error[NSAppleScript.errorMessage] as? String ?? "Unknown authentication error"
            throw NSError(domain: "SoundShade", code: 3, userInfo: [NSLocalizedDescriptionKey: message])
        }
        
        // Wait 1.5 seconds for coreaudiod to restart and discover the new driver
        try await Task.sleep(nanoseconds: 1_500_000_000)
        refresh()
    }

    func readMinVolumeDB() -> Float {
        let boxID = getBoxID(for: proxyBoxUID)
        guard boxID != 0 else { return -45.0 }
        
        // Identify ourselves as the configurator
        _ = setIdentifyValue(boxID: boxID, value: getpid())
        
        // Request the minVolumeDB configuration type (-6)
        _ = setIdentifyValue(boxID: boxID, value: -6)
        
        if let valStr = getBoxObjectName(boxID: boxID),
           let val = Float(valStr.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return val
        }
        return -45.0
    }

    func setMinVolumeDB(_ value: Float) {
        let boxID = getBoxID(for: proxyBoxUID)
        guard boxID != 0 else { return }
        
        // Identify ourselves as the configurator
        _ = setIdentifyValue(boxID: boxID, value: getpid())
        
        // Set minVolumeDB
        _ = setBoxObjectName(boxID: boxID, name: "minVolumeDB=\(value)")
        
        minVolumeDB = value
        refresh()
    }
}
