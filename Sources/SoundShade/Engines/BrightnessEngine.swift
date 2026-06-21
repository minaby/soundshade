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

    private var m1ddcPath: String? {
        Bundle.module.url(forResource: "m1ddc", withExtension: nil)?.path
            ?? Bundle.main.url(forResource: "m1ddc", withExtension: nil)?.path
    }

    init() {
        refresh()
    }

    // MARK: - Public API

    func refresh() {
        enumerateDisplays()
        isAvailable = m1ddcPath != nil && displays.contains(where: { !$0.isBuiltIn })
        if isAvailable, let current = selectedDisplay {
            brightness = fetchBrightness(for: current)
        }
    }

    func selectDisplay(_ display: ConnectedDisplay) {
        selectedDisplayID = display.id
        displays = displays.map {
            var d = $0
            d.isSelected = (d.id == display.id)
            return d
        }
        brightness = fetchBrightness(for: display)
    }

    func setBrightness(_ value: Double) {
        guard isAvailable, let display = selectedDisplay, !display.isBuiltIn else { return }
        brightness = max(0, min(1, value))
        let level = Int(brightness * Double(maxLuminance - minLuminance)) + minLuminance
        runM1DDC(args: ["display", display.m1ddcSpecifier, "set", "luminance", "\(level)"])
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

    private func fetchBrightness(for display: ConnectedDisplay) -> Double {
        guard !display.isBuiltIn else { return 0.5 }
        guard let output = runM1DDC(args: ["display", display.m1ddcSpecifier, "get", "luminance"]),
              let value = Int(output.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return 0.5
        }
        return Double(value - minLuminance) / Double(maxLuminance - minLuminance)
    }

    @discardableResult
    private func runM1DDC(args: [String]) -> String? {
        guard let path = m1ddcPath else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}
