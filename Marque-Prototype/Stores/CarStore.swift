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

    private let db = Firestore.firestore()
    private let storage = Storage.storage()
    private var listener: ListenerRegistration?
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
        currentUserId = nil
        cars = []
        pendingUploads = []
    }

    // MARK: - Car CRUD

    func addCar(_ car: Car) {
        guard let userId = currentUserId else {
            cars.append(car)
            saveLocal()
            return
        }
        try? carRef(userId: userId, carId: car.id.uuidString).setData(from: car)
    }

    func updateCar(_ car: Car) {
        guard let userId = currentUserId else {
            if let i = cars.firstIndex(where: { $0.id == car.id }) {
                cars[i] = car
                saveLocal()
            }
            return
        }
        try? carRef(userId: userId, carId: car.id.uuidString).setData(from: car)
    }

    func deleteCar(at offsets: IndexSet) {
        for index in offsets { deleteCar(cars[index]) }
    }

    func deleteCar(_ car: Car) {
        for fileName in car.photoFileNames {
            ImageManager.deleteImage(fileName: fileName)
        }
        guard let userId = currentUserId else {
            cars.removeAll { $0.id == car.id }
            saveLocal()
            return
        }
        deleteAllPhotosFromStorage(carId: car.id.uuidString, userId: userId, fileNames: car.photoFileNames)
        for fileName in car.photoFileNames {
            removePendingUpload(carId: car.id.uuidString, fileName: fileName)
        }
        if car.isPublic {
            db.collection("publicCars").document(car.id.uuidString).delete()
        }
        db.collection("users").document(userId)
            .collection("cars").document(car.id.uuidString)
            .delete()
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
    }

    // MARK: - Visibility

    func setVisibility(_ isPublic: Bool, for car: Car, ownerUsername: String, ownerAvatarURL: String? = nil) {
        var updated = car
        updated.isPublic = isPublic
        updateCar(updated)
        if isPublic {
            syncPublicCar(updated, ownerUID: currentUserId ?? "", ownerUsername: ownerUsername, ownerAvatarURL: ownerAvatarURL)
        } else {
            // If this delete fails, the public copy lingers and contradicts the local state.
            // Log so it surfaces in dev; production should retry via a queue similar to pendingUploads.
            db.collection("publicCars").document(car.id.uuidString).delete { error in
                if let error {
                    print("[Firestore] Failed to remove public car: \(error.localizedDescription)")
                }
            }
        }
    }

    private func syncPublicCar(_ car: Car, ownerUID: String, ownerUsername: String, ownerAvatarURL: String? = nil) {
        let publicCar = PublicCar(from: car, ownerUID: ownerUID, ownerUsername: ownerUsername, ownerAvatarURL: ownerAvatarURL)
        let ref = db.collection("publicCars").document(car.id.uuidString)
        do {
            var data = try Firestore.Encoder().encode(publicCar)
            data["updatedAt"] = FieldValue.serverTimestamp()
            ref.setData(data)
        } catch {
            print("[Firestore] Failed to encode PublicCar: \(error.localizedDescription)")
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
                    guard let data = image.jpegData(compressionQuality: 0.8) else { continue }
                    let ref = storageRef(userId: userId, carId: carId, fileName: fileName)
                    group.addTask {
                        do {
                            _ = try await ref.putDataAsync(data)
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
            // If this car is public, push the new primary photo URL to publicCars
            // so Explore reflects it without requiring a re-toggle of visibility.
            if cars[i].isPublic, let primaryURL = cars[i].primaryPhotoStorageURL {
                // Use setData(merge:) rather than updateData so this succeeds even if
                // the publicCars doc doesn't exist yet (e.g. upload completed before
                // the user toggled visibility).
                db.collection("publicCars").document(car.id.uuidString)
                    .setData(["photoStorageURL": primaryURL.absoluteString], merge: true)
            }
        }
    }

    private func deleteAllPhotosFromStorage(carId: String, userId: String, fileNames: [String]) {
        for fileName in fileNames {
            storageRef(userId: userId, carId: carId, fileName: fileName).delete(completion: nil)
        }
    }

    // MARK: - Pending upload queue

    private func addPendingUpload(carId: String, fileName: String) {
        guard !pendingUploads.contains(where: { $0.carId == carId && $0.fileName == fileName }) else { return }
        pendingUploads.append(PendingUpload(carId: carId, fileName: fileName))
        savePendingUploads()
    }

    private func removePendingUpload(carId: String, fileName: String) {
        let before = pendingUploads.count
        pendingUploads.removeAll { $0.carId == carId && $0.fileName == fileName }
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
            guard let image = ImageManager.loadImage(fileName: pending.fileName) else {
                removePendingUpload(carId: pending.carId, fileName: pending.fileName)
                continue
            }
            guard let data = image.jpegData(compressionQuality: 0.8) else { continue }
            let ref = storageRef(userId: userId, carId: pending.carId, fileName: pending.fileName)
            do {
                _ = try await ref.putDataAsync(data)
                let url = try await ref.downloadURL()
                if let car = cars.first(where: { $0.id.uuidString == pending.carId }) {
                    applyStorageURLs([pending.fileName: url.absoluteString], for: car)
                }
                removePendingUpload(carId: pending.carId, fileName: pending.fileName)
            } catch {
                // Still offline or transient error — leave in queue for next retry
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
    let carId: String
    let fileName: String
}
