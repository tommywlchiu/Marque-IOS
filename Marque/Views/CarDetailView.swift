import SwiftUI

/// Unified detail view that handles both the user's own car (full edit / delete /
/// expense / reminder / maintenance controls) and another user's public car
/// (owner row + report button, hides private fields).
struct CarDetailView: View {
    @EnvironmentObject var carStore: CarStore
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var exploreStore: ExploreStore
    @EnvironmentObject var blockStore: BlockStore
    @EnvironmentObject var commentStore: CommentStore
    @Environment(\.dismiss) var dismiss

    // Exactly one of these is non-nil. Own car is @State so mutations sync to UI.
    @State private var ownCar: Car?
    private let publicCar: PublicCar?

    @State private var showingEditDetails = false
    @State private var showingDeleteConfirmation = false
    @State private var maintenanceAddRequest: MaintenanceAddRequest?
    @State private var reportTarget: CarReportTarget?
    @State private var showingOwnerProfile = false
    @State private var galleryStartIndex: Int?
    @State private var editingMaintenanceRecord: MaintenanceRecord?

    // Post-log confirmation banner (MaintenanceLogFlow / LogConfirmationOverlay)
    // and the "current mileage?" check-in card (see `dismissedMileageCheckIn`).
    @State private var logConfirmation: LogConfirmation?
    @State private var dismissedMileageCheckIn = false
    @State private var mileageCheckInText = ""

    // Focused-sheet add/edit flows — one per section. Consolidated with the
    // above state to make it obvious that every "add/edit" surface here is a
    // sheet, not a full-form drop-in or a navigation push.
    @State private var showingEditRegistration = false
    @State private var showingEditVehicleDetails = false
    @State private var showingEditInsurance = false
    @State private var showingAddReminder = false

    // Social: comments sheet, push pre-prompt, going-private confirmation.
    @State private var commentsRequest: CommentsSheetRequest?
    @State private var showingPushPrePrompt = false
    @State private var showingMakePrivateConfirmation = false
    @State private var showingSharingSheet = false
    @State private var sharingSheetMode: PublicSharingSheetMode = .goingPublic
    @State private var commentActionError: String?
    @State private var blockTarget: UserRef?
    @State private var commentProfileTarget: UserRef?
    /// Opens the comments sheet once on appear (a comment push/notification).
    @State private var openCommentsOnAppear: Bool
    @State private var showingShareCard = false

    init(car: Car, openComments: Bool = false) {
        self._ownCar = State(initialValue: car)
        self.publicCar = nil
        self._openCommentsOnAppear = State(initialValue: openComments)
    }

    init(publicCar: PublicCar) {
        self._ownCar = State(initialValue: nil)
        self.publicCar = publicCar
        self._openCommentsOnAppear = State(initialValue: false)
    }

    // MARK: - Mode helpers

    private var isOwnCar: Bool { ownCar != nil }

    /// The live `Car` for own-car mode — pulled from `carStore` so external updates
    /// (Firestore listener, photo upload) flow into the UI.
    private var liveCar: Car? {
        guard let car = ownCar else { return nil }
        return carStore.cars.first(where: { $0.id == car.id }) ?? car
    }

    // MARK: - Common accessors

    private var displayName: String {
        liveCar?.displayName ?? publicCar?.displayName ?? ""
    }
    private var make: String { liveCar?.make ?? publicCar?.make ?? "" }
    private var model: String { liveCar?.model ?? publicCar?.model ?? "" }
    private var year: String { liveCar?.year ?? publicCar?.year ?? "" }
    private var color: String { liveCar?.color ?? publicCar?.color ?? "" }
    private var mileage: String { liveCar?.mileage ?? publicCar?.mileage ?? "" }
    private var trim: String { liveCar?.trim ?? publicCar?.trim ?? "" }
    private var bodyStyle: String { liveCar?.bodyStyle ?? publicCar?.bodyStyle ?? "" }
    private var driveType: String { liveCar?.driveType ?? publicCar?.driveType ?? "" }
    private var engine: String { liveCar?.engine ?? publicCar?.engine ?? "" }
    private var fuelType: String { liveCar?.fuelType ?? publicCar?.fuelType ?? "" }
    private var transmission: String { liveCar?.transmission ?? publicCar?.transmission ?? "" }
    private var notes: String { liveCar?.notes ?? publicCar?.notes ?? "" }

