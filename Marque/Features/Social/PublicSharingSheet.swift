import SwiftUI

/// Which flow opened `PublicSharingSheet`. `.goingPublic` is shown every time
/// a car is switched to Public (owner decision); `.editing` is the "Public
/// sharing" row / review-prompt path for an already-public car.
enum PublicSharingSheetMode {
    case goingPublic
    case editing
}

/// "What's shared in Explore" — lets the owner choose which optional groups
/// (`PublicSharingSettings`) and the value-range toggle (`Car.showValuePublicly`)
/// are published for this car, with a live preview built from the exact same
/// `PublicCar(from:)` projection the real publish uses.
///
/// This view never writes anything itself — `onConfirm` hands the finished
/// settings back to the caller, which is the only place `CarStore.setVisibility`
/// / `updatePublicSharing` are called. For `.goingPublic`, Cancel therefore
/// leaves the car exactly as it was (private): the caller's Public toggle,
/// which reads `car.isPublic` and never mutated it to open this sheet, snaps
/// back to off on its own next render.
struct PublicSharingSheet: View {
    let car: Car
    let mode: PublicSharingSheetMode
    var onConfirm: (PublicSharingSettings, Bool) -> Void

    @EnvironmentObject private var carStore: CarStore
    @EnvironmentObject private var authService: AuthService
    @Environment(\.dismiss) private var dismiss

    @State private var draft: PublicSharingSettings
    @State private var draftShowValuePublicly: Bool
    @State private var showPreview = false

    init(car: Car, mode: PublicSharingSheetMode, onConfirm: @escaping (PublicSharingSettings, Bool) -> Void) {
        self.car = car
        self.mode = mode
        self.onConfirm = onConfirm
        _draft = State(initialValue: car.publicSharing)
        _draftShowValuePublicly = State(initialValue: car.showValuePublicly)
    }

    // MARK: - Preview

    /// `car` with the draft toggles applied, so the preview is built through
    /// the SAME `PublicCar(from:)` every real publish uses — it can never
    /// show something the actual publish wouldn't.
    private var draftCar: Car {
        var updated = car
        updated.publicSharing = draft
        updated.showValuePublicly = draftShowValuePublicly
        return updated
    }

    private var previewPublicCar: PublicCar {
        PublicCar(
            from: draftCar,
            ownerUID: authService.currentUser?.id ?? "",
            ownerUsername: authService.currentUser?.username ?? "",
            ownerAvatarURL: authService.currentUser?.avatarURL
        )
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Public cars are visible to every Marque user in Explore and on your profile. Choose what you'd like to share below \u{2014} you can change this anytime.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Section("Always shared") {
                    AlwaysSharedRow(icon: "car.fill", title: "Year, make & model", subtitle: car.displayName)
                    AlwaysSharedRow(icon: "person.crop.circle.fill", title: "Username & avatar", subtitle: usernameSubtitle)
                    AlwaysSharedRow(icon: "heart.fill", title: "Likes & comments", subtitle: "Visible to everyone")
                }

                Section(
                    header: Text("Choose what else to share"),
                    footer: Text("A group with nothing in it yet can still be turned on \u{2014} it applies as soon as you add that information.")
                ) {
                    SharingToggleRow(icon: "photo.on.rectangle.angled", title: "Photos", subtitle: photosSubtitle, isOn: $draft.photos)
                    SharingToggleRow(icon: "list.bullet.rectangle", title: "Specs", subtitle: specsSubtitle, isOn: $draft.specs)
                    SharingToggleRow(icon: "speedometer", title: "Mileage", subtitle: mileageSubtitle, isOn: $draft.mileage)
                    SharingToggleRow(icon: "note.text", title: "Notes", subtitle: notesSubtitle, isOn: $draft.notes)
                    SharingToggleRow(icon: "wrench.and.screwdriver", title: "Service history", subtitle: serviceHistorySubtitle, isOn: $draft.serviceHistory)
                    SharingToggleRow(icon: "bolt.car", title: "Mods", subtitle: modsSubtitle, isOn: $draft.mods)
                    SharingToggleRow(icon: "waveform", title: "Engine sound", subtitle: engineSoundSubtitle, isOn: $draft.engineSound)
                    valueToggleRow
                }

