import Foundation

struct PublicServiceRecord: Identifiable, Codable, Equatable {
    let id: UUID
    let serviceType: String
    let date: Date

    init(id: UUID = UUID(), serviceType: String, date: Date) {
        self.id = id
        self.serviceType = serviceType
        self.date = date
    }

    private enum CodingKeys: String, CodingKey {
        case id, serviceType, date
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        serviceType = try c.decode(String.self, forKey: .serviceType)
        date = try c.decode(Date.self, forKey: .date)
    }
}

struct PublicCar: Identifiable, Codable {
    let carId: String
    let ownerUID: String
    let ownerUsername: String
    let ownerAvatarURL: String?
    let make: String
    let model: String
    let year: String
    let color: String
    let mileage: String
    let trim: String
    let bodyStyle: String
    let driveType: String
    let engine: String
    let fuelType: String
    let transmission: String
    let notes: String
    /// Cover photo only. Kept for older app versions; new code should use
    /// `galleryURLs`.
    let photoStorageURL: String?
    let photoOffsetY: Double
    let serviceHistory: [PublicServiceRecord]

    /// Every uploaded photo's Storage URL, cover first. Empty on docs written
    /// before the gallery existed (use `galleryURLs`, which falls back).
    let photoURLs: [String]
    /// Rounded public value range ("$30k–$35k"), present only when the owner
    /// opted in. Never an exact figure.
    let valueRange: String?
    /// Engine sound clip download URL, present only while the car is public
    /// and has a clip.
    let engineSoundURL: String?

    // Server-maintained counts (Cloud Functions). Read-only here: they are
    // NEVER encoded, and firestore.rules rejects any client write to them. 0
    // on docs that predate them.
    let likeCount: Int
    let weeklyLikeCount: Int
    let commentCount: Int

    /// Most photos a public gallery carries (firestore.rules validates each
    /// URL, and the rules engine's evaluation budget caps it at 12).
    static let maxGalleryPhotos = 12

    var id: String { carId }
    var displayName: String { [year, make, model].filter { !$0.isEmpty }.joined(separator: " ") }
    var primaryPhotoURL: URL? {
        guard let str = photoStorageURL, !str.isEmpty else { return nil }
        return URL(string: str)
    }

    /// All public photos, cover first, for the Explore gallery. Falls back to
    /// the cover alone for docs written before `photoURLs` existed.
    var galleryURLs: [URL] {
        let strings = photoURLs.isEmpty ? [photoStorageURL ?? ""] : photoURLs
        return strings.filter { !$0.isEmpty }.compactMap(URL.init(string:))
    }

    var engineSoundPlaybackURL: URL? {
        guard let str = engineSoundURL, !str.isEmpty else { return nil }
        return URL(string: str)
    }

    var specRows: [(label: String, value: String)] {
        [
            ("Make", make), ("Model", model), ("Year", year), ("Trim", trim),
            ("Color", color), ("Body Style", bodyStyle), ("Drive Type", driveType),
            ("Engine", engine), ("Fuel Type", fuelType), ("Transmission", transmission),
            ("Mileage", mileage),
        ].filter { !$0.value.isEmpty }
    }

    private enum CodingKeys: String, CodingKey {
        case carId, ownerUID, ownerUsername, ownerAvatarURL
        case make, model, year, color, mileage, trim, bodyStyle, driveType, engine
        case fuelType, transmission, notes
        case photoStorageURL, photoOffsetY, serviceHistory
        case photoURLs, valueRange, engineSoundURL
        case likeCount, weeklyLikeCount, commentCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        carId = try c.decode(String.self, forKey: .carId)
        ownerUID = try c.decode(String.self, forKey: .ownerUID)
        ownerUsername = try c.decodeIfPresent(String.self, forKey: .ownerUsername) ?? ""
        ownerAvatarURL = try c.decodeIfPresent(String.self, forKey: .ownerAvatarURL)
        make = try c.decodeIfPresent(String.self, forKey: .make) ?? ""
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? ""
        year = try c.decodeIfPresent(String.self, forKey: .year) ?? ""
        color = try c.decodeIfPresent(String.self, forKey: .color) ?? ""
        mileage = try c.decodeIfPresent(String.self, forKey: .mileage) ?? ""
        trim = try c.decodeIfPresent(String.self, forKey: .trim) ?? ""
        bodyStyle = try c.decodeIfPresent(String.self, forKey: .bodyStyle) ?? ""
        driveType = try c.decodeIfPresent(String.self, forKey: .driveType) ?? ""
        engine = try c.decodeIfPresent(String.self, forKey: .engine) ?? ""
        fuelType = try c.decodeIfPresent(String.self, forKey: .fuelType) ?? ""
        transmission = try c.decodeIfPresent(String.self, forKey: .transmission) ?? ""
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        photoStorageURL = try c.decodeIfPresent(String.self, forKey: .photoStorageURL)
        photoOffsetY = try c.decodeIfPresent(Double.self, forKey: .photoOffsetY) ?? 0
        serviceHistory = try c.decodeIfPresent([PublicServiceRecord].self, forKey: .serviceHistory) ?? []
        photoURLs = try c.decodeIfPresent([String].self, forKey: .photoURLs) ?? []
        valueRange = try c.decodeIfPresent(String.self, forKey: .valueRange)
        engineSoundURL = try c.decodeIfPresent(String.self, forKey: .engineSoundURL)
        likeCount = (try? c.decodeIfPresent(Int.self, forKey: .likeCount)) ?? 0
        weeklyLikeCount = (try? c.decodeIfPresent(Int.self, forKey: .weeklyLikeCount)) ?? 0
        commentCount = (try? c.decodeIfPresent(Int.self, forKey: .commentCount)) ?? 0
    }