    // MARK: - Social accessors

    /// The latest copy of the public car (Explore's live feed or Top Cars),
    /// so like/comment counts update while the page is open.
    private var livePublicCar: PublicCar? {
        guard let pc = publicCar else { return nil }
        return exploreStore.cars.first(where: { $0.carId == pc.carId }) ?? pc
    }

    /// The owner's own car as it appears publicly, if Explore has it loaded.
    private var ownPublicCar: PublicCar? {
        guard let car = liveCar else { return nil }
        return OwnCarPublicProjection.publishedCopy(of: car, in: exploreStore)
    }

    /// publicCars doc id whose comments this page shows; nil for a private own car.
    private var commentsCarId: String? {
        if let pc = publicCar { return pc.carId }
        guard let car = liveCar, car.isPublic else { return nil }
        return car.id.uuidString
    }

    private var commentsOwnerUID: String {
        publicCar?.ownerUID ?? authService.currentUser?.id ?? ""
    }

    private var serverCommentCount: Int {
        (livePublicCar ?? ownPublicCar)?.commentCount ?? 0
    }

    /// Loaded, block-filtered count when the whole thread is loaded; the
    /// server count otherwise.
    private var displayedCommentCount: Int {
        guard let id = commentsCarId, commentStore.carId == id, !commentStore.isLoading else {
            return serverCommentCount
        }
        let visible = commentStore.visibleComments(hiding: blockStore.blockedUIDs).count
        return commentStore.comments.count >= CommentStore.pageLimit ? max(serverCommentCount, visible) : visible
    }

    private func openComments(focusComposer: Bool) {
        guard let id = commentsCarId else { return }
        commentsRequest = CommentsSheetRequest(
            carId: id,
            carOwnerUID: commentsOwnerUID,
            carName: displayName,
            focusComposer: focusComposer
        )
    }

    // MARK: - Share card

    /// The FR-06.3 public projection `ShareCardSheet`/`CarShareCard` are built
    /// from (see `OwnCarPublicProjection.shareCard` for the own-car rules).
    private var shareCardProjection: PublicCar? {
        if let car = liveCar {
            return OwnCarPublicProjection.shareCard(for: car, exploreStore: exploreStore, authService: authService)
        }
        return livePublicCar ?? publicCar
    }

    private func offerPushPrePrompt() {
        PushPrePrompt.offer { showingPushPrePrompt = true }
    }

    // MARK: - Body

