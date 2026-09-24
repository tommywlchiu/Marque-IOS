import Foundation

struct PublicServiceRecord: Identifiable, Codable {
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
    let photoStorageURL: String?
    let photoOffsetY: Double
    let serviceHistory: [PublicServiceRecord]

    var id: String { carId }
    var displayName: String { [year, make, model].filter { !$0.isEmpty }.joined(separator: " ") }
    var primaryPhotoURL: URL? {
        guard let str = photoStorageURL, !str.isEmpty else { return nil }
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
}

extension PublicCar {
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
        serviceHistory = car.maintenanceRecords.map {
            PublicServiceRecord(serviceType: $0.serviceType, date: $0.date)
        }
    }
}
