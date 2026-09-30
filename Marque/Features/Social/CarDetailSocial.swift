import SwiftUI

// Social pieces of `CarDetailView`, kept out of that file so its body stays
// cheap for the type checker (see MaintenanceLogPresenters there).

// MARK: - Public photo header

/// Cover photo, count badge and thumbnail strip for a public car, using
/// every public photo (`galleryURLs`), not just the cover.
struct PublicCarPhotoHeader: View {
    let car: PublicCar
    let onSelect: (Int) -> Void

    var body: some View {
        let urls = car.galleryURLs
        if let cover = urls.first {
            ZStack(alignment: .bottomTrailing) {
                CachedRemoteImage(url: cover)
                    .frame(maxWidth: .infinity).frame(height: 200)
                    .offset(y: car.photoOffsetY)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                    .onTapGesture { onSelect(0) }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("Photo 1 of \(urls.count). Double-tap to view full screen")

                if urls.count > 1 {
                    HStack(spacing: 4) {
                        Image(systemName: "photo.stack").font(.caption2)
                        Text("\(urls.count)").font(.caption).fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.black.opacity(0.55))
                    .clipShape(Capsule())
                    .padding(10)
                    .accessibilityHidden(true)
                }
            }

            if urls.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
                            Button { onSelect(index) } label: {
                                CachedRemoteImage(url: url)
                                    .frame(width: 56, height: 56)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Photo \(index + 1) of \(urls.count)")
                        }
                    }
                    .padding(.horizontal, 2).padding(.top, 4)
                }
            }
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.accentColor.opacity(0.08))
                    .frame(height: 120)
                Image(systemName: "car.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.accentColor.opacity(0.4))
            }
        }
    }
}

// MARK: - Public highlights (likes, comments, value range, engine sound)

struct PublicCarHighlightsSection: View {
    let car: PublicCar
    let commentCount: Int
    let onLiked: () -> Void
    let onOpenComments: () -> Void

    @StateObject private var player = EngineSoundPlayer()

    var body: some View {
        Section {
            HStack(spacing: 10) {
                LikeButton(car: car, style: .prominent, onLiked: onLiked)
                Button(action: onOpenComments) {
                    HStack(spacing: 6) {
                        Image(systemName: "bubble.left").font(.title3)
                        Text(commentCount.formatted())
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                    }
                    .foregroundColor(.primary)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().fill(Color(.systemGray6)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(commentCount == 1 ? "1 comment" : "\(commentCount) comments")
                .accessibilityHint("Double-tap to open comments")
                Spacer(minLength: 0)
            }
            .padding(.vertical, 2)

            if let range = car.valueRange, !range.isEmpty {
                PublicValueRangeRow(range: range)
            }

            if let url = car.engineSoundPlaybackURL {
                EngineSoundCapsule(
                    isPlaying: player.isPlaying,
                    isLoading: player.isLoading,
                    progress: player.progress,
                    duration: player.duration,
                    failed: player.failed
                ) {
                    player.toggle(url: url)
                }
                .padding(.vertical, 2)
                .onDisappear { player.stop() }
            }
        }
    }
}

// MARK: - Public mods

/// Small "Modified" pill for a public car with at least one mod — shown near
/// the title on the public car page (`PublicCar.isModified`).
struct ModifiedPill: View {
    var body: some View {
        Label("Modified", systemImage: "wrench.and.screwdriver.fill")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(Color.accentColor.opacity(0.14)))
            .foregroundColor(.accentColor)
            .accessibilityLabel("Modified")
    }
}

/// Read-only "Mods" section for a public car: category/name/brand only —
/// `PublicCarMod` never carries `notes` or `installedAt` (the owner didn't
/// publish either), so there's nothing to hide here beyond what's already
/// absent from the model. The caller (`CarDetailView`) hides this section
/// entirely when `mods` is empty.
struct PublicCarModsSection: View {
    let mods: [PublicCarMod]

    var body: some View {
        Section(header: Text("Mods · \(mods.count)")) {
            ForEach(mods) { mod in
                PublicModRow(mod: mod)
            }
        }
    }
}

private struct PublicModRow: View {
    let mod: PublicCarMod

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: ModIcon.symbolName(for: mod.category))
                .font(.body)
                .foregroundColor(.accentColor)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(mod.name).foregroundColor(.primary)
                if let brand = mod.brand, !brand.isEmpty {
                    Text(brand).font(.caption).foregroundColor(.secondary)
                }
            }
            Spacer(minLength: 8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ModIcon.accessibilityLabel(for: mod.category, name: mod.name, brand: mod.brand))
    }
}

