import SwiftUI

/// Another user's public car (or your own, as Explore shows it): owner row,
/// likes/comments, the shared specs, mods and service history. Never the
/// private fields — it only ever holds a `PublicCar`. The owner manages their
/// own car in the Garage tab.
struct CarDetailView: View {
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var exploreStore: ExploreStore
    @EnvironmentObject var blockStore: BlockStore
    @EnvironmentObject var commentStore: CommentStore

    private let publicCar: PublicCar

    @State private var reportTarget: CarReportTarget?
    @State private var showingOwnerProfile = false
    @State private var galleryStartIndex: Int?

    // Social: comments sheet, push pre-prompt.
    @State private var commentsRequest: CommentsSheetRequest?
    @State private var showingPushPrePrompt = false
    @State private var commentActionError: String?
    @State private var blockTarget: UserRef?
    @State private var commentProfileTarget: UserRef?
    @State private var showingShareCard = false

    init(publicCar: PublicCar) {
        self.publicCar = publicCar
    }

    /// The latest copy of the public car (Explore's live feed or Top Cars),
    /// so like/comment counts update while the page is open.
    private var livePublicCar: PublicCar {
        exploreStore.cars.first(where: { $0.carId == publicCar.carId })
            ?? exploreStore.topCarsAllTime.first(where: { $0.carId == publicCar.carId })
            ?? publicCar
    }

    private var isOwnCar: Bool { publicCar.ownerUID == authService.currentUser?.id }

    /// Loaded, block-filtered count when the whole thread is loaded; the
    /// server count otherwise.
    private var displayedCommentCount: Int {
        let serverCount = livePublicCar.commentCount
        guard commentStore.carId == publicCar.carId, !commentStore.isLoading else { return serverCount }
        let visible = commentStore.visibleComments(hiding: blockStore.blockedUIDs).count
        return commentStore.comments.count >= CommentStore.pageLimit ? max(serverCount, visible) : visible
    }

    private func openComments(focusComposer: Bool) {
        commentsRequest = CommentsSheetRequest(
            carId: publicCar.carId,
            carOwnerUID: publicCar.ownerUID,
            carName: publicCar.displayName,
            focusComposer: focusComposer
        )
    }

    // MARK: - Body

