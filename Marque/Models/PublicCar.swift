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

/// The public projection of `CarMod`: category, name and brand only — never
/// `notes` (private-only per the model) or `installedAt` (a date the owner
/// didn't ask to publish). Not `Identifiable` by a stored id (PublicCarMod
/// carries none, matching the "3 fields only" projection); `id` below is a
/// derived, non-persisted convenience for SwiftUI lists.
struct PublicCarMod: Codable, Equatable, Identifiable {
    let category: ModCategory
    let name: String
    let brand: String?

    var id: String { "\(category.rawValue)|\(name)|\(brand ?? "")" }

    private enum CodingKeys: String, CodingKey {
        case category, name, brand
    }

    init(category: ModCategory, name: String, brand: String?) {
        self.category = category
        self.name = name
        self.brand = brand
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        category = (try? c.decode(ModCategory.self, forKey: .category)) ?? .other
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        brand = try c.decodeIfPresent(String.self, forKey: .brand)
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
    /// Category/name/brand only, capped at `maxMods`. Empty on docs written
    /// before mods existed.
    let mods: [PublicCarMod]

    /// Every uploaded photo's Storage URL, cover first. Empty on docs written
    /// before the gallery existed (use `galleryURLs`, which falls back).
    let photoURLs: [String]
    /// Rounded public value range ("$30k–$35k"). SERVER-OWNED: derived from
    /// the owner's AI valuation only (never a typed value), present while "Show
    /// on public profile" is on and the valuation still matches the car. Never
    /// encoded by the client (firestore.rules rejects client writes to it).
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
    /// When the car was made public: `updatedAt` is only set by the publish
    /// sync (later edits deliberately don't bump it, see CarStore.updateCar),
    /// so it doubles as the publish time. nil on the client's own projection.
    /// Read-only here, never encoded.
    let publishedAt: Date?

    /// Most photos a public gallery carries (firestore.rules validates each
    /// URL, and the rules engine's evaluation budget caps it at 12).
    static let maxGalleryPhotos = 12

    /// Most mods a public car carries. Mirrors Car.maxMods and the
    /// `mods.size() <= 30` check in firestore.rules — change all three together.
    static let maxMods = 30

    var id: String { carId }

    /// A car with at least one mod — drives the Explore "Modified" filter.
    var isModified: Bool { !mods.isEmpty }
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

    private enum CodingKeys: String, CodingKey {
        case carId, ownerUID, ownerUsername, ownerAvatarURL
        case make, model, year, color, mileage, trim, bodyStyle, driveType, engine
        case fuelType, transmission, notes
        case photoStorageURL, photoOffsetY, serviceHistory
        case photoURLs, valueRange, engineSoundURL
        case mods
        case likeCount, weeklyLikeCount, commentCount
        case publishedAt = "updatedAt"
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
        mods = try c.decodeIfPresent([PublicCarMod].self, forKey: .mods) ?? []
        photoURLs = try c.decodeIfPresent([String].self, forKey: .photoURLs) ?? []
        valueRange = try c.decodeIfPresent(String.self, forKey: .valueRange)
        engineSoundURL = try c.decodeIfPresent(String.self, forKey: .engineSoundURL)
        likeCount = (try? c.decodeIfPresent(Int.self, forKey: .likeCount)) ?? 0
        weeklyLikeCount = (try? c.decodeIfPresent(Int.self, forKey: .weeklyLikeCount)) ?? 0
        commentCount = (try? c.decodeIfPresent(Int.self, forKey: .commentCount)) ?? 0
        publishedAt = try? c.decodeIfPresent(Date.self, forKey: .publishedAt)
    }

    /// Made public in the last 7 days, for Explore's "New" badge.
    var isNew: Bool {
        guard let publishedAt else { return false }
        return Date().timeIntervalSince(publishedAt) < 7 * 24 * 3600
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
        try c.encode(mods, forKey: .mods)
        try c.encode(photoURLs, forKey: .photoURLs)
        try c.encodeIfPresent(engineSoundURL, forKey: .engineSoundURL)
    }
}

extension PublicCar {
    /// The public projection of `car` (FR-06.3: no VIN, plate, insurance,
    /// registration, costs, exact value or per-record notes). Server counts
    /// start at 0 here; they are never written from the client.
    ///
    /// THE PRIVACY-CRITICAL PART: also honors `car.publicSharing`. A group
    /// that's off produces an EMPTY value for every field it owns ("" for
    /// strings, [] for arrays, nil for the optionals), never the real data.
    /// Year/make/model/owner identity are never gated — always shared (owner
    /// decision). This is the only place that must apply these toggles: every
    /// `publicCars` write goes through `PublicCar(from:)` (see CarStore's
    /// "Public copy" section), so gating here is sufficient everywhere.
    init(from car: Car, ownerUID: String, ownerUsername: String, ownerAvatarURL: String?) {
        let sharing = car.publicSharing
        carId = car.id.uuidString
        self.ownerUID = ownerUID
        self.ownerUsername = ownerUsername
        self.ownerAvatarURL = ownerAvatarURL
        make = car.make
        model = car.model
        year = car.year
        // "specs" group: trim/engine/bodyStyle/driveType/transmission/fuelType/color.
        color = sharing.specs ? car.color : ""
        trim = sharing.specs ? car.trim : ""
        bodyStyle = sharing.specs ? car.bodyStyle : ""
        driveType = sharing.specs ? car.driveType : ""
        engine = sharing.specs ? car.engine : ""
        fuelType = sharing.specs ? car.fuelType : ""
        transmission = sharing.specs ? car.transmission : ""
        mileage = sharing.mileage ? car.mileage : ""
        notes = sharing.notes ? car.notes : ""
        if sharing.photos {
            photoStorageURL = car.primaryPhotoStorageURL?.absoluteString ?? ""
            photoOffsetY = car.photoOffsetY
            // Capped: firestore.rules accepts at most 12 (its per-request
            // evaluation budget). A car with more photos publishes the first 12.
            photoURLs = Array(car.uploadedPhotoURLStrings.prefix(PublicCar.maxGalleryPhotos))
        } else {
            // nil (not ""), so CarStore.publicPayload's clearablePublicKeys
            // mechanism deletes the field from an existing doc entirely.
            photoStorageURL = nil
            photoOffsetY = 0
            photoURLs = []
        }
        // The record's own id (not a fresh UUID) so the projection is stable
        // across syncs and CarStore can tell whether anything public changed.
        serviceHistory = sharing.serviceHistory
            ? car.maintenanceRecords.map { PublicServiceRecord(id: $0.id, serviceType: $0.serviceType, date: $0.date) }
            : []
        // Category/name/brand only — never notes or installedAt. Capped at
        // maxMods, same reasoning as photoURLs above (car.mods is already
        // capped at Car.maxMods == PublicCar.maxMods by CarStore.addMod, but
        // this projection caps independently so it never depends on that).
        mods = sharing.mods
            ? car.mods.prefix(PublicCar.maxMods).map { PublicCarMod(category: $0.category, name: $0.name, brand: $0.brand) }
            : []
        valueRange = nil  // server-owned; see the property
        engineSoundURL = (sharing.engineSound && car.engineSoundURL?.isEmpty == false) ? car.engineSoundURL : nil
        likeCount = 0
        weeklyLikeCount = 0
        commentCount = 0
        publishedAt = nil
    }
}

// MARK: - Self-check

#if DEBUG
extension PublicCar {
    /// No XCTest target exists in this project (see CLAUDE.md); this is the
    /// documented substitute. Call manually from a debug entry point if
    /// needed -- nothing in the app invokes this automatically.
    static func _selfCheck() {
        var sample = Car()
        sample.make = "Toyota"
        sample.model = "Supra"
        sample.year = "2022"
        sample.color = "Red"
        sample.trim = "A91"
        sample.mileage = "12000"
        sample.notes = "Track-only on weekends"
        sample.photoFileNames = ["a.jpg"]
        sample.photoStorageURLs = ["https://example.com/a.jpg"]
        sample.photoOffsetY = 0.3
        sample.maintenanceRecords = [MaintenanceRecord(serviceType: "Oil Change", date: Date())]
        sample.mods = [CarMod(category: .wheels, name: "Forged 19s", brand: "BBS")]
        sample.engineSoundURL = "https://example.com/sound.m4a"
        sample.isPublic = true

        // privacyFirst: photos/specs/mods kept, mileage/notes/serviceHistory/
        // engineSoundURL emptied.
        sample.publicSharing = .privacyFirst
        let privacyProjection = PublicCar(from: sample, ownerUID: "u", ownerUsername: "u", ownerAvatarURL: nil)
        assert(privacyProjection.mileage.isEmpty)
        assert(privacyProjection.notes.isEmpty)
        assert(privacyProjection.serviceHistory.isEmpty)
        assert(privacyProjection.engineSoundURL == nil)
        assert(!privacyProjection.color.isEmpty && !privacyProjection.trim.isEmpty)
        assert(!privacyProjection.photoURLs.isEmpty && privacyProjection.photoStorageURL?.isEmpty == false)
        assert(!privacyProjection.mods.isEmpty)

        // legacyAllOn: everything kept.
        sample.publicSharing = .legacyAllOn
        let legacyProjection = PublicCar(from: sample, ownerUID: "u", ownerUsername: "u", ownerAvatarURL: nil)
        assert(!legacyProjection.mileage.isEmpty)
        assert(!legacyProjection.notes.isEmpty)
        assert(!legacyProjection.serviceHistory.isEmpty)
        assert(legacyProjection.engineSoundURL != nil)
        assert(!legacyProjection.color.isEmpty && !legacyProjection.trim.isEmpty)
        assert(!legacyProjection.photoURLs.isEmpty && !legacyProjection.mods.isEmpty)

        // Decoding a car JSON without `publicSharing`: legacyAllOn when
        // isPublic=true, privacyFirst when isPublic=false.
        func decodedCar(isPublic: Bool) -> Car {
            let encoder = JSONEncoder()
            var data = try! encoder.encode(sample)
            var obj = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
            obj.removeValue(forKey: "publicSharing")
            obj["isPublic"] = isPublic
            data = try! JSONSerialization.data(withJSONObject: obj)
            return try! JSONDecoder().decode(Car.self, from: data)
        }
        assert(decodedCar(isPublic: true).publicSharing == .legacyAllOn)
        assert(decodedCar(isPublic: false).publicSharing == .privacyFirst)
    }
}
#endif
