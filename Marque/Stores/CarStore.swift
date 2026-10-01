import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import Network
import UIKit

@MainActor
class CarStore: ObservableObject {
    @Published var cars: [Car] = []
    @Published var isOffline = false

    /// FR-08.1 free-tier car limit. Display and client-gate copy only: the
    /// server enforces it in firestore.rules (`users/{uid}/cars` create,
    /// `carCount < 2`). Change both together.
    static let freeCarLimit = 2

    // FR-08.8: flips true when a car create is denied server-side for being
    // over the free car limit (Pro and active Family Sharing are
    // unlimited — see firestore.rules `users/{uid}/cars/{carId}` create).
    // This is the server's word, independent of and a backstop to the
    // existing client-side gate (CarListView.atCarLimit / MainTabView's
    // copy): the client check can drift from what usage/limits.carCount
    // actually says (multi-device races, an offline-queued create that
    // wasn't counted yet), and the rule is what actually decides. The
    // frontend is expected to show the paywall on this and then call
    // clearCarLimitRejected().
    @Published var carLimitRejected = false

    private let db = Firestore.firestore()
    private let storage = Storage.storage()
    private var listener: ListenerRegistration?
    private var valuationsListener: ListenerRegistration?

    /// The signed-in user's AI valuations, keyed by car ID
    /// (`Car.id.uuidString`). Live: updates after every successful
    /// `estimateValue`. Read-only mirror of the server-only
    /// `users/{uid}/usage/valuation_{carId}` docs.
    @Published private(set) var aiValuations: [String: CarValuation] = [:]
    private var currentUserId: String?
    private var pendingUploads: [PendingUpload] = []

    // UID-scoped UserDefaults keys to prevent cross-user data leakage on shared devices.
    private func localKey(_ uid: String) -> String { "marque_saved_cars_\(uid)" }
    private func pendingUploadsKey(_ uid: String) -> String { "marque_pending_uploads_\(uid)" }

    private func carRef(userId: String, carId: String) -> DocumentReference {
        db.collection("users").document(userId).collection("cars").document(carId)
    }

    private func storageRef(userId: String, carId: String, fileName: String) -> StorageReference {
        storage.reference().child("users/\(userId)/cars/\(carId)/\(fileName)")
    }

    // Fixed object name: a replacement overwrites the previous clip. storage.rules
    // limits this one path to audio/* under 500 KB.
    private func soundStorageRef(userId: String, carId: String) -> StorageReference {
        storage.reference().child("users/\(userId)/cars/\(carId)/sound.m4a")
    }

    private func receiptStorageRef(userId: String, carId: String, fileName: String) -> StorageReference {
        storage.reference().child("users/\(userId)/cars/\(carId)/receipts/\(fileName)")
    }

    // Deterministic per-record Storage object name — re-uploading a receipt
    // for the same record overwrites the previous object rather than
    // orphaning it, so replace/edit needs no explicit delete-then-upload.
    private func receiptFileName(for recordId: UUID) -> String {
        "\(recordId.uuidString).jpg"
    }

    private func padURLs(_ urls: [String], to count: Int) -> [String] {
        guard count > urls.count else { return urls }
        return urls + Array(repeating: "", count: count - urls.count)
    }

    private let networkMonitor = NWPathMonitor()
    private let networkQueue = DispatchQueue(label: "com.marque.network")

