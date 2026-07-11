import SwiftUI

// MARK: - Device Row

struct DeviceRowView: View {
    let device: AudioDevice
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                Image(systemName: device.icon)
                    .font(.system(size: 13, weight: .regular))
                    .frame(width: 18)
                    .foregroundStyle(isHovered ? Color.white : (isSelected ? Color.accentColor : Color.primary))

                Text(device.name)
                    .font(.system(size: 13))
                    .foregroundStyle(isHovered ? Color.white : Color.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isHovered ? Color.white : Color.accentColor)
                }

                if device.isBluetooth {
                    Image(systemName: "bluetooth")
                        .font(.system(size: 10))
                        .foregroundStyle(isHovered ? Color.white.opacity(0.85) : .secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isHovered ? Color.accentColor : (isSelected ? Color.accentColor.opacity(0.1) : Color.clear))
        )
        .padding(.horizontal, 4)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
