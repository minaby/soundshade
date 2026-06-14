import Foundation
import CoreAudio

// MARK: - Audio Device Model

struct AudioDevice: Identifiable, Equatable {
    let id: AudioObjectID
    let name: String
    let uid: String
    let transportType: UInt32

    var isDefault: Bool = false

    var isBluetooth: Bool {
        // kAudioDeviceTransportTypeBluetooth = 0x'0005'
        // kAudioDeviceTransportTypeBluetoothLE = 0x'0006'
        transportType == kAudioDeviceTransportTypeBluetooth ||
        transportType == kAudioDeviceTransportTypeBluetoothLE
    }

    var isBuiltIn: Bool {
        transportType == kAudioDeviceTransportTypeBuiltIn
    }

    var icon: String {
        if isBluetooth { return "airpodspro" }
        let lower = name.lowercased()
        if lower.contains("airpods") { return "airpodspro" }
        if lower.contains("macbook") || lower.contains("built-in") || lower.contains("speakers") {
            return "laptopspeaker"
        }
        if lower.contains("headphone") || lower.contains("earphone") {
            return "headphones"
        }
        if lower.contains("dell") || lower.contains("display") || lower.contains("monitor") {
            return "display"
        }
        if lower.contains("usb") { return "cable.connector" }
        if lower.contains("hdmi") { return "cable.connector.horizontal" }
        return "speaker.wave.2"
    }
}
