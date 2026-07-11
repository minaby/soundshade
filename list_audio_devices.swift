import Foundation
import CoreAudio

// Get the list of all audio device IDs
func getAudioDevices() -> [AudioObjectID] {
    var propertyAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    
    var dataSize: UInt32 = 0
    var status = AudioObjectGetPropertyDataSize(
        AudioObjectID(kAudioObjectSystemObject),
        &propertyAddress,
        0,
        nil,
        &dataSize
    )
    
    guard status == noErr else {
        print("Error getting device data size: \(status)")
        return []
    }
    
    let deviceCount = Int(dataSize) / MemoryLayout<AudioObjectID>.size
    var deviceIDs = [AudioObjectID](repeating: 0, count: deviceCount)
    
    status = AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &propertyAddress,
        0,
        nil,
        &dataSize,
        &deviceIDs
    )
    
    guard status == noErr else {
        print("Error getting device IDs list: \(status)")
        return []
    }
    
    return deviceIDs
}

// Get the name of the audio device
func getDeviceName(deviceID: AudioObjectID) -> String {
    var propertyAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceNameCFString,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    
    var deviceName: Unmanaged<CFString>?
    var dataSize = UInt32(MemoryLayout<CFString?>.size)
    
    let status = AudioObjectGetPropertyData(
        deviceID,
        &propertyAddress,
        0,
        nil,
        &dataSize,
        &deviceName
    )
    
    if status == noErr, let name = deviceName?.takeRetainedValue() {
        return name as String
    }
    
    return "Unknown Device"
}

// Get the unique UID of the audio device
func getDeviceUID(deviceID: AudioObjectID) -> String {
    var propertyAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceUID,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    
    var deviceUID: Unmanaged<CFString>?
    var dataSize = UInt32(MemoryLayout<CFString?>.size)
    
    let status = AudioObjectGetPropertyData(
        deviceID,
        &propertyAddress,
        0,
        nil,
        &dataSize,
        &deviceUID
    )
    
    if status == noErr, let uid = deviceUID?.takeRetainedValue() {
        return uid as String
    }
    
    return "No UID"
}

// Check if the device has an output channel (audio output)
func isOutputDevice(deviceID: AudioObjectID) -> Bool {
    var propertyAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyStreams,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )
    
    var dataSize: UInt32 = 0
    let status = AudioObjectGetPropertyDataSize(
        deviceID,
        &propertyAddress,
        0,
        nil,
        &dataSize
    )
    
    if status == noErr && dataSize > 0 {
        return true
    }
    return false
}

// Get the ID of the current default output device
func getDefaultOutputDevice() -> AudioObjectID {
    var propertyAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    
    var defaultDeviceID = AudioObjectID(0)
    var dataSize = UInt32(MemoryLayout<AudioObjectID>.size)
    
    let status = AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &propertyAddress,
        0,
        nil,
        &dataSize,
        &defaultDeviceID
    )
    
    if status == noErr {
        return defaultDeviceID
    }
    return 0
}

// Get the ID of the current default system output device
func getDefaultSystemOutputDevice() -> AudioObjectID {
    var propertyAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    
    var defaultDeviceID = AudioObjectID(0)
    var dataSize = UInt32(MemoryLayout<AudioObjectID>.size)
    
    let status = AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &propertyAddress,
        0,
        nil,
        &dataSize,
        &defaultDeviceID
    )
    
    if status == noErr {
        return defaultDeviceID
    }
    return 0
}

// MAIN PROGRAM
let devices = getAudioDevices()
let defaultOut = getDefaultOutputDevice()
let defaultSystemOut = getDefaultSystemOutputDevice()

print("==================================================")
print("              SOUNDSHADE AUDIO PORT TEST           ")
print("==================================================")
print("Current default output device (ID: \(defaultOut)): \(getDeviceName(deviceID: defaultOut))")
print("Default system sound device (ID: \(defaultSystemOut)): \(getDeviceName(deviceID: defaultSystemOut))")
print("--------------------------------------------------")
print("List of available output devices:")

for device in devices {
    if isOutputDevice(deviceID: device) {
        let name = getDeviceName(deviceID: device)
        let uid = getDeviceUID(deviceID: device)
        let isDefault = (device == defaultOut) ? " [Selected]" : ""
        print("- \(name) (ID: \(device))\(isDefault)")
        print("  UID: \(uid)")
    }
}
print("==================================================")
