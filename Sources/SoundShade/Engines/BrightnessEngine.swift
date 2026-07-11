//
//  BrightnessEngine.swift
//  SoundShade
//
//  Created by Dizzy (minaby.com).
//  Licensed under GNU GPLv3.
//
//  This file acts as a wrapper around the "m1ddc" command-line utility (https://github.com/jakehilborn/m1ddc)
//  created by Jake Hilborn, which utilizes DDC/CI commands to adjust external screen brightness on Apple Silicon.
//  The precompiled m1ddc executable is bundled within the application resources.
//

import Foundation
import AppKit
import CoreGraphics

// MARK: - Brightness Engine

@MainActor
final class BrightnessEngine: ObservableObject {
    static let shared = BrightnessEngine()

    @Published var displays: [ConnectedDisplay] = []
    @Published var allDisplays: [ConnectedDisplay] = []
    @Published var selectedDisplayID: CGDirectDisplayID = 0
    @Published var brightness: Double = 0.5
    @Published var isAvailable: Bool = false

    private let minLuminance: Int = 0
    private let maxLuminance: Int = 100

    nonisolated private var m1ddcPath: String? {
        Bundle.appResources.url(forResource: "m1ddc", withExtension: nil)?.path
            ?? Bundle.main.url(forResource: "m1ddc", withExtension: nil)?.path
    }

    // Coalesces rapid slider drags into a single DDC write instead of spawning
    // an m1ddc process per tick.
    private var pendingBrightnessWrite: DispatchWorkItem?

    init() {
        refresh()
    }

    // MARK: - Public API

    func refresh() {
        enumerateDisplays()
        isAvailable = m1ddcPath != nil && displays.contains(where: { !$0.isBuiltIn })
        if isAvailable, let current = selectedDisplay {
            applyKnownOrFetchBrightness(for: current)
        }
    }

    func selectDisplay(_ display: ConnectedDisplay) {
        selectedDisplayID = display.id
        displays = displays.map {
            var d = $0
            d.isSelected = (d.id == display.id)
            return d
        }
        applyKnownOrFetchBrightness(for: display)
    }

