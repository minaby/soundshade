import Foundation
import AppKit
import CoreGraphics

// MARK: - Connected Display Model

struct ConnectedDisplay: Identifiable, Equatable {
    let id: CGDirectDisplayID
    let name: String
    let isBuiltIn: Bool
    var isSelected: Bool = false

    var icon: String {
        if isBuiltIn { return "laptopcomputer" }
        let lower = name.lowercased()
        if lower.contains("dell") || lower.contains("u27") { return "display" }
        if lower.contains("lg") || lower.contains("samsung") || lower.contains("asus") { return "display" }
        return "display.2"
    }

    // m1ddc display index (1-based, based on position in non-builtin list)
    var m1ddcIndex: Int = 1
}
