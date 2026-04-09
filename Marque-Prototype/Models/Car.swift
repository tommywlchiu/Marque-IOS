import Foundation

struct Car: Identifiable, Codable {
    var id: UUID
    var make: String
    var model: String
    var year: String

    // Detailed info (added after initial creation)
    var licensePlate: String
    var vinNumber: String
    var color: String
    var mileage: String
    var fuelType: String
    var transmission: String
    var insuranceProvider: String
    var insurancePolicyNumber: String
    var notes: String

    init(
        id: UUID = UUID(),
        make: String = "",
        model: String = "",
        year: String = "",
        licensePlate: String = "",
        vinNumber: String = "",
        color: String = "",
        mileage: String = "",
        fuelType: String = "",
        transmission: String = "",
        insuranceProvider: String = "",
        insurancePolicyNumber: String = "",
        notes: String = ""
    ) {
        self.id = id
        self.make = make
        self.model = model
        self.year = year
        self.licensePlate = licensePlate
        self.vinNumber = vinNumber
        self.color = color
        self.mileage = mileage
        self.fuelType = fuelType
        self.transmission = transmission
        self.insuranceProvider = insuranceProvider
        self.insurancePolicyNumber = insurancePolicyNumber
        self.notes = notes
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
}
