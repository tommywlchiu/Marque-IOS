import Foundation

struct Car: Identifiable, Codable, Equatable {
    var id: UUID
    var make: String
    var model: String
    var year: String
    var photoFileName: String?

    var licensePlate: String
    var vinNumber: String
    var color: String
    var mileage: String
    var fuelType: String
    var transmission: String
    var insuranceProvider: String
    var insurancePolicyNumber: String
    var insuranceExpiryDate: Date?
    var registrationExpiryDate: Date?
    var notes: String

    var maintenanceRecords: [MaintenanceRecord]

    init(
        id: UUID = UUID(),
        make: String = "",
        model: String = "",
        year: String = "",
        photoFileName: String? = nil,
        licensePlate: String = "",
        vinNumber: String = "",
        color: String = "",
        mileage: String = "",
        fuelType: String = "",
        transmission: String = "",
        insuranceProvider: String = "",
        insurancePolicyNumber: String = "",
        insuranceExpiryDate: Date? = nil,
        registrationExpiryDate: Date? = nil,
        notes: String = "",
        maintenanceRecords: [MaintenanceRecord] = []
    ) {
        self.id = id
        self.make = make
        self.model = model
        self.year = year
        self.photoFileName = photoFileName
        self.licensePlate = licensePlate
        self.vinNumber = vinNumber
        self.color = color
        self.mileage = mileage
        self.fuelType = fuelType
        self.transmission = transmission
        self.insuranceProvider = insuranceProvider
        self.insurancePolicyNumber = insurancePolicyNumber
        self.insuranceExpiryDate = insuranceExpiryDate
        self.registrationExpiryDate = registrationExpiryDate
        self.notes = notes
        self.maintenanceRecords = maintenanceRecords
    }

    var displayName: String {
        let parts = [year, make, model].filter { !$0.isEmpty }
        return parts.isEmpty ? "Unknown Car" : parts.joined(separator: " ")
    }

    var hasDetailedInfo: Bool {
        !licensePlate.isEmpty || !vinNumber.isEmpty || !color.isEmpty ||
        !mileage.isEmpty || !fuelType.isEmpty || !transmission.isEmpty ||
        !insuranceProvider.isEmpty || !insurancePolicyNumber.isEmpty || !notes.isEmpty
    }

    var sortedMaintenanceRecords: [MaintenanceRecord] {
        maintenanceRecords.sorted { $0.date > $1.date }
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
}