    var body: some View {
        let pc = livePublicCar
        List {
            photoHeaderSection(for: pc)
            ownerRowSection(for: pc)
            PublicCarHighlightsSection(
                car: pc,
                commentCount: displayedCommentCount,
                onLiked: { PushPrePrompt.offer { showingPushPrePrompt = true } },
                onOpenComments: { openComments(focusComposer: false) }
            )

            BasicInfoSection(make: pc.make, model: pc.model, year: pc.year)
            if !VehicleSpecs(publicCar: pc).isEmpty {
                VehicleDetailsSection(specs: VehicleSpecs(publicCar: pc))
            }
            if !pc.mods.isEmpty {
                PublicCarModsSection(mods: pc.mods)
            }
            if !pc.notes.isEmpty {
                Section(header: Text("Notes")) {
                    Text(pc.notes).font(.body)
                }
            }
            if !pc.serviceHistory.isEmpty {
                publicServiceHistorySection(for: pc)
            }

            CarCommentsSection(
                carId: pc.carId,
                carOwnerUID: pc.ownerUID,
                serverCount: pc.commentCount,
                onOpenComments: { openComments(focusComposer: $0) },
                callbacks: CommentCallbacks(
                    onReport: { reportTarget = .comment($0, carId: pc.carId) },
                    onBlock: { blockTarget = $0 },
                    onOpenProfile: { commentProfileTarget = $0 },
                    onDeleteError: { commentActionError = $0 }
                )
            )
        }
        .navigationTitle("Car Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if !isOwnCar {
                    Menu {
                        Button(role: .destructive) { reportTarget = .car(pc) } label: {
                            Label("Report Car", systemImage: "flag")
                        }
                        if pc.engineSoundPlaybackURL != nil {
                            Button(role: .destructive) { reportTarget = .sound(pc) } label: {
                                Label("Report Sound", systemImage: "waveform.badge.exclamationmark")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("More")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingShareCard = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share car")
            }
        }
        .sheet(isPresented: $showingShareCard) {
            ShareCardSheet(car: pc, localCoverPhotoFileName: nil, isOwnCar: isOwnCar)
        }
        .sheet(isPresented: $showingOwnerProfile) {
            NavigationStack {
                PublicProfileView(ownerUID: pc.ownerUID, ownerUsername: pc.ownerUsername)
                    .environmentObject(exploreStore)
                    .environmentObject(blockStore)
            }
        }
        .modifier(CarSocialPresenters(
            commentsRequest: $commentsRequest,
            reportTarget: $reportTarget,
            showingPushPrePrompt: $showingPushPrePrompt,
            showingMakePrivateConfirmation: .constant(false),
            commentActionError: $commentActionError,
            blockTarget: $blockTarget,
            profileTarget: $commentProfileTarget,
            onConfirmMakePrivate: {}
        ))
        .modifier(CommentsListenerLifecycle(carId: publicCar.carId))
        .fullScreenCover(item: Binding(
            get: { galleryStartIndex.map(GalleryStart.init) },
            set: { galleryStartIndex = $0?.index }
        )) { start in
            if !pc.galleryURLs.isEmpty {
                PhotoGalleryView(
                    photoFileNames: [],
                    photoStorageURLs: pc.galleryURLs.map(\.absoluteString),
                    initialIndex: start.index
                )
            }
        }
    }

    // MARK: - Photo header

    private func photoHeaderSection(for pc: PublicCar) -> some View {
        Section {
            VStack(spacing: 12) {
                PublicCarPhotoHeader(car: pc) { galleryStartIndex = $0 }
                Text(pc.displayName)
                    .font(.title2).fontWeight(.bold)
                    .multilineTextAlignment(.center)
                if pc.isModified {
                    ModifiedPill()
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .listRowBackground(Color.clear)
        }
    }

    // MARK: - Owner row

    private func ownerRowSection(for pc: PublicCar) -> some View {
        Section {
            Button { showingOwnerProfile = true } label: {
                HStack(spacing: 12) {
                    OwnerAvatar(avatarURL: pc.ownerAvatarURL, username: pc.ownerUsername, size: 40)
                    Text("@\(pc.ownerUsername)")
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption).foregroundColor(.secondary.opacity(0.5))
                }
            }
        }
    }

    // MARK: - Service History (public — no costs)

    private func publicServiceHistorySection(for pc: PublicCar) -> some View {
        Section(header: HStack {
            Text("Service History")
            Spacer()
            Text("\(pc.serviceHistory.count) records")
                .font(.caption).foregroundColor(.secondary)
        }) {
            ForEach(pc.serviceHistory.sorted { $0.date > $1.date }.prefix(5)) { record in
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.serviceType)
                        .font(.subheadline).fontWeight(.medium)
                    Text(record.date, style: .date)
                        .font(.caption).foregroundColor(.secondary)
                }
            }
        }
    }
}

// MARK: - Supporting Views

private struct GalleryStart: Identifiable {
    let index: Int
    var id: Int { index }
}

/// Post-log confirmation state (see `CarDetailView.presentLogConfirmation`).
/// `id` is a fresh UUID per presentation so a delayed auto-dismiss Task from
/// an earlier banner can't clear a newer one.
/// A post-log confirmation: its message plus what Undo reverses. Shared by the
/// car page's Maintenance Log and the Service Reminders check-off flow.
struct LogConfirmation: Identifiable {
    let id = UUID()
    let message: String
    let outcome: CarStore.ServiceLogOutcome

