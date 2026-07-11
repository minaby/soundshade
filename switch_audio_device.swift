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
    
    guard status == noErr else { return [] }
    
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
    
    return status == noErr ? deviceIDs : []
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

// Check if the device is an output device
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
    return status == noErr && dataSize > 0
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
    return status == noErr ? defaultDeviceID : 0
}

// Set the default output device to the specified ID
func setDefaultOutputDevice(deviceID: AudioObjectID) -> Bool {
    var propertyAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    
    var device = deviceID
    let dataSize = UInt32(MemoryLayout<AudioObjectID>.size)
    
    let status = AudioObjectSetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &propertyAddress,
        0,
        nil,
        dataSize,
        &device
    )
    
    return status == noErr
}

// Set the default system sound effects device to the specified ID
func setDefaultSystemOutputDevice(deviceID: AudioObjectID) -> Bool {
    var propertyAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    
    var device = deviceID
    let dataSize = UInt32(MemoryLayout<AudioObjectID>.size)
    
    let status = AudioObjectSetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &propertyAddress,
        0,
        nil,
        dataSize,
        &device
    )
    
    return status == noErr
}

// MAIN PROGRAM
let args = CommandLine.arguments

if args.count < 2 {
    let defaultOut = getDefaultOutputDevice()
    print("==================================================")
    print("      SOUNDSHADE OUTPUT DEVICE SWITCHER           ")
    print("==================================================")
    print("Current default device: \(getDeviceName(deviceID: defaultOut)) (ID: \(defaultOut))")
    print("--------------------------------------------------")
    print("Please run the command with the device ID you want to switch to.")
    print("Example: swift switch_audio_device.swift <ID>")
    print("Available device IDs:")
    
    let devices = getAudioDevices()
    for device in devices {
        if isOutputDevice(deviceID: device) {
            let name = getDeviceName(deviceID: device)
            let isCurrent = (device == defaultOut) ? " [Selected]" : ""
            print("- ID: \(device) -> \(name)\(isCurrent)")
        }
    }
    print("==================================================")
} else {
    guard let targetID = UInt32(args[1]) else {
        print("Error: Invalid device ID (must be an integer).")
        exit(1)
    }
    
    let devices = getAudioDevices()
    guard devices.contains(targetID) && isOutputDevice(deviceID: targetID) else {
        print("Error: No output device found with ID \(targetID).")
        exit(1)
    }
    
    let currentName = getDeviceName(deviceID: getDefaultOutputDevice())
    let targetName = getDeviceName(deviceID: targetID)
    
    print("Switching audio playback device:")
    print("From: \(currentName)")
    print("To: \(targetName)")
    
    let success = setDefaultOutputDevice(deviceID: targetID)
    if success {
        _ = setDefaultSystemOutputDevice(deviceID: targetID)
        print("🎉 SUCCESS! Switched to: \(targetName)")
    } else {
        print("❌ FAILED! System error switching device.")
    }
}
