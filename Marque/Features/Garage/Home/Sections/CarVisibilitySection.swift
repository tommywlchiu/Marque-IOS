import SwiftUI

// Public/private toggle and the "what's shared" controls for the owner's car.
// Extracted from CarDetailView; used there and by the Garage's Public Sharing
// screen. The going-private confirmation stays in `CarSocialPresenters`
// (Features/Social), which both callers attach.

/// Human-readable list of what a public car currently shares. Mirrors the
/// currently saved `publicSharing` / `showValuePublicly` (not any draft).
enum CarSharingSummary {
    static func sharedGroups(for car: Car) -> [String] {
        var on: [String] = []
        if car.publicSharing.photos { on.append("photos") }
        if car.publicSharing.specs { on.append("specs") }
        if car.publicSharing.mileage { on.append("mileage") }
        if car.publicSharing.notes { on.append("notes") }
        if car.publicSharing.serviceHistory { on.append("service history") }
        if car.publicSharing.mods { on.append("mods") }
        if car.publicSharing.engineSound { on.append("engine sound") }
        if car.showValuePublicly { on.append("value") }
        return on
    }

    /// "Sharing: photos, specs" — the car page's row caption.
    static func text(for car: Car) -> String {
        let on = sharedGroups(for: car)
        guard !on.isEmpty else { return "Nothing extra shared" }
        return "Sharing: " + on.joined(separator: ", ")
    }

    /// One-time prompt for a public car that predates per-group sharing
    /// (`isPublic && !publicSharing.hasReviewed` — see
    /// `PublicSharingSettings.legacyAllOn`).
    static func needsReview(_ car: Car) -> Bool {
        car.isPublic && !car.publicSharing.hasReviewed
    }
}

@MainActor
enum CarVisibilityActions {
    /// Publishes or unpublishes `car`. Returns true when the car was just made
    /// public, so the caller can offer the push pre-prompt.
    @discardableResult
    static func apply(
        _ isPublic: Bool,
        to car: Car,
        sharing: PublicSharingSettings? = nil,
        showValuePublicly: Bool? = nil,
        carStore: CarStore,
        authService: AuthService
    ) -> Bool {
        guard car.isPublic != isPublic else { return false }
        let username = authService.currentUser?.username ?? ""
        let avatarURL = authService.currentUser?.avatarURL
        carStore.setVisibility(isPublic, for: car, ownerUsername: username, ownerAvatarURL: avatarURL, sharing: sharing, showValuePublicly: showValuePublicly)
        AnalyticsService.carVisibilityChanged(isPublic: isPublic)
        return isPublic
    }
}

/// The Public toggle, plus (when public) an engagement slot, the review
/// prompt and the "Public sharing" row.
///
/// The toggle never mutates the car itself: going public asks the caller to
/// open `PublicSharingSheet` in `.goingPublic` mode, going private asks it to
/// confirm. Its `get` reads `car.isPublic`, so a cancelled sheet leaves the
/// switch snapping back to off on its own.
struct CarVisibilitySection<Engagement: View>: View {
    let car: Car
    let onRequestPublic: () -> Void
    let onRequestPrivate: () -> Void
    let onEditSharing: () -> Void
    @ViewBuilder let engagement: () -> Engagement

    var body: some View {
        Section {
            Toggle(isOn: Binding(
                get: { car.isPublic },
                set: { $0 ? onRequestPublic() : onRequestPrivate() }
            )) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Public").font(.body)
                        Text(car.isPublic
                            ? "Visible in Explore and your public profile"
                            : "Only visible to you")
                            .font(.caption).foregroundColor(.secondary)
                    }
                } icon: {
                    Image(systemName: car.isPublic ? "eye.fill" : "eye.slash.fill")
                        .foregroundColor(car.isPublic ? .accentColor : .secondary)
                }
            }

            if car.isPublic {
                engagement()
                if CarSharingSummary.needsReview(car) {
                    reviewPromptBanner
                }
                publicSharingRow
            }
        }
        .garageRowBackground()
    }

    private var reviewPromptBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "eye.trianglebadge.exclamationmark")
                .foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 4) {
                Text("Choose what's shared")
                    .font(.subheadline.weight(.semibold))
                Text("You can now hide mileage, notes and more from your public car page.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Review", action: onEditSharing)
                    .font(.caption.weight(.semibold))
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var publicSharingRow: some View {
        Button(action: onEditSharing) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "slider.horizontal.3")
                    .foregroundColor(.accentColor)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Public sharing").foregroundColor(.primary)
                    Text(CarSharingSummary.text(for: car))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.4))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Public sharing, \(CarSharingSummary.text(for: car))")
        .accessibilityHint("Double-tap to choose what's shared")
    }
}

/// Presents `PublicSharingSheet` and applies its result: `.goingPublic`
/// publishes with the chosen settings, `.editing` updates them in place.
struct PublicSharingSheetPresenter: ViewModifier {
    let car: Car?
    let mode: PublicSharingSheetMode
    @Binding var isPresented: Bool
    /// Called after the car was just made public (offer the push pre-prompt).
    let onMadePublic: () -> Void

    @EnvironmentObject private var carStore: CarStore
    @EnvironmentObject private var authService: AuthService

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented) {
            if let car {
                PublicSharingSheet(car: car, mode: mode) { sharing, showValuePublicly in
                    if mode == .goingPublic {
                        let madePublic = CarVisibilityActions.apply(
                            true, to: car, sharing: sharing, showValuePublicly: showValuePublicly,
                            carStore: carStore, authService: authService
                        )
                        if madePublic { onMadePublic() }
                    } else {
                        carStore.updatePublicSharing(sharing, showValuePublicly: showValuePublicly, for: car)
                    }
                }
            }
        }
    }
}
