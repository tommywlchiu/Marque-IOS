import SwiftUI

// MARK: - Expiry status
//
// Shared "N days left / expired / no date" classification for wallet document
// badges, mirroring the 30-day threshold Car.isInsuranceExpiringSoon etc.
// already use. Driver-license expiry lives on AppUser, which has no
// equivalent computed property, so this is a small local pure helper rather
// than a Models/ change.
enum DocumentExpiryStatus {
    case none
    case valid(Date)
    case expiringSoon(Date, daysLeft: Int)
    case expired(Date)

    init(_ date: Date?) {
        guard let date else {
            self = .none
            return
        }
        let start = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.startOfDay(for: date)
        let days = Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0
        if days < 0 {
            self = .expired(date)
        } else if days <= 30 {
            self = .expiringSoon(date, daysLeft: days)
        } else {
            self = .valid(date)
        }
    }
}

/// FR-12.5: every state pairs an icon with text, never color alone.
struct ExpiryBadge: View {
    let status: DocumentExpiryStatus

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(background, in: Capsule())
        .foregroundStyle(foreground)
        .accessibilityElement(children: .combine)
    }

    private var icon: String {
        switch status {
        case .none: return "minus.circle.fill"
        case .valid: return "checkmark.circle.fill"
        case .expiringSoon: return "exclamationmark.circle.fill"
        case .expired: return "exclamationmark.triangle.fill"
        }
    }

    private var text: String {
        switch status {
        case .none: return "No expiry set"
        case .valid(let date): return date.formatted(date: .abbreviated, time: .omitted)
        case .expiringSoon(_, let days): return days == 0 ? "Expires today" : "Expires in \(days)d"
        case .expired: return "Expired"
        }
    }

    private var background: Color {
        switch status {
        case .none, .valid: return Color.white.opacity(0.2)
        case .expiringSoon: return Color.yellow.opacity(0.95)
        case .expired: return Color.red.opacity(0.95)
        }
    }

    private var foreground: Color {
        switch status {
        case .none, .valid: return .white
        case .expiringSoon: return .black
        case .expired: return .white
        }
    }
}

// MARK: - Masking

/// Masks all but the last `keepLast` characters, matching the masked-by-
/// default pattern EditProfileView's driver-license field already uses.
func maskedTail(_ value: String, revealed: Bool, keepLast: Int = 4) -> String {
    guard !value.isEmpty else { return "—" }
    guard !revealed else { return value }
    guard value.count > keepLast else { return String(repeating: "•", count: max(value.count, 4)) }
    return String(repeating: "•", count: value.count - keepLast) + value.suffix(keepLast)
}

private struct RevealButton: View {
    @Binding var revealed: Bool

    var body: some View {
        Button {
            revealed.toggle()
        } label: {
            Image(systemName: revealed ? "eye.slash.fill" : "eye.fill")
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(revealed ? "Hide number" : "Show number")
    }
}

// MARK: - Binder tab strip

/// The row of folder-style dividers across the top of the documents area —
/// License, then one per car. The selected tab reads as the front folder
/// (full brand-color fill, full height); the rest sit a little shorter and
/// muted, like dividers peeking out behind it, until tapped.
struct WalletTabStrip: View {
    let tabs: [WalletTab]
    let selected: WalletTab
    let title: (WalletTab) -> String
    let icon: (WalletTab) -> String
    let onSelect: (WalletTab) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(tabs, id: \.self) { tab in
                        FolderTab(
                            title: title(tab),
                            icon: icon(tab),
                            isSelected: tab == selected
                        ) {
                            onSelect(tab)
                        }
                        .id(tab)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .onChange(of: selected) { _, newValue in
                withAnimation { proxy.scrollTo(newValue, anchor: .center) }
            }
        }
        .background(Color(.systemGray6))
    }
}

private struct FolderTab: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.subheadline)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .frame(height: isSelected ? 52 : 40, alignment: .top)
            .padding(.top, isSelected ? 8 : 14)
            .frame(minWidth: 64)
            .foregroundStyle(isSelected ? .white : Color.secondary)
            .background(
                UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 12, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color(.systemGray4)))
            )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: isSelected)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Card shell

