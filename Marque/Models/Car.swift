import Foundation

struct Car: Identifiable, Codable, Equatable {
    var id: UUID
    var make: String
    var model: String
    var year: String

    // Ordered list of photo filenames stored in the app's Documents/CarPhotos
    // directory. The first entry is treated as the primary (cover) photo.
    var photoFileNames: [String]
    // Firebase Storage download URLs, parallel to photoFileNames. Empty string
    // means the photo hasn't been uploaded to Storage yet.
    var photoStorageURLs: [String]
    var photoOffsetY: Double

    var licensePlate: String
    var vinNumber: String
    var color: String
    var mileage: String
    // Set whenever `mileage` is bumped by CarStore (logService or
    // updateMileage). nil means it has never been set this way (e.g. only
    // ever edited by hand in EditCarDetailView, or a pre-existing car).
    var mileageUpdatedAt: Date?
    var trim: String
    var bodyStyle: String
    var driveType: String
    var engine: String
    var fuelType: String
    var transmission: String
    var insuranceProvider: String
    var insurancePolicyNumber: String
    var insuranceExpiryDate: Date?
    var registrationExpiryDate: Date?
    // Warranty, like specs, has no expiry tracking (owner decision) — just
    // who covers it and what kind. Private only; never reaches PublicCar.
    var warrantyProvider: String
    var warrantyType: String
    var notes: String
    var isPublic: Bool

    // Per-car Explore sharing toggles (photos/specs/mileage/notes/
    // serviceHistory/mods/engineSound). Estimated value stays on
    // `showValuePublicly` below, not here. `PublicCar(from:)` is the only
    // place that must honor this — see its doc comment and CarStore's
    // "Public copy" section.
    var publicSharing: PublicSharingSettings

    // Estimated market value (USD). Private: only `CarValueRange.publicLabel`
    // of it ever reaches publicCars, and only when `showValuePublicly` is on.
    var estimatedValue: Double?
    // Who produced `estimatedValue`: the owner typing it, or an accepted AI
    // estimate (CarStore.estimateValue). nil when there's no value.
    var valueSource: CarValueSource?
    var valueUpdatedAt: Date?
    var showValuePublicly: Bool

    // Engine sound clip (AAC .m4a, <= 5 s). `engineSoundFileName` is the local
    // file under Documents/CarPhotos (ImageManager.fileURL); `engineSoundURL`
    // is the Storage download URL of users/{uid}/cars/{carId}/sound.m4a, nil
    // until the upload lands.
    var engineSoundFileName: String?
    var engineSoundURL: String?
    var engineSoundDuration: Double?

    var maintenanceRecords: [MaintenanceRecord]
    var serviceReminders: [ServiceReminder]
    var mods: [CarMod]

    /// The most modifications a car can carry. Enforced client-side by
    /// `CarStore.addMod` (the private `users/{uid}/cars` doc has no deep
    /// rules validation, same as maintenanceRecords/serviceReminders); the
    /// number here MUST match the `mods.size() <= 30` check in
    /// firestore.rules' publicCars validation, or a car at the cap could
    /// fail to publish.
    static let maxMods = 30

    init(
        id: UUID = UUID(),
        make: String = "",
        model: String = "",
        year: String = "",
        photoFileNames: [String] = [],
        photoStorageURLs: [String] = [],
        photoOffsetY: Double = 0,
        licensePlate: String = "",
        vinNumber: String = "",
        color: String = "",
        mileage: String = "",
        mileageUpdatedAt: Date? = nil,
        trim: String = "",
        bodyStyle: String = "",
        driveType: String = "",
        engine: String = "",
        fuelType: String = "",
        transmission: String = "",
        insuranceProvider: String = "",
        insurancePolicyNumber: String = "",
        insuranceExpiryDate: Date? = nil,
        registrationExpiryDate: Date? = nil,
        warrantyProvider: String = "",
        warrantyType: String = "",
        notes: String = "",
        isPublic: Bool = false,
        publicSharing: PublicSharingSettings = .privacyFirst,
        estimatedValue: Double? = nil,
        valueSource: CarValueSource? = nil,
        valueUpdatedAt: Date? = nil,
        showValuePublicly: Bool = false,
        engineSoundFileName: String? = nil,
        engineSoundURL: String? = nil,
        engineSoundDuration: Double? = nil,
        maintenanceRecords: [MaintenanceRecord] = [],
        serviceReminders: [ServiceReminder] = [],
        mods: [CarMod] = []
    ) {
        self.id = id
        self.make = make
        self.model = model
        self.year = year
        self.photoFileNames = photoFileNames
        self.photoStorageURLs = photoStorageURLs
        self.photoOffsetY = photoOffsetY
        self.licensePlate = licensePlate
        self.vinNumber = vinNumber
        self.color = color
        self.mileage = mileage
        self.mileageUpdatedAt = mileageUpdatedAt
        self.trim = trim
        self.bodyStyle = bodyStyle
        self.driveType = driveType
        self.engine = engine
        self.fuelType = fuelType
        self.transmission = transmission
        self.insuranceProvider = insuranceProvider
        self.insurancePolicyNumber = insurancePolicyNumber
        self.insuranceExpiryDate = insuranceExpiryDate
        self.registrationExpiryDate = registrationExpiryDate
        self.warrantyProvider = warrantyProvider
        self.warrantyType = warrantyType
        self.notes = notes
        self.isPublic = isPublic
        self.publicSharing = publicSharing
        self.estimatedValue = estimatedValue
        self.valueSource = valueSource
        self.valueUpdatedAt = valueUpdatedAt
        self.showValuePublicly = showValuePublicly
        self.engineSoundFileName = engineSoundFileName
        self.engineSoundURL = engineSoundURL
        self.engineSoundDuration = engineSoundDuration
        self.maintenanceRecords = maintenanceRecords
        self.serviceReminders = serviceReminders
        self.mods = mods
    }