                Section {
                    DisclosureGroup("Preview in Explore", isExpanded: $showPreview) {
                        HStack {
                            Spacer(minLength: 0)
                            ExploreFeedCard(car: previewPublicCar, onOwnerTap: {}, onLiked: {})
                                .allowsHitTesting(false)
                                .frame(maxWidth: 280)
                                .padding(.vertical, 8)
                            Spacer(minLength: 0)
                        }
                        .accessibilityHidden(true) // A non-interactive copy of what's above; avoids doubling VoiceOver content.
                    }
                }
            }
            .navigationTitle(mode == .goingPublic ? "What's Shared" : "Public Sharing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(mode == .goingPublic ? "Make Public" : "Save") {
                        var finalSharing = draft
                        finalSharing.hasReviewed = true
                        onConfirm(finalSharing, draftShowValuePublicly)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Always-shared subtitles

    private var usernameSubtitle: String {
        if let username = authService.currentUser?.username, !username.isEmpty {
            return "@\(username)"
        }
        return "Your profile"
    }

    // MARK: - Toggle subtitles ("the actual data being shared")
    //
    // Deliberately computed from `car` (not `draft`): the subtitle describes
    // what WOULD be shared if the group is on, regardless of its current
    // toggle state, so switching a group off doesn't make its own row claim
    // there's nothing there.

    private var photosSubtitle: String {
        let count = car.photoFileNames.count
        guard count > 0 else { return "Nothing to share yet" }
        return "\(count) photo\(count == 1 ? "" : "s")"
    }

    private var specsValues: [String] {
        [car.trim, car.engine, car.bodyStyle, car.driveType, car.transmission, car.fuelType, car.color]
            .filter { !$0.isEmpty }
    }

    private var specsSubtitle: String {
        specsValues.isEmpty ? "Nothing to share yet" : specsValues.joined(separator: " \u{00B7} ")
    }

    private var mileageSubtitle: String {
        car.mileageText ?? "Nothing to share yet"
    }

    private var notesSubtitle: String {
        let trimmed = car.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Nothing to share yet" }
        let truncated = trimmed.count > 60 ? String(trimmed.prefix(60)) + "\u{2026}" : trimmed
        return "\u{201C}\(truncated)\u{201D}"
    }

    private var serviceHistorySubtitle: String {
        let count = car.maintenanceRecords.count
        guard count > 0 else { return "Nothing to share yet" }
        return "\(count) record\(count == 1 ? "" : "s") (types and dates, never costs)"
    }

    private var modsSubtitle: String {
        let count = car.mods.count
        guard count > 0 else { return "Nothing to share yet" }
        return "\(count) mod\(count == 1 ? "" : "s")"
    }

    private var hasEngineSoundClip: Bool {
        car.engineSoundFileName != nil || !(car.engineSoundURL ?? "").isEmpty
    }

    private var engineSoundSubtitle: String {
        guard hasEngineSoundClip else { return "Nothing to share yet" }
        let seconds = Int((car.engineSoundDuration ?? 0).rounded())
        return seconds > 0 ? "\(seconds)s clip" : "Audio clip"
    }

    // MARK: - Estimated value (special case: can be disabled)

    /// Mirrors `CarValueSection`'s rule: only an applicable AI estimate can
    /// ever be shown publicly, as a rounded range. A typed value never is.
    @ViewBuilder
    private var valueToggleRow: some View {
        if carStore.canShowValuePublicly(car) {
            SharingToggleRow(
                icon: "dollarsign.circle.fill",
                title: "Estimated value",
                subtitle: valueSubtitle,
                isOn: $draftShowValuePublicly
            )
        } else {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "dollarsign.circle")
                    .foregroundColor(.secondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Estimated value")
                        .foregroundColor(.secondary)
                    Text(valueDisabledReason)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var valueDisabledReason: String {
        carStore.aiValuation(for: car) == nil
            ? "Get an AI estimate to show a range publicly. Your own value stays private."
            : "Details changed since the last AI estimate. Re-estimate to show a range publicly."
    }

    private var valueSubtitle: String {
        guard let range = carStore.publicValueRangePreview(for: car) else { return "Nothing to share yet" }
        return "Would show as \u{201C}Est. value \(range)\u{201D}"
    }
}

// MARK: - Rows

/// Non-interactive row for the "Always shared" group.
private struct AlwaysSharedRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.secondary.opacity(0.5))
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(subtitle), always shared")
    }
}

/// One toggle row with a title and a live data-summary subtitle. The subtitle
/// is folded into the row's single accessibility label (via `.combine`) so
/// VoiceOver reads "Mileage, 50,200 mi" before the switch's own on/off state,
/// without disturbing `Toggle`'s own accessibility traits.
private struct SharingToggleRow: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundColor(.accentColor)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}
