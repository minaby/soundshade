import Foundation
import CoreAudio

// Lấy danh sách tất cả các ID của thiết bị âm thanh
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
        print("Lỗi khi lấy kích thước dữ liệu thiết bị: \(status)")
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
        print("Lỗi khi lấy danh sách ID thiết bị: \(status)")
        return []
    }
    
    return deviceIDs
}

// Lấy tên của thiết bị âm thanh
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
    
    return "Thiết bị không xác định"
}

// Lấy mã UID duy nhất của thiết bị âm thanh
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
    
    return "Không có UID"
}

// Kiểm tra xem thiết bị có kênh Output (đầu ra âm thanh) không
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

// Lấy ID của thiết bị đầu ra mặc định hiện tại
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

// CHƯƠNG TRÌNH CHÍNH
let devices = getAudioDevices()
let defaultOut = getDefaultOutputDevice()

print("==================================================")
print("              SOUNDSHADE AUDIO PORT TEST           ")
print("==================================================")
print("Thiết bị ra mặc định hiện tại (ID: \(defaultOut)): \(getDeviceName(deviceID: defaultOut))")
print("--------------------------------------------------")
print("Danh sách các thiết bị Output khả dụng:")

for device in devices {
    if isOutputDevice(deviceID: device) {
        let name = getDeviceName(deviceID: device)
        let uid = getDeviceUID(deviceID: device)
        let isDefault = (device == defaultOut) ? " [Đang chọn]" : ""
        print("- \(name) (ID: \(device))\(isDefault)")
        print("  UID: \(uid)")
    }
}
print("==================================================")