    // Shows only the parts that actually happened, per the product spec:
    // "Oil Change logged · Reminder completed · Next due Mar 2027 / 32,000 mi".
    init(logged record: MaintenanceRecord, outcome: CarStore.ServiceLogOutcome) {
        var parts = ["\(record.serviceType) logged"]
        if !outcome.completedReminderIDs.isEmpty {
            parts.append("Reminder completed")
        }
        if let next = outcome.scheduledNext {
            parts.append("Next due \(Self.nextDueDescription(next))")
        }
        if outcome.previousMileage != nil, let mileageValue = record.mileageValue {
            parts.append("Mileage updated to \(mileageValue.formatted())")
        }
        self.message = parts.joined(separator: " · ")
        self.outcome = outcome
    }

    /// "Skip — just mark done": the reminder was completed without a record.
    init(markedDone reminder: ServiceReminder, next: ServiceReminder?) {
        var parts = ["\(reminder.serviceType) marked done"]
        if let next {
            parts.append("Next due \(Self.nextDueDescription(next))")
        }
        self.message = parts.joined(separator: " · ")
        self.outcome = CarStore.ServiceLogOutcome(
            completedReminderIDs: [reminder.id], scheduledNext: next, previousMileage: nil
        )
    }

    private static func nextDueDescription(_ reminder: ServiceReminder) -> String {
        var parts: [String] = []
        if let date = reminder.dueDate {
            parts.append(date.formatted(.dateTime.month(.abbreviated).year()))
        }
        if let miles = reminder.dueMileage {
            parts.append("\(miles.formatted()) mi")
        }
        return parts.joined(separator: " / ")
    }
}

/// Bottom-anchored toast shown after logging a service record. Auto-dismiss
/// timing lives in the caller; this view only renders the message + Undo.
struct LogConfirmationBanner: View {
    let message: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button("Undo", action: onUndo)
                .font(.subheadline).fontWeight(.semibold)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
    }
}

struct MaintenanceRowView: View {
    let record: MaintenanceRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(record.serviceType).font(.subheadline).fontWeight(.medium)
                if record.receiptFileName != nil || record.receiptStorageURL != nil {
                    Image(systemName: "paperclip")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                // Parsed values, so "$49.99" or "25,000 mi" typed into the free-text
                // fields don't render as "$$49.99" / "25,000 mi mi".
                if let cost = record.costValue {
                    Text(cost, format: .currency(code: "USD"))
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundColor(.accentColor)
                }
            }

            HStack(spacing: 12) {
                Text(record.date, style: .date).font(.caption).foregroundColor(.secondary)
                if let miles = record.mileageValue {
                    Text("\(miles.formatted()) mi").font(.caption).foregroundColor(.secondary)
                }
                if !record.shop.isEmpty {
                    Text(record.shop).font(.caption).foregroundColor(.secondary)
                }
            }

            if !record.notes.isEmpty {
                Text(record.notes)
                    .font(.caption).foregroundColor(.secondary.opacity(0.8))
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
}

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            if value.isEmpty {
                Text("—").foregroundColor(.secondary.opacity(0.5))
            } else {
                CopyableValue(label: label, copyText: value) {
                    Text(value)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }
}

/// Tap (or long-press > Copy) to copy `copyText`, with a haptic and a brief
/// "Copied" confirmation swapped in for the content.
private struct CopyableValue<Content: View>: View {
    let label: String
    let copyText: String
    @ViewBuilder let content: Content

    @State private var showingCopied = false

    var body: some View {
        Button(action: copy) {
            if showingCopied {
                Label("Copied", systemImage: "checkmark")
                    .foregroundColor(.green)
            } else {
                content
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { copy() } label: { Label("Copy", systemImage: "doc.on.doc") }
        }
        .accessibilityLabel("\(label), \(copyText)")
        .accessibilityHint("Double-tap to copy")
    }

    private func copy() {
        UIPasteboard.general.string = copyText
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.easeInOut(duration: 0.15)) { showingCopied = true }
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation(.easeInOut(duration: 0.15)) { showingCopied = false }
        }
    }
}
