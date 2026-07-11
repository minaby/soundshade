import Foundation
import AppKit
import CoreGraphics

// MARK: - Display Mode Engine
//
// Implements a Windows-style "Extended / Show only on X" toggle, which macOS
// has no equivalent setting for. Collapsing to a single display mirrors every
// other display onto the chosen one (CGConfigureDisplayMirrorOfDisplay), which
// merges them into a single logical desktop — the mouse/windows can no longer
// move onto the mirrored screens and Mission Control treats it as one space.
//
// Deliberately NOT powering off the mirrored displays' backlights: DDC standby
// (VCP 0xD6) wake is unreliable on at least one tested monitor (DELL U2723QE) —
// `set standby 1` reports success but doesn't always re-light the panel,
// requiring the physical power button. The "true software disconnect" used by
// tools like BetterDisplay turned out to require a private SkyLight entitlement
// (com.apple.private.SkyLight.displaypowercontrol) that only Apple can sign —
// third-party use gets SIGKILL'd by AMFI. So mirroring is the full mechanism
// here: the secondary display stays lit showing a duplicate of the chosen one,
// but switching is 100% reliable in both directions since it's all public API.

@MainActor
final class DisplayModeEngine: ObservableObject {
    static let shared = DisplayModeEngine()

    enum Mode: Equatable {
        case extended
        case single(CGDirectDisplayID)
    }

    @Published private(set) var mode: Mode = .extended
    @Published private(set) var displays: [ConnectedDisplay] = []

    // All identity tracking below is keyed by stable system UUID, not
    // CGDirectDisplayID: macOS does not guarantee a display's ID stays the
    // same across sleep/wake or a reconfiguration event (the same issue
    // BrightnessEngine/m1ddc already works around — see ConnectedDisplay.uuid).
    // Tracking raw IDs here previously meant refresh() could conclude a
    // still-connected target had "disconnected" after an ID reassignment,
    // silently resetting local state to Extended WITHOUT actually un-mirroring
    // anything — the displays stayed physically mirrored but the UI lost the
    // "Multi-monitor" row (and with it, any way back to Extended). CG calls
    // still need a live CGDirectDisplayID, so we resolve UUID -> current ID at
    // the point we actually call into CoreGraphics.
    private var collapsedTargetUUID: String?
    private var mirroredDisplayUUIDs: Set<String> = []

    // Original origins of every display before we collapsed to single-display
    // mode, so extended arrangement (and Main Display) can be restored exactly.
    // Saving this matters because the menu bar only ever renders on whichever
    // display sits at origin (0,0) — mirroring alone does NOT move the menu bar
    // onto the chosen display, so without forcing its origin to (0,0) the status
    // bar item can end up rendered onto a display the user can no longer see.
    private var originalOriginsByUUID: [String: CGPoint] = [:]

    // Even if `displays` ever desyncs back down to one entry, keep offering
    // the escape hatch back to Extended whenever we're the one who collapsed
    // it — the user must never be left with no UI path back.
    var isAvailable: Bool { displays.count > 1 || mode != .extended }

    var currentModeLabel: String {
        switch mode {
        case .extended:
            return "Extended"
        case .single(let id):
            return displays.first(where: { $0.id == id })?.name ?? "Mirrored"
        }
    }

    // Re-syncs against the live display list. If a display involved in the
    // current single-display mode has disconnected, macOS will have already
    // dropped the mirror config on its own — just reset our local state to match.
    //
    // NOTE: `allDisplays` comes from NSScreen.screens, which macOS collapses
    // down to a single entry (the target) while mirroring is active — mirrored
    // displays simply don't appear in it. So while mode == .single we can't use
    // `allDisplays` as the new `displays` list (that would drop every mirrored
    // display and make isAvailable/the flyout think only one screen exists).
    // Instead we keep the cached `displays` from before we collapsed, and use
    // the physically-online display list (which does include mirrored
    // displays) to detect a genuine disconnect.
    func refresh(with allDisplays: [ConnectedDisplay]) {
        guard case .single = mode, let targetUUID = collapsedTargetUUID else {
            displays = allDisplays
            adoptUntrackedMirrorIfAny()
            return
        }

        let idByUUID = DisplayModeEngine.onlineDisplayIDsByUUID()

        guard let liveTargetID = idByUUID[targetUUID] else {
            // The target display itself is genuinely gone (no online display
            // carries its UUID) — macOS will have already dropped the mirror
            // config; reset local state to match.
            resetToExtendedState()
            displays = allDisplays
            return
        }

        mirroredDisplayUUIDs = mirroredDisplayUUIDs.filter { idByUUID[$0] != nil }

        guard !mirroredDisplayUUIDs.isEmpty else {
            resetToExtendedState()
            displays = allDisplays
            return
        }

        // Re-sync IDs on the cached (pre-collapse) list against the live
        // values — this is what keeps the flyout's selection state and future
        // CG calls correct even if a display's ID was reassigned while collapsed.
        displays = displays.compactMap { cached in
            guard let uuid = cached.uuid, let liveID = idByUUID[uuid] else { return nil }
            var updated = ConnectedDisplay(
                id: liveID,
                name: cached.name,
                isBuiltIn: cached.isBuiltIn,
                isSelected: cached.isSelected
            )
            updated.uuid = cached.uuid
            updated.m1ddcIndex = cached.m1ddcIndex
            return updated
        }

        mode = .single(liveTargetID)
    }

