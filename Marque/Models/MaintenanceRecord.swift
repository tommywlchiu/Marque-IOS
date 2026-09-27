import Foundation

struct MaintenanceRecord: Identifiable, Codable, Equatable {
    var id: UUID
    var serviceType: String
    var date: Date
    var mileage: String
    var cost: String
    var shop: String
    var notes: String

    // Receipt scanned/attached to this record. `receiptFileName` is the
    // deterministic Storage object name (`{id}.jpg`) and is written locally
    // the moment a receipt image is provided; `receiptStorageURL` is filled
    // in once the async upload completes (may lag behind `receiptFileName`,
    // or be nil while offline). Both are plain Optionals so older Firestore
    // docs without these fields decode with them as nil.
    var receiptFileName: String?
    var receiptStorageURL: String?

    init(
        id: UUID = UUID(),
        serviceType: String = "",
        date: Date = Date(),
        mileage: String = "",
        cost: String = "",
        shop: String = "",
        notes: String = "",
        receiptFileName: String? = nil,
        receiptStorageURL: String? = nil
    ) {
        self.id = id
        self.serviceType = serviceType
        self.date = date
        self.mileage = mileage
        self.cost = cost
        self.shop = shop
        self.notes = notes
        self.receiptFileName = receiptFileName
        self.receiptStorageURL = receiptStorageURL
    }

    // Tolerant parsing per NumberParsing (see ServiceReminderEngine.swift):
    // strips everything but digits (mileage) / digits+one decimal point (cost).
    var mileageValue: Int? { NumberParsing.mileage(from: mileage) }
    var costValue: Double? { NumberParsing.cost(from: cost) }

    static let serviceTypes = [
        "Oil Change",
        "Tire Rotation",
        "Tire Replacement",
        "Brake Service",
        "Battery Replacement",
        "Air Filter",
        "Transmission Service",
        "Coolant Flush",
        "Spark Plugs",
        "Alignment",
        "Inspection",
        "Wash / Detail",
        "Other"
    ]
}