    var body: some View {
        List {
            photoHeaderSection

            if let pc = livePublicCar {
                ownerRowSection(for: pc)
                PublicCarHighlightsSection(
                    car: pc,
                    commentCount: displayedCommentCount,
                    onLiked: offerPushPrePrompt,
                    onOpenComments: { openComments(focusComposer: false) }
                )
            }

            if let car = liveCar, car.hasExpiryWarning {
                expiryAlertBanner(for: car)
            }

            mileageCheckInSection

            if liveCar != nil {
                visibilitySection
            }

            BasicInfoSection(make: make, model: model, year: year)

            if let car = liveCar {
                RegistrationSection(car: car) { showingEditRegistration = true }
                VehicleDetailsSection(specs: VehicleSpecs(car: car)) { showingEditVehicleDetails = true }
                InsuranceSection(car: car) { showingEditInsurance = true }
                CarModsSection(car: car)
                CarValueSection(car: car)
                EngineSoundOwnerSection(car: car)
            } else {
                if let pc = publicCar, !VehicleSpecs(publicCar: pc).isEmpty {
                    VehicleDetailsSection(specs: VehicleSpecs(publicCar: pc))
                }
                if let pc = publicCar, !pc.mods.isEmpty {
                    PublicCarModsSection(mods: pc.mods)
                }
            }

            if !notes.isEmpty {
                Section(header: Text("Notes")) {
                    Text(notes).font(.body)
                }
            }

            if let car = liveCar, car.totalExpenses > 0 {
                ExpenseSummarySection(car: car)
            }

            if let car = liveCar {
                remindersSection
                MaintenanceLogSection(
                    car: car,
                    onAdd: { maintenanceAddRequest = MaintenanceAddRequest() },
                    onEdit: { editingMaintenanceRecord = $0 }
                )
            } else if let pc = publicCar, !pc.serviceHistory.isEmpty {
                publicServiceHistorySection(for: pc)
            }

            if let id = commentsCarId {
                CarCommentsSection(
                    carId: id,
                    carOwnerUID: commentsOwnerUID,
                    serverCount: serverCommentCount,
                    onOpenComments: { openComments(focusComposer: $0) },
                    callbacks: CommentCallbacks(
                        onReport: { reportTarget = .comment($0, carId: id) },
                        onBlock: { blockTarget = $0 },
                        onOpenProfile: { commentProfileTarget = $0 },
                        onDeleteError: { commentActionError = $0 }
                    )
                )
            }

            if isOwnCar {
                deleteSection
            }
        }
        .navigationTitle("Car Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if isOwnCar {
                    Button("Edit") { showingEditDetails = true }
                } else if let pc = livePublicCar {
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
            if let projection = shareCardProjection {
                ShareCardSheet(
                    car: projection,
                    localCoverPhotoFileName: isOwnCar ? liveCar?.primaryPhotoFileName : nil,
                    isOwnCar: isOwnCar
                )
            }
        }
        .sheet(isPresented: $showingEditDetails) {
            if let car = ownCar {
                EditCarDetailView(car: ownCarBinding(initial: car), onSave: { updatedCar in
                    ownCar = updatedCar
                    carStore.updateCar(updatedCar)
                })
            }
        }
        .modifier(PublicSharingSheetPresenter(
            car: liveCar,
            mode: sharingSheetMode,
            isPresented: $showingSharingSheet,
            onMadePublic: offerPushPrePrompt
        ))
        .modifier(MaintenanceLogFlow(
            carID: ownCar?.id ?? UUID(),
            addRequest: $maintenanceAddRequest,
            editingRecord: $editingMaintenanceRecord,
            logConfirmation: $logConfirmation
        ))
        .modifier(FocusedEditPresenters(
            liveCar: liveCar,
            showingEditRegistration: $showingEditRegistration,
            showingEditVehicleDetails: $showingEditVehicleDetails,
            showingEditInsurance: $showingEditInsurance,
            showingAddReminder: $showingAddReminder,
            onSave: { updated in
                ownCar = updated
                carStore.updateCar(updated)
            }
        ))
        .sheet(isPresented: $showingOwnerProfile) {
            if let pc = publicCar {
                NavigationStack {
                    PublicProfileView(ownerUID: pc.ownerUID, ownerUsername: pc.ownerUsername)
                        .environmentObject(exploreStore)
                        .environmentObject(blockStore)
                }
            }
        }
        .modifier(CarSocialPresenters(
            commentsRequest: $commentsRequest,
            reportTarget: $reportTarget,
            showingPushPrePrompt: $showingPushPrePrompt,
            showingMakePrivateConfirmation: $showingMakePrivateConfirmation,
            commentActionError: $commentActionError,
            blockTarget: $blockTarget,
            profileTarget: $commentProfileTarget,
            onConfirmMakePrivate: { applyVisibility(false) }
        ))
        .modifier(CommentsListenerLifecycle(carId: commentsCarId))
        .onAppear {
            guard openCommentsOnAppear else { return }
            openCommentsOnAppear = false
            openComments(focusComposer: false)
        }
        .fullScreenCover(item: Binding(
            get: { galleryStartIndex.map(GalleryStart.init) },
            set: { galleryStartIndex = $0?.index }
        )) { start in
            galleryViewer(startIndex: start.index)
        }
        .alert("Delete Car", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let car = liveCar {
                    carStore.deleteCar(car)
                }
                dismiss()
            }
        } message: {
            Text("Are you sure you want to delete \(displayName)? This action cannot be undone.")
        }
        .overlay(alignment: .bottomTrailing) {
            // Hidden while the log confirmation shows: they share the bottom edge,
            // and the button was taking taps meant for the banner's Undo.
            if let car = liveCar, logConfirmation == nil {
                AskMarqueButton(scopedCarId: car.id.uuidString)
                    .padding(.trailing, 16)
                    .padding(.bottom, 16)
            }
        }
        .modifier(LogConfirmationOverlay(carID: ownCar?.id ?? UUID(), confirmation: $logConfirmation))
    }

    // EditCarDetailView wants a Binding<Car>; thread it through @State ownCar.
    private func ownCarBinding(initial: Car) -> Binding<Car> {
        Binding(
            get: { ownCar ?? initial },
            set: { ownCar = $0 }
        )
    }

    // MARK: - Photo header (shared, edge-to-edge in the list)

    private var photoHeaderSection: some View {
        Section {
            VStack(spacing: 12) {
                photoHeaderContent
                Text(displayName)
                    .font(.title2).fontWeight(.bold)
                    .multilineTextAlignment(.center)
                // Public page only (FR ask): the owner already sees their mod
                // count in the Mods section header just below.
                if let pc = publicCar, pc.isModified {
                    ModifiedPill()
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder
    private var photoHeaderContent: some View {
        if let car = liveCar, let fileName = car.primaryPhotoFileName {
            ZStack(alignment: .bottomTrailing) {
                CarPhotoImage(fileName: fileName, storageURL: car.primaryPhotoStorageURL)
                    .frame(maxWidth: .infinity).frame(height: 200)
                    .offset(y: car.photoOffsetY)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                    .onTapGesture { galleryStartIndex = 0 }

                if car.hasMultiplePhotos {
                    photoCountBadge(count: car.photoFileNames.count)
                }
            }

            if car.hasMultiplePhotos {
                photoThumbnailStrip(for: car)
            }
        } else if let pc = livePublicCar {
            PublicCarPhotoHeader(car: pc) { galleryStartIndex = $0 }
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.accentColor.opacity(0.08))
                    .frame(height: 120)
                VStack(spacing: 8) {
                    Image(systemName: "car.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.accentColor.opacity(0.4))
                    if isOwnCar {
                        Text("Tap Edit to add a photo")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private func photoCountBadge(count: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "photo.stack").font(.caption2)
            Text("\(count)").font(.caption).fontWeight(.semibold)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color.black.opacity(0.55))
        .clipShape(Capsule())
        .padding(10)
    }

    private func photoThumbnailStrip(for car: Car) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(car.photoFileNames.enumerated()), id: \.offset) { index, fileName in
                    Button {
                        galleryStartIndex = index
                    } label: {
                        CarPhotoImage(fileName: fileName, storageURL: car.storageURL(at: index))
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2).padding(.top, 4)
        }
    }

    @ViewBuilder
    private func galleryViewer(startIndex: Int) -> some View {
        if let car = liveCar {
            PhotoGalleryView(
                photoFileNames: car.photoFileNames,
                photoStorageURLs: car.photoStorageURLs,
                initialIndex: startIndex,
                onSetCover: { index in
                    // Re-read the car at tap time; the gallery may have been open a while.
                    guard let current = liveCar, index < current.photoFileNames.count else { return }
                    carStore.setCoverPhoto(fileName: current.photoFileNames[index], for: current)
                }
            )
        } else if let pc = livePublicCar, !pc.galleryURLs.isEmpty {
            PhotoGalleryView(
                photoFileNames: [],
                photoStorageURLs: pc.galleryURLs.map(\.absoluteString),
                initialIndex: startIndex
            )
        }
    }

    // MARK: - Owner row (public only)

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

    // MARK: - Expiry banner (own only)

    private func expiryAlertBanner(for car: Car) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                if car.isRegistrationExpired {
                    ExpiryBannerItem(icon: "exclamationmark.triangle.fill", text: "Registration has expired", color: .red)
                } else if car.isRegistrationExpiringSoon {
                    ExpiryBannerItem(icon: "clock.badge.exclamationmark", text: "Registration expiring soon", color: .orange)
                }
                if car.isInsuranceExpired {
                    ExpiryBannerItem(icon: "exclamationmark.triangle.fill", text: "Insurance has expired", color: .red)
                } else if car.isInsuranceExpiringSoon {
                    ExpiryBannerItem(icon: "clock.badge.exclamationmark", text: "Insurance expiring soon", color: .orange)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Mileage check-in (own only)

    // Shown when the car has an open mileage-triggered reminder and its
    // mileage hasn't been touched (or was touched over 30 days ago) — those
    // reminders can never fire a local notification on their own, so this is
    // the periodic nudge that keeps them accurate.
    private var shouldShowMileageCheckIn: Bool {
        guard !dismissedMileageCheckIn, let car = liveCar, car.hasOpenMileageReminders else { return false }
        guard let updatedAt = car.mileageUpdatedAt else { return true }
        return Date().timeIntervalSince(updatedAt) > 30 * 24 * 60 * 60
    }

    @ViewBuilder
    private var mileageCheckInSection: some View {
        if shouldShowMileageCheckIn, let car = liveCar {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Current mileage?")
                            .font(.subheadline).fontWeight(.semibold)
                        Spacer()
                        Button {
                            withAnimation { dismissedMileageCheckIn = true }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Dismiss")
                    }

                    HStack(spacing: 10) {
                        TextField("Mileage", text: $mileageCheckInText)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)

                        Button("Update") {
                            let digitsOnly = mileageCheckInText.replacingOccurrences(of: ",", with: "")
                            guard let value = Int(digitsOnly) else { return }
                            carStore.updateMileage(value, for: car)
                            mileageCheckInText = ""
                            withAnimation { dismissedMileageCheckIn = true }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(Int(mileageCheckInText.replacingOccurrences(of: ",", with: "")) == nil)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Visibility toggle (own only)

    @ViewBuilder
    private var visibilitySection: some View {
        if let car = liveCar {
            CarVisibilitySection(
                car: car,
                onRequestPublic: {
                    sharingSheetMode = .goingPublic
                    showingSharingSheet = true
                },
                onRequestPrivate: { showingMakePrivateConfirmation = true },
                onEditSharing: {
                    sharingSheetMode = .editing
                    showingSharingSheet = true
                }
            ) {
                OwnCarEngagementRow(
                    publicCar: ownPublicCar,
                    commentCount: displayedCommentCount,
                    onOpenComments: { openComments(focusComposer: false) }
                )
            }
        }
    }

    private func applyVisibility(_ isPublic: Bool) {
        guard let car = liveCar else { return }
        if CarVisibilityActions.apply(isPublic, to: car, carStore: carStore, authService: authService) {
            offerPushPrePrompt()
        }
    }

    // MARK: - Reminders (own only)

    private var remindersSection: some View {
        Section(header: AddSectionHeader(title: "Service Reminders") { showingAddReminder = true }) {
            if let car = liveCar {
                let upcoming = car.serviceReminders.filter { !$0.isCompleted }
                let currentMileage = ServiceReminderEngine.mileage(from: car.mileage)
                let overdueCount = upcoming.filter { $0.status(currentMileage: currentMileage) == .overdue }.count

                if upcoming.isEmpty && car.serviceReminders.isEmpty {
                    EmptySectionRow(title: "Add Reminder", systemImage: "wrench.and.screwdriver") {
                        showingAddReminder = true
                    }
                } else {
                    NavigationLink(destination: ServiceRemindersView(carID: car.id)) {
                        HStack {
                            Image(systemName: overdueCount > 0 ? "exclamationmark.circle.fill" : "wrench.and.screwdriver")
                                .foregroundColor(overdueCount > 0 ? .red : .accentColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(upcoming.isEmpty ? "\(car.serviceReminders.count) Completed" : "\(upcoming.count) Upcoming")
                                    .font(.subheadline)
                                if overdueCount > 0 {
                                    Text("\(overdueCount) overdue").font(.caption).foregroundColor(.red)
                                }
                            }
                        }
                    }
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

    // MARK: - Delete Car (own only)

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                HStack {
                    Spacer()
                    Label("Delete Car", systemImage: "trash")
                    Spacer()
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

struct ExpiryBannerItem: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundColor(color).font(.subheadline)
            Text(text).font(.subheadline).fontWeight(.medium).foregroundColor(color)
        }
    }
}

struct ExpiryRow: View {
    let label: String
    let date: Date
    let isExpired: Bool
    let isExpiringSoon: Bool

    private var statusColor: Color {
        if isExpired { return .red }
        if isExpiringSoon { return .orange }
        return .primary
    }

    private var daysText: String {
        let days = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0
        if days < 0 { return "Expired" }
        if days == 0 { return "Expires today" }
        if days == 1 { return "Expires tomorrow" }
        return "Expires in \(days) days"
    }

    var body: some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            // Copies the date as displayed, not the "Expires in N days" caption.
            CopyableValue(label: label, copyText: date.formatted(date: .long, time: .omitted)) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(date, style: .date).foregroundColor(statusColor)
                    if isExpired || isExpiringSoon {
                        Text(daysText).font(.caption).fontWeight(.medium).foregroundColor(statusColor)
                    }
                }
            }
        }
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
