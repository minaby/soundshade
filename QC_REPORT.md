# SoundShade QC — 2026-10-01

Reviewed commit: `132386c`.

## Fix status

All five findings below have been addressed in the working tree. Packaging now fails fast and uses the release bin path reported by SwiftPM. Flyout placement checks the visible screen frame. Display visibility uses disabled UUIDs, migrating the old name preference for currently connected displays; previously disconnected displays are enabled by default when next connected. Proxy configuration failures retain the current default route. Mute checks property writability and write status and reads back actual state; unsupported mute leaves the slider usable.

Validation after edits: Bash syntax check and a mocked `swift build` failure (exit 42) passed; the script stopped before version stamping/packaging. `git diff --check` passed. Swift compilation and macOS runtime checks remain pending. The build script stamps the source plist version when you build on Mac.

## Scope and results

Source and packaging review on Windows. No Swift executable or macOS SDK is available here, so compilation, UI execution, CoreAudio behavior, signing, and hardware DDC tests remain unverified. Both tracked plist files parse as XML. All five resources declared in Package.swift exist. `git diff --check` passed before this report was added. No test target or automated test suite is present.

## Findings

1. **P1 — Failed builds can be reported as successful** (`build_app.sh:38`). The script has no fail-fast setting and does not check `swift build`'s exit status. It proceeds to stamp the version and package even if compilation fails. With a previous release executable present it can package stale code under a new version; without one, copy failures still lead to the final success message. Stop on failed commands and require the executable and release resource bundle to exist. Resource discovery at line 84 also chooses the first bundle anywhere under `.build`, which can pick a debug/stale bundle instead of the current release output.

2. **P2 — Multi-monitor flyout can appear outside the screen** (`Sources/SoundShade/MenuBarController.swift:356`). The flyout always starts at `mainFrame.maxX - 2` and never checks screen bounds or opens to the left. With the menu-bar icon near the right edge, most of the flyout can be off-screen and its choices inaccessible. Select the opening direction based on available room and clamp both axes to the screen's visible frame.

3. **P2 — Identical monitor models cannot be enabled independently** (`Sources/SoundShade/Views/PreferencesView.swift:184`, `Sources/SoundShade/Engines/BrightnessEngine.swift:155`). Visibility is stored and filtered by `display.name`. Two monitors with the same name share a preference; disabling one disables both. Once a list is saved, a newly connected monitor with a different name is also hidden by default. Store disabled display UUIDs, with migration from the existing preference.

4. **P2 — Proxy routing proceeds after target configuration fails** (`Sources/SoundShade/Engines/AudioEngine.swift:126`, `:538`). `configureProxyDevice` returns no result, silently returns if the box is missing, and discards both configuration write results. The caller nevertheless switches the default output to the proxy. A failed target update can leave audio routed to the previous target or unavailable. Return and check configuration success before changing either default output; display an error or retain the existing route.

5. **P2 — Mute UI can claim success without muting audio** (`Sources/SoundShade/Engines/AudioEngine.swift:183`). `setDeviceMuted` returns immediately when the mute property is absent and ignores the write status when it exists. `setMuted` always changes `isMuted`, and the panel then disables the volume slider. On an output with volume support but no writable master mute property, audio keeps playing while the UI says muted. Check writability and status; only publish confirmed state, or implement an appropriate volume-based mute fallback.

These findings follow directly from code paths; their observed hardware/UI behavior has not been reproduced on macOS here.

## Remaining Mac checks

- Clean release build and package verification; force a compilation failure and confirm a nonzero script exit without a success message.
- Install from `/Applications`; verify signatures and packaged resources.
- External HDMI/DP audio through the proxy, target switching, bypass, mute, and reconnect.
- Bluetooth volume/mute, including changing output in System Settings while the panel is open.
- Brightness on two identical monitors; DDC disabled, unplug/replug, sleep/wake, and rapid slider changes.
- Multi-monitor flyout near each screen edge; mirror/extended transitions and relaunch while mirrored.
- Start at login and driver installation cancellation/failure/recovery.
