import Foundation
import AppKit
import CoreGraphics
import ApplicationServices

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

    // m1ddc display index (1-based, based on position in non-builtin list).
    // Kept only as a fallback; prefer `uuid` for addressing m1ddc since its
    // positional ordering is unrelated to NSScreen ordering and changes across
    // sleep/wake and reconnects.
    var m1ddcIndex: Int = 1

    // Stable system UUID for this display, derived from its CGDirectDisplayID.
    // m1ddc accepts this directly (`display <uuid> ...`) and it does not depend
    // on enumeration order, so it survives sleep/wake and monitor switching.
    var uuid: String? = nil

    // The argument passed to m1ddc's `display` command. Uses the stable UUID when
    // available; falls back to the legacy positional index only if UUID lookup failed.
    var m1ddcSpecifier: String {
        if let uuid, !uuid.isEmpty { return uuid }
        return "\(m1ddcIndex)"
    }
}

extension ConnectedDisplay {
    static func systemUUID(for displayID: CGDirectDisplayID) -> String? {
        guard let ref = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else {
            return nil
        }
        return CFUUIDCreateString(nil, ref) as String?
    }
}