    // Includes a legacy `photoFileName` key so previously-saved single-photo
    // data continues to load after the multi-photo migration.
    private enum CodingKeys: String, CodingKey {
        case id, make, model, year
        case photoFileNames
        case legacyPhotoFileName = "photoFileName"
        case photoStorageURLs
        case photoOffsetY
        case licensePlate, vinNumber, color, mileage, mileageUpdatedAt, trim, bodyStyle, driveType, engine
        case fuelType, transmission
        case insuranceProvider, insurancePolicyNumber
        case insuranceExpiryDate, registrationExpiryDate
        case warrantyProvider, warrantyType
        case notes, isPublic
        case publicSharing
        case estimatedValue, valueSource, valueUpdatedAt, showValuePublicly
        case engineSoundFileName, engineSoundURL, engineSoundDuration
        case maintenanceRecords, serviceReminders
        case mods
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        make = try c.decode(String.self, forKey: .make)
        model = try c.decode(String.self, forKey: .model)
        year = try c.decode(String.self, forKey: .year)

        if let names = try c.decodeIfPresent([String].self, forKey: .photoFileNames), !names.isEmpty {
            photoFileNames = names
        } else if let legacy = try c.decodeIfPresent(String.self, forKey: .legacyPhotoFileName) {
            photoFileNames = [legacy]
        } else {
            photoFileNames = []
        }

        photoStorageURLs = try c.decodeIfPresent([String].self, forKey: .photoStorageURLs) ?? []
        photoOffsetY = try c.decodeIfPresent(Double.self, forKey: .photoOffsetY) ?? 0
        licensePlate = try c.decode(String.self, forKey: .licensePlate)
        vinNumber = try c.decode(String.self, forKey: .vinNumber)
        color = try c.decode(String.self, forKey: .color)
        mileage = try c.decode(String.self, forKey: .mileage)
        mileageUpdatedAt = try c.decodeIfPresent(Date.self, forKey: .mileageUpdatedAt)
        trim = try c.decodeIfPresent(String.self, forKey: .trim) ?? ""
        bodyStyle = try c.decodeIfPresent(String.self, forKey: .bodyStyle) ?? ""
        driveType = try c.decodeIfPresent(String.self, forKey: .driveType) ?? ""
        engine = try c.decodeIfPresent(String.self, forKey: .engine) ?? ""
        fuelType = try c.decode(String.self, forKey: .fuelType)
        transmission = try c.decode(String.self, forKey: .transmission)
        insuranceProvider = try c.decode(String.self, forKey: .insuranceProvider)
        insurancePolicyNumber = try c.decode(String.self, forKey: .insurancePolicyNumber)
        insuranceExpiryDate = try c.decodeIfPresent(Date.self, forKey: .insuranceExpiryDate)
        registrationExpiryDate = try c.decodeIfPresent(Date.self, forKey: .registrationExpiryDate)
        warrantyProvider = try c.decodeIfPresent(String.self, forKey: .warrantyProvider) ?? ""
        warrantyType = try c.decodeIfPresent(String.self, forKey: .warrantyType) ?? ""
        notes = try c.decode(String.self, forKey: .notes)
        isPublic = try c.decodeIfPresent(Bool.self, forKey: .isPublic) ?? false
        // Missing key (every car saved before this feature existed): an
        // already-public car keeps sharing everything it always has (no
        // visible change in Explore) until the owner reviews; an already-
        // private car gets the new privacy-first defaults the first time
        // it's made public, since it never had a reviewed public footprint.
        if let decoded = try? c.decodeIfPresent(PublicSharingSettings.self, forKey: .publicSharing) {
            publicSharing = decoded
        } else {
            publicSharing = isPublic ? .legacyAllOn : .privacyFirst
        }
        // All optional/defaulted: every car saved before these fields existed
        // has none of them. `try?` on the enum so an unknown future source
        // string degrades to nil instead of failing the whole car's decode.
        estimatedValue = try c.decodeIfPresent(Double.self, forKey: .estimatedValue)
        valueSource = (try? c.decodeIfPresent(CarValueSource.self, forKey: .valueSource)) ?? nil
        valueUpdatedAt = try c.decodeIfPresent(Date.self, forKey: .valueUpdatedAt)
        showValuePublicly = try c.decodeIfPresent(Bool.self, forKey: .showValuePublicly) ?? false
        engineSoundFileName = try c.decodeIfPresent(String.self, forKey: .engineSoundFileName)
        engineSoundURL = try c.decodeIfPresent(String.self, forKey: .engineSoundURL)
        engineSoundDuration = try c.decodeIfPresent(Double.self, forKey: .engineSoundDuration)
        maintenanceRecords = try c.decode([MaintenanceRecord].self, forKey: .maintenanceRecords)
        serviceReminders = try c.decodeIfPresent([ServiceReminder].self, forKey: .serviceReminders) ?? []
        mods = try c.decodeIfPresent([CarMod].self, forKey: .mods) ?? []
    }

