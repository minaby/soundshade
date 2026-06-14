# SoundShade

**SoundShade** is a lightweight macOS Menu Bar utility designed to control display brightness and volume for external monitors (HDMI/DisplayPort/USB-C) and easily switch audio output devices.

It is designed to solve a very common issue on macOS where external monitors do not allow native volume slider adjustments over the display connection. Additionally, it implements a **Smart Bluetooth Bypass** to completely avoid the audio crackling/clipping issues common in general-purpose software volume adjusters (like eqMac) when Bluetooth devices (like AirPods) are connected.

---

## System Requirements

* **Operating System**: macOS 13.0 (Ventura) or newer.
  * *On older OS versions:* The app declares `LSMinimumSystemVersion = 13.0` in its metadata. Running the app on macOS 12 (Monterey) or older will trigger a native macOS dialog stating that the app is incompatible and refuse to launch.
  * *Why macOS 13+?* SoundShade leverages the modern `ServiceManagement` (`SMAppService`) APIs to manage "Start at login" without legacy helper daemons, alongside layout improvements introduced in SwiftUI for macOS 13.
* **Hardware**: Optimized for Apple Silicon Macs (M1/M2/M3/M4). 

---

## Key Features

1. **🔆 Display Brightness Control**:
   - Sends DDC/CI commands directly to connected external displays to adjust their hardware luminance.
   - Verified on Apple Silicon (M1/M2/M3/M4) devices.

2. **🔊 External Monitor Volume Control (Software Attenuation)**:
   - Since many monitors (like the DELL U2723QE) lock their Line-Out port volume to 100% and ignore DDC volume commands, SoundShade intercepts and attenuates the audio stream digitally on your Mac before sending it over the cable.
   - Utilizes a custom, lightweight CoreAudio HAL virtual driver (`ProxyAudioDevice`).

3. **🎧 Smart Bluetooth Bypass**:
   - When outputting to AirPods or Bluetooth headphones, SoundShade completely bypasses the virtual driver and lets macOS route audio natively. This prevents audio dropouts, distortion, and latency bugs.

4. **⚙️ Preferences & Configuration Checklist**:
   - A beautiful settings panel to select which displays and audio outputs are visible.
   - Adjust the **Low-volume sensitivity** (from `-60 dB` to `-20 dB`) with a clickable popover explaining the feature.
   - Toggle **Start at Login** (utilizing macOS `ServiceManagement` API).
   - Dynamically resizes based on the number of connected devices to prevent interface clipping.

---

## Installation & Setup

### 1. Download & Move to Applications
1. Download the compiled `SoundShade.app` (or download the source and build it).
2. **Important:** Drag `SoundShade.app` into your `/Applications/` folder. This is required for macOS permissions, login item registration, and helper scripts to function.

### 2. Bypass Gatekeeper Warning
Since this app is distributed independently:
1. Right-click (or Control-click) `SoundShade.app` in `/Applications/`.
2. Select **Open** from the menu.
3. Click **Open** on the macOS security dialog.
*This standard security step is only required on the first launch.*

### 3. Install the Virtual Audio Driver (Required for External Screen Volume)
1. Click the **SoundShade** icon in your Menu Bar and select **Preferences...**
2. Click **Install driver** at the bottom of the window.
3. Enter your macOS administrator password when prompted.
4. SoundShade will copy the driver to `/Library/Audio/Plug-Ins/HAL/` and restart the coreaudiod service automatically.
*If the installation fails, a diagnostic alert will show up advising you to check permissions or verify that the app runs from `/Applications/`.*

---

## Troubleshooting

### Q: Changing the volume slider has no effect on my external monitor.
Make sure you select the target monitor output name in the SoundShade popover list. SoundShade only intercepts and scales the audio signal when routing through the virtual audio driver.

### Q: Brightness control is not working.
Ensure **DDC/CI** is enabled in your monitor's built-in OSD (On-Screen Display) menu. Some monitors disable this feature by default.

---

## Building from Source

To compile and package the app manually:
1. Clone the repository.
2. Run the build script:
   ```bash
   ./build_app.sh
   ```
3. Copy the compiled bundle to `/Applications/`:
   ```bash
   cp -R SoundShade.app /Applications/
   ```

---

## License & Copyleft

This project is open-source and released under the **GNU General Public License v3.0 (GPLv3)**. See the [LICENSE](LICENSE) file for the full license text.