    func setBrightness(_ value: Double) {
        guard isAvailable, let display = selectedDisplay, !display.isBuiltIn else { return }
        brightness = max(0, min(1, value))
        setCachedBrightness(brightness, for: display)

        // The actual DDC write is debounced and dispatched off-thread: a display
        // right after a mirror/reconfigure can stall its DDC channel for seconds,
        // and firing one process per drag tick would otherwise queue up a pile
        // of blocked m1ddc processes.
        let level = Int(brightness * Double(maxLuminance - minLuminance)) + minLuminance
        let specifier = display.m1ddcSpecifier
        pendingBrightnessWrite?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { await self?.runM1DDC(args: ["display", specifier, "set", "luminance", "\(level)"]) }
        }
        pendingBrightnessWrite = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: workItem)
    }

    // Shows a cached value immediately (synchronous, no hardware round-trip);
    // only reaches for the device over DDC in the background if we've never
    // seen a value for it before, so the UI never blocks on a stalled display.
    private func applyKnownOrFetchBrightness(for display: ConnectedDisplay) {
        if let cached = cachedBrightness(for: display) {
            brightness = cached
            return
        }
        brightness = 0.5
        Task {
            let fetched = await fetchBrightness(for: display)
            if selectedDisplay?.id == display.id {
                brightness = fetched
            }
        }
    }

    var selectedDisplay: ConnectedDisplay? {
        displays.first { $0.id == selectedDisplayID }
            ?? displays.first { !$0.isBuiltIn }
            ?? displays.first
    }

    var externalDisplays: [ConnectedDisplay] {
        displays.filter { !$0.isBuiltIn }
    }

    // MARK: - Display Enumeration

    private func enumerateDisplays() {
        let screens = NSScreen.screens
        var externalIndex = 1  // m1ddc uses 1-based index for external displays

        let newDisplays: [ConnectedDisplay] = screens.compactMap { screen in
            guard let idNum = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            let displayID = CGDirectDisplayID(idNum.uint32Value)
            let isBuiltIn = CGDisplayIsBuiltin(displayID) != 0
            let name = screen.localizedName

            var display = ConnectedDisplay(
                id: displayID,
                name: name,
                isBuiltIn: isBuiltIn,
                isSelected: (displayID == selectedDisplayID)
            )
            display.uuid = ConnectedDisplay.systemUUID(for: displayID)

            if !isBuiltIn {
                display.m1ddcIndex = externalIndex
                externalIndex += 1
            }

            return display
        }

        allDisplays = newDisplays

        let enabledNames = UserDefaults.standard.stringArray(forKey: "enabledDisplayNames")
        let hasSavedEnabled = enabledNames != nil
        let actualEnabledNames = enabledNames ?? []

        displays = newDisplays.filter { !hasSavedEnabled || actualEnabledNames.contains($0.name) }

        // Auto-select first external display if no selection or selection gone
        if selectedDisplayID == 0 || !displays.contains(where: { $0.id == selectedDisplayID }) {
            if let ext = displays.first(where: { !$0.isBuiltIn }) {
                selectedDisplayID = ext.id
            } else if let first = displays.first {
                selectedDisplayID = first.id
            }
        }

        // Keep selection sync'd in both lists
        displays = displays.map {
            var d = $0
            d.isSelected = (d.id == selectedDisplayID)
            return d
        }

        allDisplays = allDisplays.map {
            var d = $0
            d.isSelected = (d.id == selectedDisplayID)
            return d
        }
    }

    // MARK: - m1ddc Helpers

    // Some monitors' DDC firmware reports a bogus "get luminance" value (seen
    // returning 0 regardless of actual brightness on a DELL U2520D) even though
    // "set luminance" applies correctly. So once we know the value we set
    // ourselves, trust that over the device's GET response — only fall back to
    // querying the device for a display we've never adjusted yet.
    private static let brightnessCacheKey = "cachedBrightnessByDisplayUUID"

    private func cachedBrightness(for display: ConnectedDisplay) -> Double? {
        guard let uuid = display.uuid else { return nil }
        let cache = UserDefaults.standard.dictionary(forKey: Self.brightnessCacheKey) as? [String: Double]
        return cache?[uuid]
    }

    private func setCachedBrightness(_ value: Double, for display: ConnectedDisplay) {
        guard let uuid = display.uuid else { return }
        var cache = UserDefaults.standard.dictionary(forKey: Self.brightnessCacheKey) as? [String: Double] ?? [:]
        cache[uuid] = value
        UserDefaults.standard.set(cache, forKey: Self.brightnessCacheKey)
    }

    private func fetchBrightness(for display: ConnectedDisplay) async -> Double {
        guard !display.isBuiltIn else { return 0.5 }
        if let cached = cachedBrightness(for: display) { return cached }
        guard let output = await runM1DDC(args: ["display", display.m1ddcSpecifier, "get", "luminance"]),
              let value = Int(output.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return 0.5
        }
        let fetched = Double(value - minLuminance) / Double(maxLuminance - minLuminance)
        setCachedBrightness(fetched, for: display)
        return fetched
    }

    // Runs m1ddc off the main thread with a hard timeout. DDC/I2C calls can
    // stall for seconds — or hang outright — right after a display
    // reconfiguration (e.g. toggling mirroring), so this must never be called
    // synchronously from the main actor.
    @discardableResult
    nonisolated private func runM1DDC(args: [String]) async -> String? {
        guard let path = m1ddcPath else { return nil }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = args
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = Pipe()

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: nil)
                    return
                }

                let timeoutWorkItem = DispatchWorkItem {
                    if process.isRunning { process.terminate() }
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + 2.0, execute: timeoutWorkItem)

                // Drain the pipe before waiting on exit — reading after
                // waitUntilExit() can deadlock if the child fills the pipe
                // buffer before the parent starts reading it.
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                timeoutWorkItem.cancel()

                continuation.resume(returning: String(data: data, encoding: .utf8))
            }
        }
    }
}