/// "Est. value $30k–$35k". Only ever the rounded public range.
struct PublicValueRangeRow: View {
    let range: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "tag.fill")
                .foregroundColor(.accentColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Est. value \(range)")
                    .font(.subheadline.weight(.semibold))
                Text("Owner's estimate, not an appraisal")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Owner's own public car: likes and comments at a glance, under the Public
/// toggle. Likes need the public doc (from Explore's cache); if it isn't
/// loaded, only the comment count shows.
struct OwnCarEngagementRow: View {
    let publicCar: PublicCar?
    let commentCount: Int
    let onOpenComments: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            if let publicCar {
                LikeButton(car: publicCar, style: .compact)
                    .font(.body)
            }
            Button(action: onOpenComments) {
                Label(commentCount == 1 ? "1 comment" : "\(commentCount) comments", systemImage: "bubble.left")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            Spacer()
        }
    }
}

// MARK: - Presenters

struct CommentsSheetRequest: Identifiable {
    let id = UUID()
    let carId: String
    let carOwnerUID: String
    let carName: String
    let focusComposer: Bool
}

enum CarReportTarget: Identifiable {
    case car(PublicCar)
    case sound(PublicCar)
    case comment(CarComment, carId: String)

    var id: String {
        switch self {
        case .car(let c): return "car-\(c.carId)"
        case .sound(let c): return "sound-\(c.carId)"
        case .comment(let comment, let carId): return "comment-\(carId)-\(comment.id)"
        }
    }
}

/// Sheets and alerts for the social features of the car page, grouped into
/// one modifier for the type checker.
struct CarSocialPresenters: ViewModifier {
    @Binding var commentsRequest: CommentsSheetRequest?
    @Binding var reportTarget: CarReportTarget?
    @Binding var showingPushPrePrompt: Bool
    @Binding var showingMakePrivateConfirmation: Bool
    @Binding var commentActionError: String?
    @Binding var blockTarget: UserRef?
    @Binding var profileTarget: UserRef?
    let onConfirmMakePrivate: () -> Void

    func body(content: Content) -> some View {
        content
            .sheet(item: $commentsRequest) { request in
                CommentsSheet(
                    carId: request.carId,
                    carOwnerUID: request.carOwnerUID,
                    carName: request.carName,
                    focusComposerOnAppear: request.focusComposer
                )
            }
            .sheet(item: $reportTarget) { target in
                reportView(for: target)
            }
            .sheet(item: $profileTarget) { user in
                NavigationStack {
                    PublicProfileView(ownerUID: user.uid, ownerUsername: user.username)
                }
            }
            .modifier(BlockUserConfirmation(target: $blockTarget))
            .pushPrePrompt(isPresented: $showingPushPrePrompt)
            .alert("Make this car private?", isPresented: $showingMakePrivateConfirmation) {
                Button("Make Private", role: .destructive, action: onConfirmMakePrivate)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("It will be removed from Explore and your public profile. Likes and comments will be hidden until you make it public again.")
            }
            .alert("Something Went Wrong", isPresented: Binding(
                get: { commentActionError != nil },
                set: { if !$0 { commentActionError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(commentActionError ?? "")
            }
    }

    @ViewBuilder
    private func reportView(for target: CarReportTarget) -> some View {
        switch target {
        case .car(let car):
            ReportView(title: "Report Car", reportedUID: car.ownerUID, contentId: ReportContent.car(carId: car.carId),
                       reportedUsername: car.ownerUsername)
        case .sound(let car):
            ReportView(title: "Report Sound", reportedUID: car.ownerUID, contentId: ReportContent.engineSound(carId: car.carId),
                       reportedUsername: car.ownerUsername)
        case .comment(let comment, let carId):
            ReportView(
                title: "Report Comment",
                reportedUID: comment.authorUID,
                contentId: ReportContent.comment(carId: carId, commentId: comment.documentID ?? comment.id),
                reportedUsername: comment.authorUsername
            )
        }
    }
}

/// Keeps `CommentStore` listening to this page's car. The store holds one
/// car at a time, so a car page opened on top of this one (pushed, or in a
/// sheet) takes it over; this re-attaches when that page goes away, and only
/// stops the listener if it's still this car's.
struct CommentsListenerLifecycle: ViewModifier {
    /// nil when the car has no comments to show (a private own car).
    let carId: String?

    @EnvironmentObject private var commentStore: CommentStore
    @State private var isOnScreen = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                isOnScreen = true
                attach()
            }
            .onDisappear {
                isOnScreen = false
                if let carId, commentStore.carId == carId {
                    commentStore.stopListeningToCar()
                }
            }
            .onChange(of: carId) { oldValue, _ in
                if let oldValue, commentStore.carId == oldValue {
                    commentStore.stopListeningToCar()
                }
                attach()
            }
            .onChange(of: commentStore.carId) { _, newValue in
                if newValue == nil { attach() }
            }
    }

    private func attach() {
        guard isOnScreen, let carId, commentStore.carId != carId else { return }
        commentStore.listen(to: carId)
    }
}