    // Covers relaunching (or crash-recovering) while a mirror is already
    // active — one this process set up in a previous run, or one turned on
    // outside the app (e.g. System Settings > Displays). `mode` always starts
    // fresh as .extended on launch since it's plain in-memory state, but the
    // actual CoreGraphics display configuration persists across process
    // restarts. Without this, a relaunch while mirrored permanently hides the
    // "Multi-monitor" row (displays.count collapses to 1, same as isAvailable)
    // with no way back to Extended from the UI.
    private func adoptUntrackedMirrorIfAny() {
        let idByUUID = DisplayModeEngine.onlineDisplayIDsByUUID()
        let mirroredOnlineIDs = idByUUID.values.filter { CGDisplayIsInMirrorSet($0) != 0 }
        guard !mirroredOnlineIDs.isEmpty else { return }

        let targetID = CGMainDisplayID()
        mode = .single(targetID)
        collapsedTargetUUID = ConnectedDisplay.systemUUID(for: targetID)
        mirroredDisplayUUIDs = Set(
            mirroredOnlineIDs.filter { $0 != targetID }.compactMap { ConnectedDisplay.systemUUID(for: $0) }
        )
        // originalOriginsByUUID intentionally left empty: this process never
        // observed the pre-mirror arrangement, so switchToExtended() has
        // nothing to restore — it'll just un-mirror and leave whatever
        // origins CoreGraphics already has.
    }

    private func resetToExtendedState() {
        mode = .extended
        mirroredDisplayUUIDs = []
        collapsedTargetUUID = nil
        originalOriginsByUUID = [:]
    }

    // Physical displays that are online (powered/connected), regardless of
    // whether they're currently active/visible to NSScreen — unlike
    // NSScreen.screens, this still includes displays that are mirror targets.
    private static func onlinePhysicalDisplayIDs() -> Set<CGDirectDisplayID> {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }
        return Set(ids.prefix(Int(count)))
    }

    // Live CGDirectDisplayID for every online display, keyed by stable UUID.
    private static func onlineDisplayIDsByUUID() -> [String: CGDirectDisplayID] {
        var result: [String: CGDirectDisplayID] = [:]
        for id in onlinePhysicalDisplayIDs() {
            if let uuid = ConnectedDisplay.systemUUID(for: id) {
                result[uuid] = id
            }
        }
        return result
    }

    func selectMode(_ newMode: Mode) {
        switch newMode {
        case .extended:
            switchToExtended()
        case .single(let id):
            guard mode != newMode, let target = displays.first(where: { $0.id == id }) else { return }
            showOnly(target)
        }
    }

    // MARK: - Private

    private func showOnly(_ target: ConnectedDisplay) {
        guard let targetUUID = target.uuid else { return }
        let others = displays.filter { $0.id != target.id }
        guard !others.isEmpty else { return }

        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let cfg = config else { return }

        if case .single = mode, !mirroredDisplayUUIDs.isEmpty {
            // Already collapsed onto a different display — undo that mirror
            // config in the SAME transaction as the new one below, rather than
            // as a separate prior transaction (previously done via a call to
            // switchToExtended()). Two full CGCompleteDisplayConfiguration
            // calls back-to-back can stall WindowServer for several seconds,
            // which reads as the app "freezing".
            let idByUUID = DisplayModeEngine.onlineDisplayIDsByUUID()
            for uuid in mirroredDisplayUUIDs {
                if let id = idByUUID[uuid] {
                    CGConfigureDisplayMirrorOfDisplay(cfg, id, kCGNullDirectDisplay)
                }
            }
        } else {
            // Snapshot the natural (extended) arrangement before we collapse it,
            // so switchToExtended() can put everything back exactly.
            originalOriginsByUUID = Dictionary(uniqueKeysWithValues: displays.compactMap { d -> (String, CGPoint)? in
                guard let uuid = d.uuid else { return nil }
                return (uuid, CGDisplayBounds(d.id).origin)
            })
        }

        // Force the chosen display to (0,0): that's what makes it the Main
        // Display, which is what the menu bar/status items actually render on.
        CGConfigureDisplayOrigin(cfg, target.id, 0, 0)
        for other in others {
            CGConfigureDisplayMirrorOfDisplay(cfg, other.id, target.id)
        }
        CGCompleteDisplayConfiguration(cfg, .forSession)

        mirroredDisplayUUIDs = Set(others.compactMap { $0.uuid })
        collapsedTargetUUID = targetUUID
        mode = .single(target.id)
    }

    private func switchToExtended() {
        // Deliberately not gated on `mode == .single`: this must still work
        // to break out of a live mirror even if our own state never caught up
        // with it (e.g. right after a relaunch, before adoptUntrackedMirrorIfAny
        // has run, or any other desync) — always check CoreGraphics directly.
        let idByUUID = DisplayModeEngine.onlineDisplayIDsByUUID()

        // Union our tracked UUIDs with whatever CoreGraphics currently reports
        // as actually mirrored, so a stale/empty tracked set (e.g. after an ID
        // reassignment desynced us) can't leave the user stuck mirrored with
        // no way back — always double check live state before giving up.
        var idsToUnmirror = Set(mirroredDisplayUUIDs.compactMap { idByUUID[$0] })
        for id in idByUUID.values where CGDisplayIsInMirrorSet(id) != 0 {
            idsToUnmirror.insert(id)
        }

        guard !idsToUnmirror.isEmpty else {
            resetToExtendedState()
            return
        }

        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let cfg = config else { return }
        for id in idsToUnmirror {
            CGConfigureDisplayMirrorOfDisplay(cfg, id, kCGNullDirectDisplay)
        }
        // Restore the original arrangement, including whichever display was
        // Main before we forced the chosen one to (0,0).
        for (uuid, origin) in originalOriginsByUUID {
            if let id = idByUUID[uuid] {
                CGConfigureDisplayOrigin(cfg, id, Int32(origin.x), Int32(origin.y))
            }
        }
        CGCompleteDisplayConfiguration(cfg, .forSession)

        resetToExtendedState()
    }
}
