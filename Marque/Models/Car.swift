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
    var notes: String
    var isPublic: Bool

    var maintenanceRecords: [MaintenanceRecord]
    var serviceReminders: [ServiceReminder]

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
        notes: String = "",
        isPublic: Bool = false,
        maintenanceRecords: [MaintenanceRecord] = [],
        serviceReminders: [ServiceReminder] = []
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
        self.notes = notes
        self.isPublic = isPublic
        self.maintenanceRecords = maintenanceRecords
        self.serviceReminders = serviceReminders
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
        case notes, isPublic
        case maintenanceRecords, serviceReminders
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
        notes = try c.decode(String.self, forKey: .notes)
        isPublic = try c.decodeIfPresent(Bool.self, forKey: .isPublic) ?? false
        maintenanceRecords = try c.decode([MaintenanceRecord].self, forKey: .maintenanceRecords)
        serviceReminders = try c.decodeIfPresent([ServiceReminder].self, forKey: .serviceReminders) ?? []
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
        try c.encode(notes, forKey: .notes)
        try c.encode(isPublic, forKey: .isPublic)
        try c.encode(maintenanceRecords, forKey: .maintenanceRecords)
        try c.encode(serviceReminders, forKey: .serviceReminders)
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

    var hasMultiplePhotos: Bool {
        photoFileNames.count > 1
    }

    var displayName: String {
        let parts = [year, make, model].filter { !$0.isEmpty }
        return parts.isEmpty ? "Unknown Car" : parts.joined(separator: " ")
    }

    var hasDetailedInfo: Bool {
        !licensePlate.isEmpty || !vinNumber.isEmpty || !color.isEmpty ||
        !mileage.isEmpty || !trim.isEmpty || !bodyStyle.isEmpty ||
        !driveType.isEmpty || !engine.isEmpty || !fuelType.isEmpty ||
        !transmission.isEmpty || !insuranceProvider.isEmpty ||
        !insurancePolicyNumber.isEmpty || !notes.isEmpty
    }

    var sortedMaintenanceRecords: [MaintenanceRecord] {
        maintenanceRecords.sorted { $0.date > $1.date }
    }

    // Tolerant parse of `mileage` (see NumberParsing in ServiceReminderEngine.swift).
    var mileageValue: Int? { NumberParsing.mileage(from: mileage) }

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

    var hasExpiryWarning: Bool {
        isInsuranceExpiringSoon || isInsuranceExpired ||
        isRegistrationExpiringSoon || isRegistrationExpired
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
