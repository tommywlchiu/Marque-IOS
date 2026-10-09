import SwiftUI

/// Icon-only quick action (no label, no circle). The tap target is at least
/// 44x44pt; the VoiceOver label carries the meaning the glyph alone can't.
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

/// One row of the grouped "attention" card. Takes its own tap action rather
/// than being wrapped in an outer `Button` — `onDismiss` is only passed (and
/// only then does a close button appear) for a "missing info" suggestion, as
/// a sibling tap target next to the row's own, never nested inside it (two
/// `Button`s nested in SwiftUI fight over the gesture; siblings don't). An
/// expiry or reminder row is never dismissible.
struct GarageAttentionRow: View {
    let item: GarageSummary.AttentionItem
    let onTap: () -> Void
    var onDismiss: (() -> Void)? = nil

    @ScaledMetric(relativeTo: .title3) private var iconSize: CGFloat = 20
    @ScaledMetric(relativeTo: .title3) private var iconColumn: CGFloat = 32

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onTap) {
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
                    if onDismiss == nil {
                        Image(systemName: "chevron.right")
                            .font(.body.weight(.semibold))
                            .foregroundColor(GarageTheme.chevron)
                    }
                }
                .padding(.vertical, 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(GaragePressStyle())

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .foregroundColor(GarageTheme.chevron)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Dismiss suggestion")
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, onDismiss == nil ? 16 : 4)
        // Combining into one VoiceOver element only makes sense with a
        // single action — with a dismiss button too, each needs to stay
        // reachable as its own element, or the "Dismiss" action is lost.
        .modifier(CombineAccessibilityIfNoDismiss(enabled: onDismiss == nil))
    }
}

private struct CombineAccessibilityIfNoDismiss: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled {
            content.accessibilityElement(children: .combine)
        } else {
            content
        }
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

// MARK: - Mileage check-in

/// "Current mileage?" — shown when the car has an open mileage-triggered
/// reminder and its mileage hasn't been updated in 30 days (or ever). Those
/// reminders can never fire a local notification on their own, so this is
/// the periodic nudge that keeps them accurate. Dismissal lasts until the
/// screen is rebuilt, as it did on the old car page.
struct GarageMileageCheckIn: View {
    let car: Car

    @EnvironmentObject private var carStore: CarStore
    @State private var dismissedCarID: UUID?
    @State private var text = ""

    private var shouldShow: Bool {
        guard dismissedCarID != car.id, car.hasOpenMileageReminders else { return false }
        guard let updatedAt = car.mileageUpdatedAt else { return true }
        return Date().timeIntervalSince(updatedAt) > 30 * 24 * 60 * 60
    }

    private var enteredValue: Int? { Int(text.replacingOccurrences(of: ",", with: "")) }

    var body: some View {
        if shouldShow {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Current mileage?")
                        .font(.headline)
                        .foregroundColor(GarageTheme.primaryText)
                    Spacer()
                    Button {
                        withAnimation { dismissedCarID = car.id }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(GarageTheme.secondaryText)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(GaragePressStyle())
                    .accessibilityLabel("Dismiss")
                }
                Text("Keeps your mileage-based reminders on time.")
                    .font(.subheadline)
                    .foregroundColor(GarageTheme.secondaryText)
                HStack(spacing: 10) {
                    TextField("Mileage", text: $text)
                        .keyboardType(.numberPad)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.08)))
                        .foregroundColor(GarageTheme.primaryText)
                    Button {
                        guard let value = enteredValue else { return }
                        carStore.updateMileage(value, for: car)
                        text = ""
                        withAnimation { dismissedCarID = car.id }
                    } label: {
                        Text("Update")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(GarageTheme.background)
                            .padding(.horizontal, 18)
                            .frame(minHeight: 44)
                            .background(Capsule().fill(Color.white.opacity(enteredValue == nil ? 0.4 : 1)))
                    }
                    .buttonStyle(GaragePressStyle())
                    .disabled(enteredValue == nil)
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 4)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(GarageTheme.card))
        }
    }
}
