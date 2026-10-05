import SwiftUI

/// Icon-only quick action (no label, no circle). The tap target is at least
/// 44x44pt; the VoiceOver label carries the meaning the glyph alone can't.
struct GarageQuickAction: View {
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void

    @ScaledMetric(relativeTo: .title2) private var glyphSize: CGFloat = 24

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: glyphSize, weight: .regular))
                .foregroundColor(GarageTheme.icon)
                .frame(maxWidth: .infinity, minHeight: 56)
                .contentShape(Rectangle())
        }
        .buttonStyle(GaragePressStyle())
        .accessibilityLabel(accessibilityLabel)
    }
}

/// Large Tesla-style row: icon, big label, grey live subtitle, chevron.
/// Separated from its neighbours by generous spacing, not divider lines.
struct GarageListRow: View {
    let systemImage: String
    let title: String
    let subtitle: String
    /// A tiny accent dot on the icon — used sparingly, for "look at this".
    var showsDot = false

    @ScaledMetric(relativeTo: .title2) private var iconSize: CGFloat = 22
    @ScaledMetric(relativeTo: .title2) private var iconColumn: CGFloat = 34

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: iconSize))
                .foregroundColor(GarageTheme.icon)
                .frame(width: iconColumn)
                .overlay(alignment: .topTrailing) {
                    if showsDot {
                        Circle()
                            .fill(GarageTheme.accentDot)
                            .frame(width: 8, height: 8)
                            .offset(x: 2, y: -2)
                    }
                }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .foregroundColor(GarageTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(GarageTheme.secondaryText)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.body.weight(.semibold))
                .foregroundColor(GarageTheme.chevron)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(showsDot ? "Needs attention" : "")
    }
}

/// One row of the grouped "attention" card.
struct GarageAttentionRow: View {
    let item: GarageSummary.AttentionItem

    @ScaledMetric(relativeTo: .title3) private var iconSize: CGFloat = 20
    @ScaledMetric(relativeTo: .title3) private var iconColumn: CGFloat = 32

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: item.icon)
                .font(.system(size: iconSize))
                .foregroundColor(GarageTheme.icon)
                .frame(width: iconColumn)
                .overlay(alignment: .topTrailing) {
                    if item.isUrgent {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 7, height: 7)
                            .offset(x: 2, y: -2)
                    }
                }
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.title3.weight(.semibold))
                    .foregroundColor(GarageTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(item.subtitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(GarageTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.body.weight(.semibold))
                .foregroundColor(GarageTheme.chevron)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Dims on press without the default blue tint.
struct GaragePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.45 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
