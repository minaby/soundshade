import SwiftUI

// MARK: - Multi-monitor Control Row (lives in the main panel)
//
// Behaves like a native NSMenu item with a submenu: hovering it (reported via
// onHoverChange) opens a flyout panel positioned using the frame reported
// through onFrameChange.

struct MultiMonitorRowView: View {
    let currentModeLabel: String
    let onHoverChange: (Bool) -> Void
    let onFrameChange: (CGRect) -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "rectangle.on.rectangle")
                .font(.system(size: 13, weight: .regular))
                .frame(width: 18)
                .foregroundStyle(isHovered ? Color.white : Color.primary)

            Text("Multi-monitor")
                .font(.system(size: 13))
                .foregroundStyle(isHovered ? Color.white : Color.primary)
                .lineLimit(1)

            Spacer()

            Text(currentModeLabel)
                .font(.system(size: 12))
                .foregroundStyle(isHovered ? Color.white.opacity(0.85) : .secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isHovered ? Color.white.opacity(0.85) : .secondary)
        }
        .contentShape(Rectangle())
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isHovered ? Color.accentColor : Color.clear)
        )
        .padding(.horizontal, 4)
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { onFrameChange(geo.frame(in: .named("panelSpace"))) }
                    .onChange(of: geo.frame(in: .named("panelSpace"))) { newFrame in
                        onFrameChange(newFrame)
                    }
            }
        )
        .onHover { hovering in
            isHovered = hovering
            onHoverChange(hovering)
        }
    }
}

// MARK: - Multi-monitor Flyout (separate NSPanel content)

struct MultiMonitorFlyoutView: View {
    let displays: [ConnectedDisplay]
    let mode: DisplayModeEngine.Mode
    let onSelect: (DisplayModeEngine.Mode) -> Void
    let onHoverChange: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Other displays mirror the one you choose")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 4)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 1) {
                FlyoutOptionRow(title: "Extended", isSelected: mode == .extended) {
                    onSelect(.extended)
                }
                ForEach(displays) { display in
                    FlyoutOptionRow(
                        title: "Mirror \(display.name)",
                        isSelected: mode == .single(display.id)
                    ) {
                        onSelect(.single(display.id))
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .fixedSize(horizontal: true, vertical: true)
        .onHover { hovering in
            onHoverChange(hovering)
        }
    }
}

private struct FlyoutOptionRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(isHovered ? Color.white : Color.primary)
                    .lineLimit(1)

                Spacer(minLength: 12)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isHovered ? Color.white : Color.accentColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(backgroundColor)
        )
        .padding(.horizontal, 4)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var backgroundColor: Color {
        if isHovered { return Color.accentColor }
        if isSelected { return Color.accentColor.opacity(0.1) }
        return Color.clear
    }
}
