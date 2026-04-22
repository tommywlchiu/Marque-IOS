import Foundation

struct MaintenanceRecord: Identifiable, Codable {
    var id: UUID
    var serviceType: String
    var date: Date
    var mileage: String
    var cost: String
    var shop: String
    var notes: String

    init(
        id: UUID = UUID(),
        serviceType: String = "",
        date: Date = Date(),
        mileage: String = "",
        cost: String = "",
        shop: String = "",
        notes: String = ""
    ) {
        self.id = id
        self.serviceType = serviceType
        self.date = date
        self.mileage = mileage
        self.cost = cost
        self.shop = shop
        self.notes = notes
    }

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