/// Apple-Wallet-style rounded card: gradient fill, icon + chevron header row,
/// caption title, then the type's own content. `onTap` opens the existing
/// editor for that document (never a second editor built here).
private struct WalletCardShell<Content: View>: View {
    let gradient: [Color]
    let icon: String
    let title: String
    let onTap: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: icon)
                        .font(.title2)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .opacity(0.7)
                }
                Text(title)
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .opacity(0.85)
                content
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(.white)
            .background(
                LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Driver's License

struct DriverLicenseCard: View {
    let user: AppUser
    let onTap: () -> Void

    @State private var revealed = false

    private var status: DocumentExpiryStatus { DocumentExpiryStatus(user.driverLicenseExpiryDate) }

    var body: some View {
        WalletCardShell(gradient: [.indigo, .blue], icon: "person.text.rectangle.fill", title: "Driver's License", onTap: onTap) {
            HStack {
                Text(maskedTail(user.driverLicenseNumber, revealed: revealed))
                    .font(.system(.title3, design: .monospaced).weight(.semibold))
                    .lineLimit(1)
                Spacer()
                RevealButton(revealed: $revealed)
            }
            HStack {
                if !user.driverLicenseState.isEmpty {
                    Text(user.driverLicenseState)
                        .font(.footnote.weight(.medium))
                        .opacity(0.9)
                }
                Spacer()
                ExpiryBadge(status: status)
            }
        }
        .accessibilityLabel("Driver's license, edit")
    }
}

// MARK: - Insurance

struct InsuranceCard: View {
    let car: Car
    let onTap: () -> Void

    @State private var revealed = false

    private var status: DocumentExpiryStatus { DocumentExpiryStatus(car.insuranceExpiryDate) }

    var body: some View {
        WalletCardShell(gradient: [.teal, .green], icon: "shield.fill", title: "Insurance", onTap: onTap) {
            HStack {
                Text(maskedTail(car.insurancePolicyNumber, revealed: revealed))
                    .font(.system(.title3, design: .monospaced).weight(.semibold))
                    .lineLimit(1)
                Spacer()
                RevealButton(revealed: $revealed)
            }
            HStack {
                if !car.insuranceProvider.isEmpty {
                    Text(car.insuranceProvider)
                        .font(.footnote.weight(.medium))
                        .opacity(0.9)
                        .lineLimit(1)
                }
                Spacer()
                ExpiryBadge(status: status)
            }
        }
        .accessibilityLabel("\(car.displayName) insurance, edit")
    }
}

// MARK: - Registration

struct RegistrationCard: View {
    let car: Car
    let onTap: () -> Void

    private var status: DocumentExpiryStatus { DocumentExpiryStatus(car.registrationExpiryDate) }

    var body: some View {
        WalletCardShell(gradient: [.orange, .red], icon: "doc.text.fill", title: "Registration", onTap: onTap) {
            Text(car.licensePlate.isEmpty ? "No plate on file" : car.licensePlate)
                .font(.system(.title3, design: .monospaced).weight(.semibold))
                .lineLimit(1)
            HStack {
                Spacer()
                ExpiryBadge(status: status)
            }
        }
        .accessibilityLabel("\(car.displayName) registration, edit")
    }
}

// MARK: - Specs

/// Read-only summary of the car's own vehicle-detail fields — editing routes
/// to the existing EditVehicleDetailsSheet (Garage's Details screen), never
/// a second specs editor. No expiry badge: specs don't expire.
struct SpecsCard: View {
    let car: Car
    let onTap: () -> Void

    private var identityLine: String {
        [car.trim, car.bodyStyle, car.driveType].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var powertrainLine: String {
        [car.engine, car.transmission, car.fuelType, car.color].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var body: some View {
        WalletCardShell(gradient: [.gray, Color(white: 0.2)], icon: "list.bullet.rectangle.fill", title: "Specs", onTap: onTap) {
            if !identityLine.isEmpty {
                Text(identityLine)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .lineLimit(1)
            }
            if !powertrainLine.isEmpty {
                Text(powertrainLine)
                    .font(.footnote.weight(.medium))
                    .opacity(0.9)
                    .lineLimit(2)
            }
        }
        .accessibilityLabel("\(car.displayName) specs, edit")
    }
}

// MARK: - Warranty

struct WarrantyCard: View {
    let car: Car
    let onTap: () -> Void

    var body: some View {
        WalletCardShell(gradient: [.purple, .indigo], icon: "checkmark.seal.fill", title: "Warranty", onTap: onTap) {
            Text(car.warrantyType.isEmpty ? "Type not set" : car.warrantyType)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .lineLimit(1)
            if !car.warrantyProvider.isEmpty {
                Text(car.warrantyProvider)
                    .font(.footnote.weight(.medium))
                    .opacity(0.9)
                    .lineLimit(1)
            }
        }
        .accessibilityLabel("\(car.displayName) warranty, edit")
    }
}

// MARK: - Add-document prompt

/// Dashed "Add X" card for a document type the user hasn't filled in yet —
/// matches the dashed "Add a Car" affordance already used on Garage.
struct AddDocumentCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Color.accentColor.opacity(0.12)).frame(width: 44, height: 44)
                    Image(systemName: icon).foregroundStyle(Color.accentColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "plus.circle.fill").foregroundStyle(Color.accentColor)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [8, 6]))
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the editor to add this document")
    }
}