    init() {
        // Firebase Auth restores currentUser synchronously after FirebaseApp.configure(),
        // so we can pre-load cached data instantly when relaunching for the same user.
        if let uid = Auth.auth().currentUser?.uid {
            loadLocal(uid: uid)
            loadPendingUploads(uid: uid)
        }
        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let wasOffline = self.isOffline
                self.isOffline = path.status != .satisfied
                if wasOffline && !self.isOffline {
                    await self.retryPendingUploads()
                }
            }
        }
        networkMonitor.start(queue: networkQueue)
    }

    deinit {
        networkMonitor.cancel()
    }

    // MARK: - Auth lifecycle

    func startListening(userId: String) {
        guard userId != currentUserId else { return }
        stopListening()
        currentUserId = userId
        loadLocal(uid: userId)
        loadPendingUploads(uid: userId)

        let ref = db.collection("users").document(userId).collection("cars")
        listener = ref.addSnapshotListener { [weak self] snapshot, _ in
            guard let self, let snapshot else { return }
            guard self.currentUserId == userId else { return }
            self.cars = snapshot.documents.compactMap { try? $0.data(as: Car.self) }
                .sorted { $0.displayName < $1.displayName }
            self.saveLocal()
        }

        valuationsListener = db.collection("users").document(userId).collection("usage")
            .whereField("kind", isEqualTo: "valuation")
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self, let snapshot, self.currentUserId == userId else { return }
                var map: [String: CarValuation] = [:]
                for doc in snapshot.documents {
                    let created = (doc.data(with: .estimate)["createdAt"] as? Timestamp)?.dateValue()
                    if let v = CarValuation(firestoreData: doc.data(), createdAt: created) { map[v.carId] = v }
                }
                self.aiValuations = map
            }

        // Upload photos that live on-device but were never synced to Firebase Storage
        // (e.g. added before Storage was set up, or upload previously failed).
        // Uses the local cache — fast on re-launch, no-op on first install.
        uploadMissingStoragePhotos()

        if !pendingUploads.isEmpty {
            Task { await retryPendingUploads() }
        }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
        valuationsListener?.remove()
        valuationsListener = nil
        aiValuations = [:]
        currentUserId = nil
        cars = []
        pendingUploads = []
        claimedPublicCarIDs = []
    }

    // MARK: - Car CRUD

    // `entryMethod` exists only to satisfy FR-11.4's `car_added.entry_method`.
    // The store cannot infer it — only the caller knows whether the user came
    // through the VIN lookup or typed the car in by hand — so it is optional and
    // the event is skipped entirely when it isn't supplied. A default of `.manual`
    // would be a guess, and a fabricated `entry_method` corrupts the activation
    // funnel R-01 depends on; a missing event is recoverable, a wrong one is not.
    func addCar(_ car: Car, entryMethod: AnalyticsService.CarEntryMethod? = nil) {
        guard let userId = currentUserId else {
            cars.append(car)
            saveLocal()
            reportCarAdded(entryMethod)
            return
        }
        // Report only if the car was actually handed to Firestore. `setData(from:)`
        // throws synchronously on Codable encoding failure — the network round
        // trip is async and offline-buffered, so this confirms the write was
        // enqueued, not that the server acked it.
        let ref = carRef(userId: userId, carId: car.id.uuidString)
        do {
            try ref.setData(from: car) { [weak self] error in
                guard let self, let error else { return }
                // The listener's next snapshot already drops this doc once
                // Firestore's own local-write rollback removes it from the
                // cache on any completion error — including one that only
                // surfaces after the write was queued while offline and
                // rejected once connectivity returns. Removing it here too is
                // a belt-and-suspenders guard against a ghost local car
                // surviving in the meantime, since that rollback is SDK
                // behavior this store doesn't directly control.
                self.cars.removeAll { $0.id == car.id }
                self.saveLocal()
                // A photo attached in the moments before the rejection landed is
                // queued for upload under this car's id; the car will never exist
                // server-side, so drop the queued uploads and their local files.
                let carId = car.id.uuidString
                for pending in self.pendingUploads where pending.carId == carId {
                    ImageManager.deleteImage(fileName: pending.fileName)
                }
                if self.pendingUploads.contains(where: { $0.carId == carId }) {
                    self.pendingUploads.removeAll { $0.carId == carId }
                    self.savePendingUploads()
                }
                let nsError = error as NSError
                if nsError.domain == FirestoreErrorDomain,
                   nsError.code == FirestoreErrorCode.permissionDenied.rawValue {
                    // FR-08.8: the free car cap, or a security-rule change
                    // that also denies this write — either way, the create
                    // did not go through.
                    self.carLimitRejected = true
                }
            }
        } catch {
            return
        }
        reportCarAdded(entryMethod)
    }

    /// Clears the FR-08.8 server-side denial flag once the caller has shown
    /// (or dismissed) the paywall in response to it.
    func clearCarLimitRejected() {
        carLimitRejected = false
    }

    // FR-11.4 `car_added`. Fire-and-forget: nothing here can alter the outcome
    // of the save above.
    private func reportCarAdded(_ entryMethod: AnalyticsService.CarEntryMethod?) {
        guard let entryMethod else { return }
        AnalyticsService.carAdded(entryMethod: entryMethod, secondsSinceSignup: Self.secondsSinceSignup())
    }

    // Serves the "time to first car added < 3 min" target in Section 9.
    // Firebase Auth's own account creation date is the signup timestamp for all
    // three auth methods (it is also what backs `AppUser.joinedDate`), so this
    // needs no cooperation from AuthService and keeps the stores decoupled.
    // Returns nil rather than a sentinel when the date is unavailable —
    // AnalyticsService omits the property in that case.
    private static func secondsSinceSignup() -> Int? {
        guard let created = Auth.auth().currentUser?.metadata.creationDate else { return nil }
        let elapsed = Date().timeIntervalSince(created)
        guard elapsed >= 0 else { return nil }
        return Int(elapsed)
    }

    func updateCar(_ car: Car) {
        guard let userId = currentUserId else {
            if let i = cars.firstIndex(where: { $0.id == car.id }) {
                cars[i] = car
                saveLocal()
            }
            return
        }
        let previous = cars.first(where: { $0.id == car.id })
        try? carRef(userId: userId, carId: car.id.uuidString).setData(from: car)
        // Keep the public copy in step with any edit that changes what Explore
        // shows: cover/crop, the photo gallery (reorder, removal), specs,
        // notes, service history, the public value range, the engine sound.
        // Only when the car was ALREADY public: a car that just became public
        // is written in full by setVisibility → syncPublicCar, and a private
        // car must never get a public copy. Edits that change nothing public
        // (VIN, insurance, costs, reminders) write nothing here.
        if car.isPublic, previous?.isPublic ?? true,
           previous.map({ publicProjectionChanged(from: $0, to: car) }) ?? true {
            pushPublicFields(of: car)
        }
    }

    /// Makes `fileName` the car's cover (first) photo. Reorders the local file
    /// names and their Storage URLs together, since they're parallel arrays,
    /// and resets the crop, which was set for the previous cover.
    func setCoverPhoto(fileName: String, for car: Car) {
        guard let index = car.photoFileNames.firstIndex(of: fileName), index != 0 else { return }
        var updated = car
        var names = car.photoFileNames
        var urls = padURLs(car.photoStorageURLs, to: names.count)
        names.insert(names.remove(at: index), at: 0)
        urls.insert(urls.remove(at: index), at: 0)
        updated.photoFileNames = names
        updated.photoStorageURLs = urls
        updated.photoOffsetY = 0
        updateCar(updated)
    }

    // MARK: - Public copy (publicCars/{carId})
    //
    // Every write here is a MERGE, never a full overwrite: the doc also carries
    // server-maintained counts (likeCount, weeklyLikeCount, commentCount) that
    // a non-merge setData would wipe (and firestore.rules now rejects any write
    // that touches them). Because Firestore's encoder omits nil optionals, a
    // merge alone can't clear a field that became nil, so publicPayload maps
    // those to FieldValue.delete() explicitly.

    /// The owner-written public fields for `car`, minus the owner's identity
    /// (ownerUsername/ownerAvatarURL: only setVisibility and
    /// AuthService.changeUsername write those). nil optionals become deletes.
    private func publicPayload(of car: Car, ownerUID: String) -> [String: Any]? {
        let publicCar = PublicCar(from: car, ownerUID: ownerUID, ownerUsername: "", ownerAvatarURL: nil)
        guard var data = try? Firestore.Encoder().encode(publicCar) else { return nil }
        data.removeValue(forKey: "ownerUsername")
        data.removeValue(forKey: "ownerAvatarURL")
        for key in Self.clearablePublicKeys where data[key] == nil {
            data[key] = FieldValue.delete()
        }
        return data
    }

    /// Optional public fields that must be deleted, not just omitted, when nil.
    /// (valueRange is not here: it's server-owned and never written by the client.)
    private static let clearablePublicKeys = ["engineSoundURL", "photoStorageURL"]

    private func publicProjectionChanged(from old: Car, to new: Car) -> Bool {
        let encoder = Firestore.Encoder()
        guard let a = try? encoder.encode(PublicCar(from: old, ownerUID: "", ownerUsername: "", ownerAvatarURL: nil)),
              let b = try? encoder.encode(PublicCar(from: new, ownerUID: "", ownerUsername: "", ownerAvatarURL: nil))
        else { return true }
        return !NSDictionary(dictionary: a).isEqual(to: b)
    }

    /// Merges every public field of `car` onto its public copy. An empty cover
    /// URL (not uploaded yet) is fine: applyStorageURLs pushes again on upload.
    /// Deliberately doesn't bump `updatedAt`, which orders the Explore feed:
    /// logging a service shouldn't move a car to the top.
    private func pushPublicFields(of car: Car) {
        guard let userId = currentUserId,
              let data = publicPayload(of: car, ownerUID: userId) else { return }
        db.collection("publicCars").document(car.id.uuidString).setData(data, merge: true) { error in
            if let error { print("[CarStore] Couldn't update the public copy: \(error.localizedDescription)") }
        }
    }

    func deleteCar(at offsets: IndexSet) {
        for index in offsets { deleteCar(cars[index]) }
    }

    func deleteCar(_ car: Car) {
        let receiptFileNames = car.maintenanceRecords.compactMap(\.receiptFileName)

        for fileName in car.photoFileNames {
            ImageManager.deleteImage(fileName: fileName)
        }
        for fileName in receiptFileNames {
            ImageManager.deleteImage(fileName: fileName)
        }
        if let soundFile = car.engineSoundFileName {
            ImageManager.deleteImage(fileName: soundFile)
        }
        guard let userId = currentUserId else {
            cars.removeAll { $0.id == car.id }
            saveLocal()
            return
        }
        soundStorageRef(userId: userId, carId: car.id.uuidString).delete(completion: nil)
        if let soundFile = car.engineSoundFileName {
            removePendingUpload(carId: car.id.uuidString, fileName: soundFile, kind: .sound)
        }
        deleteAllPhotosFromStorage(carId: car.id.uuidString, userId: userId, fileNames: car.photoFileNames)
        // Receipts live under a `receipts/` subpath, not `photoFileNames`, so
        // deleteAllPhotosFromStorage above won't reach them — otherwise
        // they'd be orphaned in Storage after the car (and its Firestore
        // doc, which lists them) is gone.
        for fileName in receiptFileNames {
            receiptStorageRef(userId: userId, carId: car.id.uuidString, fileName: fileName).delete(completion: nil)
        }
        for fileName in car.photoFileNames {
            removePendingUpload(carId: car.id.uuidString, fileName: fileName, kind: .photo)
        }
        for fileName in receiptFileNames {
            removePendingUpload(carId: car.id.uuidString, fileName: fileName, kind: .receipt)
        }
        // Same batch as the car doc delete (rather than two independent
        // fire-and-forget calls) so both succeed or fail together and there's
        // a single completion to log against, instead of the public copy
        // silently lingering if only its delete failed.
        // The car's likes/ and comments/ (under publicCars/{carId}, kept even
        // while the car is private) are other users' docs, which this client
        // may not delete (the likes rule binds the liker). Server-side sweeps
        // remove them once the car doc is gone: onPublicCarDeleted for a public
        // car, onCarWritten's delete branch for a private one.
        let batch = db.batch()
        if car.isPublic {
            batch.deleteDocument(db.collection("publicCars").document(car.id.uuidString))
        }
        batch.deleteDocument(
            db.collection("users").document(userId)
                .collection("cars").document(car.id.uuidString)
        )
        batch.commit { error in
            if let error {
                print("[Firestore] Failed to delete car\(car.isPublic ? " (and its public copy)" : ""): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Maintenance records

    static let maxMaintenanceRecords = 500

    func addMaintenanceRecord(_ record: MaintenanceRecord, to car: Car) {
        // Hard cap to prevent unbounded growth past Firestore's 1MB doc limit.
        guard car.maintenanceRecords.count < Self.maxMaintenanceRecords else { return }
        var updated = car
        updated.maintenanceRecords.append(record)
        updateCar(updated)
    }

    func deleteMaintenanceRecord(_ record: MaintenanceRecord, from car: Car) {
        var updated = car
        updated.maintenanceRecords.removeAll { $0.id == record.id }
        updateCar(updated)
        if let fileName = record.receiptFileName {
            deleteReceiptFiles(fileName: fileName, carId: car.id.uuidString)
        }
    }

    func updateMaintenanceRecord(
        _ record: MaintenanceRecord,
        in car: Car,
        newReceiptImage: UIImage? = nil,
        removeReceipt: Bool = false
    ) {
        var updated = car
        guard let idx = updated.maintenanceRecords.firstIndex(where: { $0.id == record.id }) else { return }

        var newRecord = record
        let fileName = receiptFileName(for: record.id)

        if removeReceipt {
            deleteReceiptFiles(fileName: fileName, carId: car.id.uuidString)
            newRecord.receiptFileName = nil
            newRecord.receiptStorageURL = nil
        } else if let newReceiptImage {
            // Local save is synchronous so the record always references a
            // usable file even if the app is killed before the upload below
            // finishes (FR-03.4 pattern) — mirrors car-photo handling.
            saveReceiptLocally(newReceiptImage, fileName: fileName)
            newRecord.receiptFileName = fileName
            // Cleared until the fresh upload lands — the previous
            // receiptStorageURL (if any) points at the object this upload is
            // about to overwrite, so it must not keep being shown as current.
            newRecord.receiptStorageURL = nil
        }

        updated.maintenanceRecords[idx] = newRecord
        updateCar(updated)

        if !removeReceipt, let newReceiptImage {
            uploadReceipt(newReceiptImage, fileName: fileName, recordId: record.id, carId: car.id.uuidString)
        }
    }

    // MARK: - Mods

    enum ModError: LocalizedError, Equatable {
        case nameRequired
        case notAllowed
        case limitReached
        case notFound

        var errorDescription: String? {
            switch self {
            case .nameRequired: return "Give this mod a name."
            case .notAllowed: return "That name or brand contains language that isn't allowed."
            case .limitReached: return "You can add up to \(Car.maxMods) mods per car."
            case .notFound: return "That mod could not be found."
            }
        }
    }

    /// Appends `mod` to `car.mods`. `mod` is clamped first (`CarMod.clamped()`:
    /// name/brand/notes trimmed and length-capped, empty brand/notes -> nil),
    /// so callers never need to pre-trim. Throws `.nameRequired` if the
    /// trimmed name is empty, `.notAllowed` if the (already-clamped) name or
    /// brand fails the word filter — App Store guideline 1.2, since both are
    /// public free text once the car and mod list are public (same
    /// client-side gate as CommentStore.post; the server backstop is
    /// `onPublicCarModsWritten`) — and `.limitReached` at `Car.maxMods` (30).
    /// `notes` is never filtered: it's private-only, same as
    /// MaintenanceRecord.notes.
    func addMod(_ mod: CarMod, to car: Car) throws {
        guard car.mods.count < Car.maxMods else { throw ModError.limitReached }
        let clamped = mod.clamped()
        guard !clamped.name.isEmpty else { throw ModError.nameRequired }
        guard CommentFilter.isAllowed(clamped.name), clamped.brand.map(CommentFilter.isAllowed) ?? true else {
            throw ModError.notAllowed
        }
        var updated = car
        updated.mods.append(clamped)
        updateCar(updated)
    }

    /// Replaces the mod matching `mod.id` in `car.mods` with a clamped copy of
    /// `mod`. Same validation as `addMod`; throws `.notFound` if `car` no
    /// longer has a mod with that id (e.g. deleted from another device).
    func updateMod(_ mod: CarMod, in car: Car) throws {
        guard car.mods.contains(where: { $0.id == mod.id }) else { throw ModError.notFound }
        let clamped = mod.clamped()
        guard !clamped.name.isEmpty else { throw ModError.nameRequired }
        guard CommentFilter.isAllowed(clamped.name), clamped.brand.map(CommentFilter.isAllowed) ?? true else {
            throw ModError.notAllowed
        }
        var updated = car
        guard let idx = updated.mods.firstIndex(where: { $0.id == mod.id }) else { return }
        updated.mods[idx] = clamped
        updateCar(updated)
    }

    /// Removes the mod matching `mod.id`. A no-op (not an error) if it's
    /// already gone, matching `deleteMaintenanceRecord`.
    func deleteMod(_ mod: CarMod, from car: Car) {
        var updated = car
        updated.mods.removeAll { $0.id == mod.id }
        updateCar(updated)
    }

    /// Reorders `car.mods` to `mods`. Cheap: no clamping or word-filter re-run
    /// (nothing about the reordered content changed), just a permutation
    /// check — `mods` must carry exactly the same set of ids as `car.mods` or
    /// this silently no-ops rather than risk dropping or duplicating a mod.
    func reorderMods(_ mods: [CarMod], in car: Car) {
        guard mods.count == car.mods.count, Set(mods.map(\.id)) == Set(car.mods.map(\.id)) else { return }
        var updated = car
        updated.mods = mods
        updateCar(updated)
    }

    // MARK: - Maintenance <-> reminders integration

    struct ServiceLogOutcome: Equatable {
        /// Reminders auto-completed because their serviceType case-insensitively
        /// matched the logged record.
        let completedReminderIDs: [UUID]
        /// The next occurrence auto-scheduled as a result of this log, if any.
        let scheduledNext: ServiceReminder?
        /// The car's mileage string *before* this log bumped it. nil means the
        /// log did not bump mileage (record had no parseable/higher mileage).
        let previousMileage: String?
    }

    /// Records a completed service. Appends the record; bumps the car's
    /// mileage when the record's is higher; completes every open reminder of
    /// the same serviceType (case-insensitive); and, if any reminder was
    /// completed and the type has a known interval, schedules the next
    /// occurrence (unless one is already open). All of the above lands in a
    /// single `updateCar` write. The receipt (if any) is saved locally
    /// synchronously and then uploaded to Storage separately — the upload
    /// never blocks this call or its return value.
    @discardableResult
    func logService(_ record: MaintenanceRecord, for car: Car, receiptImage: UIImage? = nil) -> ServiceLogOutcome {
        guard car.maintenanceRecords.count < Self.maxMaintenanceRecords else {
            return ServiceLogOutcome(completedReminderIDs: [], scheduledNext: nil, previousMileage: nil)
        }

        var updated = car
        var newRecord = record

        if let receiptImage {
            let fileName = receiptFileName(for: record.id)
            saveReceiptLocally(receiptImage, fileName: fileName)
            newRecord.receiptFileName = fileName
        }

        updated.maintenanceRecords.append(newRecord)

        var previousMileage: String?
        if let loggedMileage = newRecord.mileageValue,
           car.mileageValue.map({ loggedMileage > $0 }) ?? true {
            previousMileage = car.mileage
            updated.mileage = Self.formattedMileage(loggedMileage)
            updated.mileageUpdatedAt = newRecord.date
        }

        var completedIDs: [UUID] = []
        for i in updated.serviceReminders.indices {
            let reminder = updated.serviceReminders[i]
            guard !reminder.isCompleted,
                  reminder.serviceType.caseInsensitiveCompare(newRecord.serviceType) == .orderedSame
            else { continue }
            updated.serviceReminders[i].isCompleted = true
            updated.serviceReminders[i].completedDate = newRecord.date
            completedIDs.append(reminder.id)
        }

        var scheduledNext: ServiceReminder?
        if !completedIDs.isEmpty, let interval = ServiceReminderEngine.interval(for: newRecord.serviceType) {
            let stillOpen = updated.serviceReminders.contains {
                !$0.isCompleted && $0.serviceType.caseInsensitiveCompare(newRecord.serviceType) == .orderedSame
            }
            if !stillOpen, let next = Self.nextOccurrence(
                serviceType: newRecord.serviceType,
                interval: interval,
                anchorDate: newRecord.date,
                anchorMileage: newRecord.mileageValue ?? updated.mileageValue
            ) {
                updated.serviceReminders.append(next)
                scheduledNext = next
            }
        }

        updateCar(updated)
        // FR-11.4 maintenance_record_added — new records only (edits don't
        // re-fire). Callers that still append+updateCar directly (pre-
        // migration call sites) fire this themselves; once they switch to
        // logService, remove their own call to avoid double-counting.
        AnalyticsService.maintenanceRecordAdded()

        if let receiptImage {
            uploadReceipt(receiptImage, fileName: receiptFileName(for: record.id), recordId: record.id, carId: car.id.uuidString)
        }

        return ServiceLogOutcome(completedReminderIDs: completedIDs, scheduledNext: scheduledNext, previousMileage: previousMileage)
    }

    /// Reverses the reminder side effects of a prior `logService` call: restores
    /// any reminders it auto-completed and removes the reminder it auto-scheduled.
    /// Does NOT delete the maintenance record itself or revert the mileage bump —
    /// callers that want a full undo must also call `deleteMaintenanceRecord`.
    func undoLogSideEffects(_ outcome: ServiceLogOutcome, for car: Car) {
        var updated = car
        if let scheduledNext = outcome.scheduledNext {
            updated.serviceReminders.removeAll { $0.id == scheduledNext.id }
        }
        for id in outcome.completedReminderIDs {
            if let idx = updated.serviceReminders.firstIndex(where: { $0.id == id }) {
                updated.serviceReminders[idx].isCompleted = false
                updated.serviceReminders[idx].completedDate = nil
            }
        }
        updateCar(updated)
    }

    /// "Skip, just mark done" path — completes a reminder without recording a
    /// service. (Logging a service goes through `logService`, which completes
    /// matching reminders by serviceType.) Schedules + returns the next
    /// occurrence, anchored to today/current mileage, if the type has a known
    /// interval and no other open reminder of that type exists.
    @discardableResult
    func completeReminder(_ reminder: ServiceReminder, in car: Car) -> ServiceReminder? {
        var updated = car
        guard let idx = updated.serviceReminders.firstIndex(where: { $0.id == reminder.id }) else { return nil }

        let now = Date()
        updated.serviceReminders[idx].isCompleted = true
        updated.serviceReminders[idx].completedDate = now

        var next: ServiceReminder?
        if let interval = ServiceReminderEngine.interval(for: reminder.serviceType) {
            let stillOpen = updated.serviceReminders.contains {
                !$0.isCompleted && $0.serviceType.caseInsensitiveCompare(reminder.serviceType) == .orderedSame
            }
            if !stillOpen, let created = Self.nextOccurrence(
                serviceType: reminder.serviceType,
                interval: interval,
                anchorDate: now,
                anchorMileage: updated.mileageValue
            ) {
                updated.serviceReminders.append(created)
                next = created
            }
        }

        updateCar(updated)
        return next
    }

    func updateReminder(_ reminder: ServiceReminder, in car: Car) {
        var updated = car
        guard let idx = updated.serviceReminders.firstIndex(where: { $0.id == reminder.id }) else { return }
        updated.serviceReminders[idx] = reminder
        updateCar(updated)
    }

    /// Sets `car.mileage` (formatted like "25,000") and `mileageUpdatedAt = now`.
    func updateMileage(_ mileage: Int, for car: Car) {
        var updated = car
        updated.mileage = Self.formattedMileage(mileage)
        updated.mileageUpdatedAt = Date()
        updateCar(updated)
    }

    // Shared next-occurrence math for logService/completeReminder — mirrors
    // AddReminderView.configureDefaults: months added to the anchor date,
    // miles added to the anchor mileage and rounded via
    // ServiceReminderEngine.roundedMileage. Returns nil if neither trigger can
    // be computed (mileage-only interval with no mileage anchor available).
    private static func nextOccurrence(
        serviceType: String,
        interval: (months: Int?, miles: Int?),
        anchorDate: Date,
        anchorMileage: Int?
    ) -> ServiceReminder? {
        let dueDate = interval.months.flatMap {
            Calendar.current.date(byAdding: .month, value: $0, to: anchorDate)
        }
        let dueMileage: Int? = {
            guard let miles = interval.miles, let anchorMileage else { return nil }
            return ServiceReminderEngine.roundedMileage(anchorMileage + miles)
        }()
        guard dueDate != nil || dueMileage != nil else { return nil }
        return ServiceReminder(serviceType: serviceType, dueDate: dueDate, dueMileage: dueMileage)
    }

    private static func formattedMileage(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    // MARK: - Receipt upload

    private static let receiptMaxDimension: CGFloat = 2000
    private static let receiptJPEGQuality: CGFloat = 0.7

    // Resize logic is shared with ImageManager (car photos); only the JPEG
    // quality differs for receipts (0.7 vs. ImageManager's 0.8).
    private static func downscaledForReceipt(_ image: UIImage) -> UIImage {
        ImageManager.downscaled(image, maxDimension: receiptMaxDimension)
    }

    // Synchronous on-device save so the receipt survives even if the app is
    // killed before the Storage upload below completes, and so the retry
    // queue (ImageManager.loadImage) has something to read back. Downscaled
    // to match the uploaded copy; local re-encode quality is ImageManager's
    // own default (0.8) since it only accepts a UIImage, not raw Data.
    private func saveReceiptLocally(_ image: UIImage, fileName: String) {
        ImageManager.saveImage(Self.downscaledForReceipt(image), fileName: fileName)
    }

    private func uploadReceipt(_ image: UIImage, fileName: String, recordId: UUID, carId: String) {
        guard let userId = currentUserId else { return }
        guard let data = Self.downscaledForReceipt(image).jpegData(compressionQuality: Self.receiptJPEGQuality) else { return }
        let ref = receiptStorageRef(userId: userId, carId: carId, fileName: fileName)
        Task {
            do {
                _ = try await ref.putDataAsync(data, metadata: .jpegImage)
                let url = try await ref.downloadURL()
                applyReceiptStorageURL(carId: carId, recordId: recordId, urlString: url.absoluteString)
                removePendingUpload(carId: carId, fileName: fileName, kind: .receipt)
            } catch {
                addPendingUpload(carId: carId, fileName: fileName, kind: .receipt)
            }
        }
    }

    private func applyReceiptStorageURL(carId: String, recordId: UUID, urlString: String) {
        guard let userId = currentUserId,
              let carIdx = cars.firstIndex(where: { $0.id.uuidString == carId }),
              let recordIdx = cars[carIdx].maintenanceRecords.firstIndex(where: { $0.id == recordId })
        else { return }
        cars[carIdx].maintenanceRecords[recordIdx].receiptStorageURL = urlString
        saveLocal()
        try? carRef(userId: userId, carId: carId).setData(from: cars[carIdx])
    }

    private func deleteReceiptFiles(fileName: String, carId: String) {
        ImageManager.deleteImage(fileName: fileName)
        removePendingUpload(carId: carId, fileName: fileName, kind: .receipt)
        guard let userId = currentUserId else { return }
        receiptStorageRef(userId: userId, carId: carId, fileName: fileName).delete(completion: nil)
    }

    // MARK: - Estimated value

    /// Asks the `estimateCarValue` Cloud Function for an AI estimate of this
    /// car as it's saved (the server reads year/make/model/trim/mileage from
    /// the car doc; only `condition` and `region` come from here). The
    /// server records the result as the car's AI valuation (`aiValuations`
    /// updates), which is what drives the PUBLIC range. It does NOT change
    /// the car's own value: call `updateValue` with whatever the owner accepts
    /// (source `.ai`) or edits (source `.owner`). That value stays private.
    /// `region` is an optional zip or area ("94107", "Bay Area, CA").
    /// Throws `CarValueService.ValueError`.
    func estimateValue(for car: Car, condition: ValueCondition, region: String? = nil) async throws -> ValueEstimate {
        try await CarValueService().estimate(for: car, condition: condition, region: region)
    }

    /// Saves the car's value (private to the owner; any source) and the
    /// "Show on public profile" toggle. What Explore shows is decided
    /// server-side from the AI valuation only; see `publicValueRangePreview`.
    /// Pass `value: nil` to clear the value (the source is cleared with it).
    func updateValue(_ value: Double?, source: CarValueSource, showPublicly: Bool, for car: Car) {
        var updated = car
        if let value, value.isFinite, value > 0 {
            updated.estimatedValue = value
            updated.valueSource = source
            updated.valueUpdatedAt = Date()
        } else {
            updated.estimatedValue = nil
            updated.valueSource = nil
            updated.valueUpdatedAt = nil
        }
        updated.showValuePublicly = showPublicly
        updateCar(updated)
    }

    /// The car's AI valuation, if it has one.
    func aiValuation(for car: Car) -> CarValuation? {
        aiValuations[car.id.uuidString]
    }

    /// The range Explore will show for this car when it's public and "Show on
    /// public profile" is on: the AI valuation's rounded range, or nil when
    /// there's no valuation or it no longer applies (year/make/model/trim
    /// edited, 20k+ miles driven since, over a year old). Mirrors the server's
    /// rule, so the UI can say "Estimate to show a public range" / "Re-estimate:
    /// details changed". The authoritative value is `PublicCar.valueRange`.
    func publicValueRangePreview(for car: Car) -> String? {
        guard let v = aiValuation(for: car), v.applies(to: car) else { return nil }
        return v.publicLabel
    }

    /// Whether a public range can be shown for this car right now (an
    /// applicable AI valuation exists), regardless of the toggle.
    func canShowValuePublicly(_ car: Car) -> Bool {
        publicValueRangePreview(for: car) != nil
    }

    /// Flips only the public toggle.
    func setValueVisibility(_ showPublicly: Bool, for car: Car) {
        var updated = car
        updated.showValuePublicly = showPublicly
        updateCar(updated)
    }

    // MARK: - Engine sound

    /// Max clip length the store accepts. The recorder should stop at 5 s; the
    /// extra 0.2 s absorbs encoder rounding.
    static let maxEngineSoundDuration: Double = 5.2
    /// Must stay under storage.rules' `500 * 1024` byte cap for sound.m4a.
    static let maxEngineSoundBytes = 500 * 1024

    enum EngineSoundError: LocalizedError, Equatable {
        case tooLong
        case tooLarge
        case unreadable

        var errorDescription: String? {
            switch self {
            case .tooLong: return "Engine sound clips can be at most 5 seconds."
            case .tooLarge: return "That clip is too large. Keep it under 5 seconds."
            case .unreadable: return "Couldn't read that audio file."
            }
        }
    }

    private func engineSoundFileName(for carId: UUID) -> String {
        "sound_\(carId.uuidString).m4a"
    }

    /// Sets (or replaces) the car's engine sound. `fileURL` is an AAC .m4a
    /// the frontend recorded or imported; `duration` is its length in
    /// seconds. Validates, copies it into the app's own storage (so the
    /// caller's temp file can go away), saves the car, then uploads in the
    /// background. The upload goes through the pending-upload retry queue if it
    /// fails. `engineSoundURL` stays nil until the upload lands, then the public
    /// copy (if the car is public) picks it up.
    func setEngineSound(fileURL: URL, duration: Double, for car: Car) throws {
        guard duration.isFinite, duration > 0, duration <= Self.maxEngineSoundDuration else {
            throw EngineSoundError.tooLong
        }
        guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else {
            throw EngineSoundError.unreadable
        }
        guard data.count < Self.maxEngineSoundBytes else { throw EngineSoundError.tooLarge }

        let fileName = engineSoundFileName(for: car.id)
        let localURL = ImageManager.fileURL(for: fileName)
        do {
            try data.write(to: localURL, options: .atomic)
        } catch {
            throw EngineSoundError.unreadable
        }

        var updated = car
        updated.engineSoundFileName = fileName
        updated.engineSoundDuration = duration
        // The old URL points at the object this upload is about to overwrite.
        updated.engineSoundURL = nil
        updateCar(updated)

        uploadEngineSound(data, fileName: fileName, carId: car.id.uuidString)
    }

    /// Removes the car's engine sound locally, from Storage, and from the
    /// public copy.
    func removeEngineSound(for car: Car) {
        let carId = car.id.uuidString
        if let fileName = car.engineSoundFileName {
            ImageManager.deleteImage(fileName: fileName)
            removePendingUpload(carId: carId, fileName: fileName, kind: .sound)
        }
        if let userId = currentUserId {
            soundStorageRef(userId: userId, carId: carId).delete(completion: nil)
        }
        var updated = car
        updated.engineSoundFileName = nil
        updated.engineSoundURL = nil
        updated.engineSoundDuration = nil
        updateCar(updated)
    }

    /// Local file for the car's engine sound, for playback before (or
    /// without) the upload. nil if there's no clip on this device.
    func localEngineSoundURL(for car: Car) -> URL? {
        guard let fileName = car.engineSoundFileName else { return nil }
        let url = ImageManager.fileURL(for: fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private static let soundMetadata: StorageMetadata = {
        let meta = StorageMetadata()
        meta.contentType = "audio/mp4"  // storage.rules requires audio/*
        return meta
    }()

    private func uploadEngineSound(_ data: Data, fileName: String, carId: String) {
        guard let userId = currentUserId else { return }
        let ref = soundStorageRef(userId: userId, carId: carId)
        Task {
            do {
                _ = try await ref.putDataAsync(data, metadata: Self.soundMetadata)
                let url = try await ref.downloadURL()
                applyEngineSoundURL(url.absoluteString, fileName: fileName, carId: carId)
                removePendingUpload(carId: carId, fileName: fileName, kind: .sound)
            } catch {
                addPendingUpload(carId: carId, fileName: fileName, kind: .sound)
            }
        }
    }

    private func retryEngineSoundUpload(_ pending: PendingUpload, userId: String) async {
        let localURL = ImageManager.fileURL(for: pending.fileName)
        guard let data = try? Data(contentsOf: localURL),
              cars.contains(where: { $0.id.uuidString == pending.carId && $0.engineSoundFileName == pending.fileName })
        else {
            removePendingUpload(carId: pending.carId, fileName: pending.fileName, kind: .sound)
            return
        }
        let ref = soundStorageRef(userId: userId, carId: pending.carId)
        do {
            _ = try await ref.putDataAsync(data, metadata: Self.soundMetadata)
            let url = try await ref.downloadURL()
            applyEngineSoundURL(url.absoluteString, fileName: pending.fileName, carId: pending.carId)
            removePendingUpload(carId: pending.carId, fileName: pending.fileName, kind: .sound)
        } catch {
            // Still offline or transient error. Leave it queued.
        }
    }

    private func applyEngineSoundURL(_ urlString: String, fileName: String, carId: String) {
        guard let userId = currentUserId,
              let i = cars.firstIndex(where: { $0.id.uuidString == carId }),
              // Removed (or replaced by a different file) while uploading.
              cars[i].engineSoundFileName == fileName
        else { return }
        cars[i].engineSoundURL = urlString
        saveLocal()
        carRef(userId: userId, carId: carId).updateData(["engineSoundURL": urlString])
        if cars[i].isPublic {
            pushPublicFields(of: cars[i])
        }
    }

    // MARK: - Visibility

    /// Flips `car.isPublic`. `sharing`/`showValuePublicly`, when provided,
    /// are applied in the SAME private-car write as `isPublic` (so the very
    /// first publish already respects them, instead of publishing with
    /// whatever defaults the car happened to carry and re-syncing a moment
    /// later). `sharing.hasReviewed` is forced true, since passing it here
    /// only happens from the owner's "Make Public"/"Save" confirmation.
    /// Only meaningful while going public; ignored when going private.
    func setVisibility(
        _ isPublic: Bool,
        for car: Car,
        ownerUsername: String,
        ownerAvatarURL: String? = nil,
        sharing: PublicSharingSettings? = nil,
        showValuePublicly: Bool? = nil
    ) {
        var updated = car
        updated.isPublic = isPublic
        if isPublic {
            if var sharing {
                sharing.hasReviewed = true
                updated.publicSharing = sharing
            }
            if let showValuePublicly {
                updated.showValuePublicly = showValuePublicly
            }
        }
        updateCar(updated)
        if isPublic {
            syncPublicCar(updated, ownerUID: currentUserId ?? "", ownerUsername: ownerUsername, ownerAvatarURL: ownerAvatarURL)
        } else {
            // Deleting the public doc HIDES the car's likes and comments; it
            // doesn't delete them (owner decision). The rules make them
            // unreadable while the doc is absent, and onPublicCarCreated
            // restores the counts if the car is made public again.
            // If this delete fails, the public copy lingers and contradicts the local state.
            // Log so it surfaces in dev; production should retry via a queue similar to pendingUploads.
            db.collection("publicCars").document(car.id.uuidString).delete { error in
                if let error {
                    print("[Firestore] Failed to remove public car: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Saves new sharing-group toggles (and the value-range toggle) for
    /// `car`, marking them reviewed. If the car is public, `updateCar`'s own
    /// diffing (`publicProjectionChanged`) detects the settings change and
    /// re-syncs `publicCars` immediately — so a group switched OFF is
    /// actually removed from the live doc, not just withheld from future
    /// writes. For the FIRST publish, use `setVisibility`'s `sharing`
    /// parameter instead, so the initial write already reflects it.
    func updatePublicSharing(_ sharing: PublicSharingSettings, showValuePublicly: Bool, for car: Car) {
        var updated = car
        updated.publicSharing = sharing
        updated.publicSharing.hasReviewed = true
        updated.showValuePublicly = showValuePublicly
        updateCar(updated)
    }

    // MARK: - publicCars ID registry (publicCarOwners/{carId})
    //
    // firestore.rules only lets you create or edit publicCars/{carId} while
    // you hold the claim publicCarOwners/{carId} = { uid, createdAt }. Claims
    // are first-come and create-only, and they survive the car going private,
    // so nobody else can ever publish under a car ID once it's been public.
    // The first publish creates the claim and the public doc in ONE batch;
    // later publishes find the claim already ours and just merge the doc.

    /// Car IDs this session has confirmed (or just made) our claim on.
    private var claimedPublicCarIDs: Set<String> = []

    private enum ClaimState { case mine, unknown }

    /// `.mine` only when this user's claim is confirmed. The rules allow
    /// reading ONLY your own claim (no existence oracle), so a missing claim,
    /// someone else's claim and being offline all read as `.unknown`, and
    /// the publish goes through the claim batch.
    private func claimState(carId: String, uid: String) async -> ClaimState {
        if claimedPublicCarIDs.contains(carId) { return .mine }
        guard let snap = try? await db.collection("publicCarOwners").document(carId).getDocument(),
              snap.exists, (snap.data()?["uid"] as? String) == uid
        else { return .unknown }
        claimedPublicCarIDs.insert(carId)
        return .mine
    }

    // Merge, not a full overwrite. See "Public copy" above.
    private func syncPublicCar(_ car: Car, ownerUID: String, ownerUsername: String, ownerAvatarURL: String? = nil) {
        guard var data = publicPayload(of: car, ownerUID: ownerUID) else {
            print("[Firestore] Failed to encode PublicCar")
            return
        }
        data["ownerUsername"] = ownerUsername
        if let ownerAvatarURL { data["ownerAvatarURL"] = ownerAvatarURL }
        data["updatedAt"] = FieldValue.serverTimestamp()
        let carId = car.id.uuidString
        let publicRef = db.collection("publicCars").document(carId)
        let claimRef = db.collection("publicCarOwners").document(carId)

        Task {
            let plainWrite = {
                publicRef.setData(data, merge: true) { error in
                    if let error { print("[Firestore] Failed to publish car: \(error.localizedDescription)") }
                }
            }
            switch await claimState(carId: carId, uid: ownerUID) {
            case .mine:
                plainWrite()
            case .unknown:
                let batch = db.batch()
                batch.setData(["uid": ownerUID, "createdAt": FieldValue.serverTimestamp()], forDocument: claimRef)
                batch.setData(data, forDocument: publicRef, merge: true)
                batch.commit { [weak self] error in
                    Task { @MainActor [weak self] in
                        if error == nil {
                            self?.claimedPublicCarIDs.insert(carId)
                        } else {
                            // The claim already existed: creating it again is an
                            // update, which is denied and fails the batch. If
                            // it's ours (another device, or it just couldn't be
                            // read), the plain write succeeds. If it's someone
                            // else's (a car-ID collision), the rules deny that too.
                            plainWrite()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Photo upload

    private func uploadMissingStoragePhotos() {
        let carsNeedingUpload = cars.filter { car in
            !car.photoFileNames.isEmpty &&
            !car.photoStorageURLs.contains(where: { !$0.isEmpty })
        }
        guard !carsNeedingUpload.isEmpty else { return }
        for car in carsNeedingUpload {
            let photos = car.photoFileNames.compactMap { fileName -> (fileName: String, image: UIImage)? in
                guard let image = ImageManager.loadImage(fileName: fileName) else { return nil }
                return (fileName: fileName, image: image)
            }
            guard !photos.isEmpty else { continue }
            uploadPhotos(photos, removingFileNames: [], for: car)
        }
    }

    func uploadPhotos(
        _ newPhotos: [(fileName: String, image: UIImage)],
        removingFileNames: Set<String>,
        for car: Car
    ) {
        guard let userId = currentUserId else { return }
        let carId = car.id.uuidString

        for fileName in removingFileNames {
            storageRef(userId: userId, carId: carId, fileName: fileName).delete(completion: nil)
            removePendingUpload(carId: carId, fileName: fileName)
        }

        guard !newPhotos.isEmpty else { return }

        Task {
            var urlMap: [String: String] = [:]
            await withTaskGroup(of: (String, String?).self) { group in
                for (fileName, image) in newPhotos {
                    // Downscale here too, not just on local save — callers may
                    // hand this the original full-resolution UIImage straight
                    // from the camera/picker rather than a reloaded (already
                    // downscaled) copy from disk.
                    guard let data = ImageManager.downscaled(image).jpegData(compressionQuality: 0.8) else { continue }
                    let ref = storageRef(userId: userId, carId: carId, fileName: fileName)
                    group.addTask {
                        do {
                            _ = try await ref.putDataAsync(data, metadata: .jpegImage)
                            let url = try await ref.downloadURL()
                            return (fileName, url.absoluteString)
                        } catch {
                            return (fileName, nil)
                        }
                    }
                }
                for await (fileName, urlString) in group {
                    if let urlString {
                        urlMap[fileName] = urlString
                    } else {
                        addPendingUpload(carId: carId, fileName: fileName)
                    }
                }
            }
            applyStorageURLs(urlMap, for: car)
        }
    }

    private func applyStorageURLs(_ urlMap: [String: String], for car: Car) {
        guard let userId = currentUserId,
              let current = cars.first(where: { $0.id == car.id }) else { return }
        let existingURLs = Dictionary(
            uniqueKeysWithValues: zip(car.photoFileNames, padURLs(car.photoStorageURLs, to: car.photoFileNames.count))
        )
        let updatedURLs = current.photoFileNames.map { urlMap[$0] ?? existingURLs[$0] ?? "" }
        carRef(userId: userId, carId: car.id.uuidString)
            .updateData(["photoStorageURLs": updatedURLs])
        if let i = cars.firstIndex(where: { $0.id == car.id }) {
            cars[i].photoStorageURLs = updatedURLs
            saveLocal()
            // If this car is public, push the new cover and gallery URLs to
            // publicCars so Explore reflects them without a visibility re-toggle.
            // A merge, so it also works before the public doc exists.
            if cars[i].isPublic {
                pushPublicFields(of: cars[i])
            }
        }
    }

    private func deleteAllPhotosFromStorage(carId: String, userId: String, fileNames: [String]) {
        for fileName in fileNames {
            storageRef(userId: userId, carId: carId, fileName: fileName).delete(completion: nil)
        }
    }

    // MARK: - Pending upload queue

    private func addPendingUpload(carId: String, fileName: String, kind: PendingUpload.Kind = .photo) {
        guard !pendingUploads.contains(where: { $0.carId == carId && $0.fileName == fileName && $0.kind == kind }) else { return }
        pendingUploads.append(PendingUpload(carId: carId, fileName: fileName, kind: kind))
        savePendingUploads()
    }

    private func removePendingUpload(carId: String, fileName: String, kind: PendingUpload.Kind = .photo) {
        let before = pendingUploads.count
        pendingUploads.removeAll { $0.carId == carId && $0.fileName == fileName && $0.kind == kind }
        if pendingUploads.count != before { savePendingUploads() }
    }

    private func savePendingUploads() {
        guard let uid = currentUserId,
              let data = try? JSONEncoder().encode(pendingUploads) else { return }
        UserDefaults.standard.set(data, forKey: pendingUploadsKey(uid))
    }

    private func loadPendingUploads(uid: String) {
        guard let data = UserDefaults.standard.data(forKey: pendingUploadsKey(uid)),
              let decoded = try? JSONDecoder().decode([PendingUpload].self, from: data) else {
            pendingUploads = []
            return
        }
        pendingUploads = decoded
    }

    private func retryPendingUploads() async {
        guard let userId = currentUserId, !pendingUploads.isEmpty else { return }
        let queue = pendingUploads
        for pending in queue {
            if pending.kind == .sound {
                await retryEngineSoundUpload(pending, userId: userId)
                continue
            }
            guard let image = ImageManager.loadImage(fileName: pending.fileName) else {
                removePendingUpload(carId: pending.carId, fileName: pending.fileName, kind: pending.kind)
                continue
            }
            switch pending.kind {
            case .photo:
                // `image` came back through ImageManager.loadImage, which
                // already downscales on read — this is a no-op in the
                // common case and a safety net otherwise.
                guard let data = ImageManager.downscaled(image).jpegData(compressionQuality: 0.8) else { continue }
                let ref = storageRef(userId: userId, carId: pending.carId, fileName: pending.fileName)
                do {
                    _ = try await ref.putDataAsync(data, metadata: .jpegImage)
                    let url = try await ref.downloadURL()
                    if let car = cars.first(where: { $0.id.uuidString == pending.carId }) {
                        applyStorageURLs([pending.fileName: url.absoluteString], for: car)
                    }
                    removePendingUpload(carId: pending.carId, fileName: pending.fileName, kind: .photo)
                } catch {
                    // Still offline or transient error — leave in queue for next retry
                }
            case .sound:
                continue  // handled above, before the image load
            case .receipt:
                guard let data = image.jpegData(compressionQuality: Self.receiptJPEGQuality) else { continue }
                // Receipt filenames are deterministic (`{recordId}.jpg`), so the
                // record this belongs to can be recovered from the name alone —
                // no need to carry recordId in the persisted queue.
                guard let recordId = UUID(uuidString: (pending.fileName as NSString).deletingPathExtension) else {
                    removePendingUpload(carId: pending.carId, fileName: pending.fileName, kind: .receipt)
                    continue
                }
                let ref = receiptStorageRef(userId: userId, carId: pending.carId, fileName: pending.fileName)
                do {
                    _ = try await ref.putDataAsync(data, metadata: .jpegImage)
                    let url = try await ref.downloadURL()
                    applyReceiptStorageURL(carId: pending.carId, recordId: recordId, urlString: url.absoluteString)
                    removePendingUpload(carId: pending.carId, fileName: pending.fileName, kind: .receipt)
                } catch {
                    // Still offline or transient error — leave in queue for next retry
                }
            }
        }
    }

    // MARK: - Local cache

    private func saveLocal() {
        guard let uid = currentUserId,
              let data = try? JSONEncoder().encode(cars) else { return }
        UserDefaults.standard.set(data, forKey: localKey(uid))
    }

    private func loadLocal(uid: String) {
        guard let data = UserDefaults.standard.data(forKey: localKey(uid)),
              let decoded = try? JSONDecoder().decode([Car].self, from: data) else {
            cars = []
            return
        }
        cars = decoded
    }

    // MARK: - Preview

    static var previewCars: [Car] { sampleCars }

    private static var sampleCars: [Car] {
        let calendar = Calendar.current
        let now = Date()

        return [
            Car(
                make: "Tesla",
                model: "Model 3",
                year: "2023",
                licensePlate: "8VNX231",
                vinNumber: "5YJ3E1EA5PF123456",
                color: "White",
                mileage: "18,420",
                fuelType: "Electric",
                transmission: "Automatic",
                insuranceProvider: "Progressive",
                insurancePolicyNumber: "PRG-9281034",
                insuranceExpiryDate: calendar.date(byAdding: .day, value: 45, to: now),
                registrationExpiryDate: calendar.date(byAdding: .month, value: 3, to: now),
                maintenanceRecords: [
                    MaintenanceRecord(serviceType: "Tire Rotation", date: calendar.date(byAdding: .day, value: -30, to: now)!, mileage: "18,000", cost: "35", shop: "Discount Tire"),
                    MaintenanceRecord(serviceType: "Inspection", date: calendar.date(byAdding: .month, value: -4, to: now)!, mileage: "14,200", cost: "0", shop: "Tesla Service Center"),
                    MaintenanceRecord(serviceType: "Wash / Detail", date: calendar.date(byAdding: .day, value: -12, to: now)!, mileage: "18,300", cost: "150", shop: "Elite Auto Spa")
                ]
            ),
            Car(
                make: "Toyota",
                model: "RAV4",
                year: "2021",
                licensePlate: "7ABC392",
                vinNumber: "2T3P1RFV8MW089012",
                color: "Silver",
                mileage: "42,850",
                fuelType: "Gasoline",
                transmission: "Automatic",
                insuranceProvider: "State Farm",
                insurancePolicyNumber: "SF-44829103",
                insuranceExpiryDate: calendar.date(byAdding: .day, value: 18, to: now),
                registrationExpiryDate: calendar.date(byAdding: .day, value: -10, to: now),
                maintenanceRecords: [
                    MaintenanceRecord(serviceType: "Oil Change", date: calendar.date(byAdding: .day, value: -15, to: now)!, mileage: "42,500", cost: "65", shop: "Valvoline Instant Oil Change"),
                    MaintenanceRecord(serviceType: "Brake Service", date: calendar.date(byAdding: .month, value: -2, to: now)!, mileage: "40,100", cost: "380", shop: "Pep Boys", notes: "Front brake pads and rotors replaced")
                ]
            ),
            Car(
                make: "BMW",
                model: "330i",
                year: "2022",
                licensePlate: "6MNP887",
                vinNumber: "WBA5R1C50NAH78901",
                color: "Black",
                mileage: "28,340",
                fuelType: "Gasoline",
                transmission: "Automatic",
                insuranceProvider: "GEICO",
                insurancePolicyNumber: "GK-7731920",
                insuranceExpiryDate: calendar.date(byAdding: .month, value: 8, to: now),
                registrationExpiryDate: calendar.date(byAdding: .month, value: 5, to: now),
                maintenanceRecords: [
                    MaintenanceRecord(serviceType: "Oil Change", date: calendar.date(byAdding: .day, value: -20, to: now)!, mileage: "28,000", cost: "95", shop: "BMW of Stevens Creek"),
                    MaintenanceRecord(serviceType: "Alignment", date: calendar.date(byAdding: .month, value: -3, to: now)!, mileage: "25,800", cost: "120", shop: "BMW of Stevens Creek")
                ]
            )
        ]
    }
}

private struct PendingUpload: Codable, Equatable {
    enum Kind: String, Codable {
        case photo
        case receipt
        case sound
    }

    let carId: String
    let fileName: String
    var kind: Kind

    init(carId: String, fileName: String, kind: Kind = .photo) {
        self.carId = carId
        self.fileName = fileName
        self.kind = kind
    }

    private enum CodingKeys: String, CodingKey { case carId, fileName, kind }

    // Existing persisted queues (UserDefaults) predate `kind` — default to
    // .photo, the only kind that existed before receipts.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        carId = try c.decode(String.self, forKey: .carId)
        fileName = try c.decode(String.self, forKey: .fileName)
        kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .photo
    }
}
