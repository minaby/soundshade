# SoundShade - macOS Utility

**SoundShade** là một ứng dụng Menu Bar gọn nhẹ dành riêng cho macOS, giúp người dùng dễ dàng điều chỉnh âm lượng (volume), độ sáng (brightness) của màn hình ngoài (HDMI/DisplayPort) và chuyển đổi nhanh các thiết bị đầu ra âm thanh (Audio Output Devices) một cách mượt mà và trực quan.

Đặc biệt, ứng dụng được thiết kế tối ưu để **tránh hoàn toàn các lỗi xung đột âm thanh, lẹt đẹt hay nấc tiếng (audio clipping/crackling)** khi người dùng kết nối với tai nghe Bluetooth (như AirPods) - một lỗi rất phổ biến ở các ứng dụng điều khiển âm thanh hệ thống hiện nay như eqMac.

---

## 1. Thiết kế kỹ thuật thực tế (Phù hợp với M4 Mac mini & Dell U2723QE)

Qua thử nghiệm thực tế trên máy M4 Mac mini kết nối màn hình Dell U2723QE, dự án đã xác định các phương án kỹ thuật tối ưu như sau:

*   **🔆 Điều chỉnh Độ sáng (External Brightness):**
    *   **Giải pháp:** Sử dụng **DDC/CI phần cứng** qua cổng kết nối USB-C/DP. 
    *   **Hiện trạng thử nghiệm:** Đã kiểm chứng thành công bằng lệnh `m1ddc display 1 set luminance <value>`. Màn hình Dell phản hồi thay đổi độ sáng vật lý trực tiếp.
*   **🔊 Điều chỉnh Âm lượng (Volume):**
    *   **Giải pháp:** Sử dụng **Driver âm thanh ảo (Software Attenuation)**.
    *   **Lý do:** Màn hình Dell U2723QE không hỗ trợ chỉnh âm lượng của cổng Line-Out 3.5mm bằng phần cứng qua DDC/CI (luôn cố định ở 100%). Vì vậy, ứng dụng sẽ nhân giảm biên độ âm thanh số trên Mac trước khi phát qua HDMI/DP/USB-C.
*   **🔌 Trình chuyển đổi Thiết bị phát (Audio Output Switcher):**
    *   **Giải pháp:** Sử dụng API `CoreAudio` mặc định để chuyển đổi nhanh thiết bị mặc định.
    *   **Hiện trạng thử nghiệm:** Đã kiểm chứng thành công bằng file script [switch_audio_device.swift](file:///Users/dzcat/Library/CloudStorage/Dropbox/Works/www/tools/soundshade/switch_audio_device.swift).
*   **🛡️ Cơ chế Bypass AirPods/Bluetooth thông minh (Smart Bypass):**
    *   Khi phát hiện thiết bị phát mặc định là AirPods hoặc thiết bị Bluetooth, SoundShade sẽ **bỏ qua (bypass) hoàn toàn** luồng xử lý phần mềm của mình và nhường quyền kiểm soát âm lượng gốc cho macOS, loại bỏ triệt để lỗi xung đột và nấc tiếng.

---

## 2. Các file script thử nghiệm hiện có trong thư mục

*   [list_audio_devices.swift](file:///Users/dzcat/Library/CloudStorage/Dropbox/Works/www/tools/soundshade/list_audio_devices.swift): Liệt kê danh sách tất cả các thiết bị đầu ra âm thanh đang kết nối và ID tương ứng của chúng.
*   [switch_audio_device.swift](file:///Users/dzcat/Library/CloudStorage/Dropbox/Works/www/tools/soundshade/switch_audio_device.swift): Lệnh chuyển đổi thiết bị phát âm thanh mặc định qua Terminal bằng cách truyền ID (ví dụ: `swift switch_audio_device.swift 55`).

---

## 3. Lộ trình phát triển tiếp theo

### Giai đoạn 1: Xây dựng Driver âm thanh ảo tối giản
*   Tạo một HAL Audio Plugin (`AudioServerPlugIn`) tối giản để làm nhiệm vụ đón nhận và điều chỉnh biên độ âm thanh (Software volume control) cho cổng HDMI/DP.
*   Đảm bảo driver này tự động gán nhãn trùng tên với màn hình ngoài được kết nối.

### Giai đoạn 2: Thiết kế giao diện SwiftUI Menu Bar
*   Thiết kế giao diện bảng điều khiển (Control Panel) dạng kính mờ (Glassmorphic) trên thanh Menu Bar.
*   Tích hợp thanh trượt chỉnh độ sáng (gọi lệnh DDC/CI I2C) và âm lượng (giao tiếp với Driver ảo).

### Giai đoạn 3: Đóng gói và Xử lý Quyền hệ thống (System Entitlements)
*   Đăng ký phím nóng bàn phím (F11/F12 cho âm lượng, F1/F2 cho độ sáng) qua Accessibility API.
*   Đóng gói ứng dụng thành file cài đặt `.dmg`.
