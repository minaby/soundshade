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

// Kiểm tra xem thiết bị có phải đầu ra (Output) không
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
    return status == noErr ? defaultDeviceID : 0
}

// Chuyển thiết bị đầu ra mặc định sang ID được chỉ định
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

// CHƯƠNG TRÌNH CHÍNH
let args = CommandLine.arguments

if args.count < 2 {
    let defaultOut = getDefaultOutputDevice()
    print("==================================================")
    print("      SOUNDSHADE OUTPUT DEVICE SWITCHER           ")
    print("==================================================")
    print("Thiết bị mặc định hiện tại: \(getDeviceName(deviceID: defaultOut)) (ID: \(defaultOut))")
    print("--------------------------------------------------")
    print("Hãy chạy lệnh kèm theo ID thiết bị muốn chuyển.")
    print("Ví dụ: swift switch_audio_device.swift <ID>")
    print("Danh sách ID khả dụng:")
    
    let devices = getAudioDevices()
    for device in devices {
        if isOutputDevice(deviceID: device) {
            let name = getDeviceName(deviceID: device)
            let isCurrent = (device == defaultOut) ? " [Đang chọn]" : ""
            print("- ID: \(device) -> \(name)\(isCurrent)")
        }
    }
    print("==================================================")
} else {
    guard let targetID = UInt32(args[1]) else {
        print("Lỗi: ID thiết bị không hợp lệ (phải là số nguyên).")
        exit(1)
    }
    
    let devices = getAudioDevices()
    guard devices.contains(targetID) && isOutputDevice(deviceID: targetID) else {
        print("Lỗi: Không tìm thấy thiết bị output nào có ID là \(targetID).")
        exit(1)
    }
    
    let currentName = getDeviceName(deviceID: getDefaultOutputDevice())
    let targetName = getDeviceName(deviceID: targetID)
    
    print("Đang chuyển đổi thiết bị phát âm thanh:")
    print("Từ: \(currentName)")
    print("Sang: \(targetName)")
    
    let success = setDefaultOutputDevice(deviceID: targetID)
    if success {
        print("🎉 THÀNH CÔNG! Đã chuyển sang: \(targetName)")
    } else {
        print("❌ THẤT BẠI! Lỗi hệ thống khi chuyển thiết bị.")
    }
}