    // Skip writing the legacy key — new data is written under photoFileNames.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(make, forKey: .make)
        try c.encode(model, forKey: .model)
        try c.encode(year, forKey: .year)
        try c.encode(photoFileNames, forKey: .photoFileNames)
        try c.encode(photoStorageURLs, forKey: .photoStorageURLs)
        try c.encode(photoOffsetY, forKey: .photoOffsetY)
        try c.encode(licensePlate, forKey: .licensePlate)
        try c.encode(vinNumber, forKey: .vinNumber)
        try c.encode(color, forKey: .color)
        try c.encode(mileage, forKey: .mileage)
        try c.encodeIfPresent(mileageUpdatedAt, forKey: .mileageUpdatedAt)
        try c.encode(trim, forKey: .trim)
        try c.encode(bodyStyle, forKey: .bodyStyle)
        try c.encode(driveType, forKey: .driveType)
        try c.encode(engine, forKey: .engine)
        try c.encode(fuelType, forKey: .fuelType)
        try c.encode(transmission, forKey: .transmission)
        try c.encode(insuranceProvider, forKey: .insuranceProvider)
        try c.encode(insurancePolicyNumber, forKey: .insurancePolicyNumber)
        try c.encodeIfPresent(insuranceExpiryDate, forKey: .insuranceExpiryDate)
        try c.encodeIfPresent(registrationExpiryDate, forKey: .registrationExpiryDate)
        try c.encode(warrantyProvider, forKey: .warrantyProvider)
        try c.encode(warrantyType, forKey: .warrantyType)
        try c.encode(notes, forKey: .notes)
        try c.encode(isPublic, forKey: .isPublic)
        try c.encode(publicSharing, forKey: .publicSharing)
        try c.encodeIfPresent(estimatedValue, forKey: .estimatedValue)
        try c.encodeIfPresent(valueSource, forKey: .valueSource)
        try c.encodeIfPresent(valueUpdatedAt, forKey: .valueUpdatedAt)
        try c.encode(showValuePublicly, forKey: .showValuePublicly)
        try c.encodeIfPresent(engineSoundFileName, forKey: .engineSoundFileName)
        try c.encodeIfPresent(engineSoundURL, forKey: .engineSoundURL)
        try c.encodeIfPresent(engineSoundDuration, forKey: .engineSoundDuration)
        try c.encode(maintenanceRecords, forKey: .maintenanceRecords)
        try c.encode(serviceReminders, forKey: .serviceReminders)
        try c.encode(mods, forKey: .mods)
    }

    var primaryPhotoFileName: String? {
        photoFileNames.first
    }

    var primaryPhotoStorageURL: URL? {
        guard let str = photoStorageURLs.first, !str.isEmpty else { return nil }
        return URL(string: str)
    }

    func storageURL(at index: Int) -> URL? {
        guard index < photoStorageURLs.count else { return nil }
        let str = photoStorageURLs[index]
        return str.isEmpty ? nil : URL(string: str)
    }

    /// Every uploaded photo's Storage URL, cover first, skipping photos whose
    /// upload hasn't landed. What publicCars.photoURLs carries.
    var uploadedPhotoURLStrings: [String] {
        photoStorageURLs.prefix(photoFileNames.count).filter { !$0.isEmpty }
    }

    /// A car with at least one mod counts as "Modified" — drives the Explore
    /// filter (PublicCar.isModified mirrors this).
    var isModified: Bool {
        !mods.isEmpty
    }

    var displayName: String {
        let parts = [year, make, model].filter { !$0.isEmpty }
        return parts.isEmpty ? "Unknown Car" : parts.joined(separator: " ")
    }

    var sortedMaintenanceRecords: [MaintenanceRecord] {
        maintenanceRecords.sorted { $0.date > $1.date }
    }

    // Tolerant parse of `mileage` (see NumberParsing in ServiceReminderEngine.swift).
    var mileageValue: Int? { NumberParsing.mileage(from: mileage) }

    /// Formatted "28,450 mi", or nil if unset. `mileage` is free text (the
    /// field's own placeholder suggests including "mi"), so appending " mi"
    /// to it directly double-units a value a user already typed with the
    /// unit — always go through this (or `mileageValue`) instead of reading
    /// `mileage` raw wherever a unit-suffixed display string is needed.
    var mileageText: String? { mileageValue.map { "\($0.formatted()) mi" } }

    // Drives NotificationManager's mileage check-in alert (FR-14-adjacent):
    // a mileage-only reminder can never fire a date-based local notification,
    // so instead we periodically nudge the user to update their mileage.
    var hasOpenMileageReminders: Bool {
        serviceReminders.contains { !$0.isCompleted && $0.dueMileage != nil }
    }

    var isInsuranceExpiringSoon: Bool {
        guard let date = insuranceExpiryDate else { return false }
        let daysUntil = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0
        return daysUntil >= 0 && daysUntil <= 30
    }

    var isInsuranceExpired: Bool {
        guard let date = insuranceExpiryDate else { return false }
        return date < Date()
    }

    var isRegistrationExpiringSoon: Bool {
        guard let date = registrationExpiryDate else { return false }
        let daysUntil = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0
        return daysUntil >= 0 && daysUntil <= 30
    }

    var isRegistrationExpired: Bool {
        guard let date = registrationExpiryDate else { return false }
        return date < Date()
    }

    var totalExpenses: Double {
        maintenanceRecords.compactMap { $0.costValue }.reduce(0, +)
    }

    func expenses(in period: ExpensePeriod) -> Double {
        let now = Date()
        let calendar = Calendar.current
        let startDate: Date
        switch period {
        case .month:
            startDate = calendar.date(byAdding: .month, value: -1, to: now) ?? now
        case .sixMonths:
            startDate = calendar.date(byAdding: .month, value: -6, to: now) ?? now
        case .year:
            startDate = calendar.date(byAdding: .year, value: -1, to: now) ?? now
        case .allTime:
            return totalExpenses
        }
        return maintenanceRecords
            .filter { $0.date >= startDate }
            .compactMap { $0.costValue }
            .reduce(0, +)
    }

    func expensesByCategory(in period: ExpensePeriod) -> [(category: String, amount: Double)] {
        let now = Date()
        let calendar = Calendar.current
        let filtered: [MaintenanceRecord]
        switch period {
        case .month:
            let start = calendar.date(byAdding: .month, value: -1, to: now) ?? now
            filtered = maintenanceRecords.filter { $0.date >= start }
        case .sixMonths:
            let start = calendar.date(byAdding: .month, value: -6, to: now) ?? now
            filtered = maintenanceRecords.filter { $0.date >= start }
        case .year:
            let start = calendar.date(byAdding: .year, value: -1, to: now) ?? now
            filtered = maintenanceRecords.filter { $0.date >= start }
        case .allTime:
            filtered = maintenanceRecords
        }

        var grouped: [String: Double] = [:]
        for record in filtered {
            if let cost = record.costValue, cost > 0 {
                grouped[record.serviceType, default: 0] += cost
            }
        }
        return grouped.map { (category: $0.key, amount: $0.value) }
            .sorted { $0.amount > $1.amount }
    }
}

enum ExpensePeriod: String, CaseIterable {
    case month = "30 Days"
    case sixMonths = "6 Months"
    case year = "1 Year"
    case allTime = "All Time"
}