    /// Encodes ONLY the owner-written fields (the `ownerWrittenFields()`
    /// allowlist in firestore.rules). The server counts are deliberately
    /// skipped: including them would make every owner write fail the rules.
    /// nil optionals are omitted; CarStore clears them explicitly with
    /// FieldValue.delete() when it merges.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(carId, forKey: .carId)
        try c.encode(ownerUID, forKey: .ownerUID)
        try c.encode(ownerUsername, forKey: .ownerUsername)
        try c.encodeIfPresent(ownerAvatarURL, forKey: .ownerAvatarURL)
        try c.encode(make, forKey: .make)
        try c.encode(model, forKey: .model)
        try c.encode(year, forKey: .year)
        try c.encode(color, forKey: .color)
        try c.encode(mileage, forKey: .mileage)
        try c.encode(trim, forKey: .trim)
        try c.encode(bodyStyle, forKey: .bodyStyle)
        try c.encode(driveType, forKey: .driveType)
        try c.encode(engine, forKey: .engine)
        try c.encode(fuelType, forKey: .fuelType)
        try c.encode(transmission, forKey: .transmission)
        try c.encode(notes, forKey: .notes)
        try c.encodeIfPresent(photoStorageURL, forKey: .photoStorageURL)
        try c.encode(photoOffsetY, forKey: .photoOffsetY)
        try c.encode(serviceHistory, forKey: .serviceHistory)
        try c.encode(photoURLs, forKey: .photoURLs)
        try c.encodeIfPresent(valueRange, forKey: .valueRange)
        try c.encodeIfPresent(engineSoundURL, forKey: .engineSoundURL)
    }
}

extension PublicCar {
    /// The public projection of `car` (FR-06.3: no VIN, plate, insurance,
    /// registration, costs, exact value or per-record notes). Server counts
    /// start at 0 here; they are never written from the client.
    init(from car: Car, ownerUID: String, ownerUsername: String, ownerAvatarURL: String?) {
        carId = car.id.uuidString
        self.ownerUID = ownerUID
        self.ownerUsername = ownerUsername
        self.ownerAvatarURL = ownerAvatarURL
        make = car.make
        model = car.model
        year = car.year
        color = car.color
        mileage = car.mileage
        trim = car.trim
        bodyStyle = car.bodyStyle
        driveType = car.driveType
        engine = car.engine
        fuelType = car.fuelType
        transmission = car.transmission
        notes = car.notes
        photoStorageURL = car.primaryPhotoStorageURL?.absoluteString ?? ""
        photoOffsetY = car.photoOffsetY
        // The record's own id (not a fresh UUID) so the projection is stable
        // across syncs and CarStore can tell whether anything public changed.
        serviceHistory = car.maintenanceRecords.map {
            PublicServiceRecord(id: $0.id, serviceType: $0.serviceType, date: $0.date)
        }
        // Capped: firestore.rules accepts at most 12 (its per-request
        // evaluation budget). A car with more photos publishes the first 12.
        photoURLs = Array(car.uploadedPhotoURLStrings.prefix(PublicCar.maxGalleryPhotos))
        valueRange = car.publicValueRange
        engineSoundURL = (car.engineSoundURL?.isEmpty == false) ? car.engineSoundURL : nil
        likeCount = 0
        weeklyLikeCount = 0
        commentCount = 0
    }
}
