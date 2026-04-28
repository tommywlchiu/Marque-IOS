import Foundation

class CarStore: ObservableObject {
    @Published var cars: [Car] = [] {
        didSet {
            save()
        }
    }

    private let saveKey = "marque_saved_cars"

    init() {
        load()
    }

    func addCar(_ car: Car) {
        cars.append(car)
    }

    func updateCar(_ car: Car) {
        if let index = cars.firstIndex(where: { $0.id == car.id }) {
            cars[index] = car
        }
    }

    func deleteCar(at offsets: IndexSet) {
        for index in offsets {
            if let fileName = cars[index].photoFileName {
                ImageManager.deleteImage(fileName: fileName)
            }
        }
        cars.remove(atOffsets: offsets)
    }

    func deleteCar(_ car: Car) {
        if let fileName = car.photoFileName {
            ImageManager.deleteImage(fileName: fileName)
        }
        cars.removeAll { $0.id == car.id }
    }

    func addMaintenanceRecord(_ record: MaintenanceRecord, to car: Car) {
        if let index = cars.firstIndex(where: { $0.id == car.id }) {
            cars[index].maintenanceRecords.append(record)
        }
    }

    func deleteMaintenanceRecord(_ record: MaintenanceRecord, from car: Car) {
        if let index = cars.firstIndex(where: { $0.id == car.id }) {
            cars[index].maintenanceRecords.removeAll { $0.id == record.id }
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(cars) {
            UserDefaults.standard.set(data, forKey: saveKey)
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: saveKey),
           let decoded = try? JSONDecoder().decode([Car].self, from: data) {
            cars = decoded
        }
    }

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
                    MaintenanceRecord(
                        serviceType: "Tire Rotation",
                        date: calendar.date(byAdding: .day, value: -30, to: now)!,
                        mileage: "18,000",
                        cost: "35",
                        shop: "Discount Tire"
                    ),
                    MaintenanceRecord(
                        serviceType: "Inspection",
                        date: calendar.date(byAdding: .month, value: -4, to: now)!,
                        mileage: "14,200",
                        cost: "0",
                        shop: "Tesla Service Center"
                    ),
                    MaintenanceRecord(
                        serviceType: "Wash / Detail",
                        date: calendar.date(byAdding: .day, value: -12, to: now)!,
                        mileage: "18,300",
                        cost: "150",
                        shop: "Elite Auto Spa"
                    )
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
                    MaintenanceRecord(
                        serviceType: "Oil Change",
                        date: calendar.date(byAdding: .day, value: -15, to: now)!,
                        mileage: "42,500",
                        cost: "65",
                        shop: "Valvoline Instant Oil Change"
                    ),
                    MaintenanceRecord(
                        serviceType: "Brake Service",
                        date: calendar.date(byAdding: .month, value: -2, to: now)!,
                        mileage: "40,100",
                        cost: "380",
                        shop: "Pep Boys",
                        notes: "Front brake pads and rotors replaced"
                    ),
                    MaintenanceRecord(
                        serviceType: "Tire Replacement",
                        date: calendar.date(byAdding: .month, value: -5, to: now)!,
                        mileage: "36,000",
                        cost: "640",
                        shop: "Costco Tire Center",
                        notes: "Full set of Michelin Defender tires"
                    ),
                    MaintenanceRecord(
                        serviceType: "Air Filter",
                        date: calendar.date(byAdding: .month, value: -7, to: now)!,
                        mileage: "33,200",
                        cost: "25",
                        shop: "DIY"
                    ),
                    MaintenanceRecord(
                        serviceType: "Oil Change",
                        date: calendar.date(byAdding: .month, value: -8, to: now)!,
                        mileage: "31,500",
                        cost: "55",
                        shop: "Jiffy Lube"
                    )
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
                    MaintenanceRecord(
                        serviceType: "Oil Change",
                        date: calendar.date(byAdding: .day, value: -20, to: now)!,
                        mileage: "28,000",
                        cost: "95",
                        shop: "BMW of Stevens Creek"
                    ),
                    MaintenanceRecord(
                        serviceType: "Alignment",
                        date: calendar.date(byAdding: .month, value: -3, to: now)!,
                        mileage: "25,800",
                        cost: "120",
                        shop: "BMW of Stevens Creek"
                    ),
                    MaintenanceRecord(
                        serviceType: "Wash / Detail",
                        date: calendar.date(byAdding: .day, value: -5, to: now)!,
                        mileage: "28,300",
                        cost: "200",
                        shop: "Prestige Auto Detail",
                        notes: "Full interior and exterior detail with ceramic coating"
                    )
                ]
            ),
            Car(
                make: "Honda",
                model: "Civic",
                year: "2019",
                licensePlate: "5XYZ114",
                vinNumber: "2HGFC2F69KH567890",
                color: "Blue",
                mileage: "67,210",
                fuelType: "Gasoline",
                transmission: "CVT",
                insuranceProvider: "Allstate",
                insurancePolicyNumber: "AL-33019284",
                insuranceExpiryDate: calendar.date(byAdding: .month, value: 2, to: now),
                registrationExpiryDate: calendar.date(byAdding: .month, value: 1, to: now),
                maintenanceRecords: [
                    MaintenanceRecord(
                        serviceType: "Oil Change",
                        date: calendar.date(byAdding: .day, value: -7, to: now)!,
                        mileage: "67,000",
                        cost: "45",
                        shop: "Jiffy Lube"
                    ),
                    MaintenanceRecord(
                        serviceType: "Transmission Service",
                        date: calendar.date(byAdding: .month, value: -1, to: now)!,
                        mileage: "65,500",
                        cost: "210",
                        shop: "Honda Dealership",
                        notes: "CVT fluid change"
                    ),
                    MaintenanceRecord(
                        serviceType: "Spark Plugs",
                        date: calendar.date(byAdding: .month, value: -3, to: now)!,
                        mileage: "62,000",
                        cost: "180",
                        shop: "Midas"
                    ),
                    MaintenanceRecord(
                        serviceType: "Battery Replacement",
                        date: calendar.date(byAdding: .month, value: -6, to: now)!,
                        mileage: "58,000",
                        cost: "165",
                        shop: "AutoZone",
                        notes: "Interstate battery MTX-51R"
                    ),
                    MaintenanceRecord(
                        serviceType: "Brake Service",
                        date: calendar.date(byAdding: .month, value: -9, to: now)!,
                        mileage: "53,000",
                        cost: "290",
                        shop: "Midas",
                        notes: "Rear brakes replaced"
                    ),
                    MaintenanceRecord(
                        serviceType: "Coolant Flush",
                        date: calendar.date(byAdding: .month, value: -11, to: now)!,
                        mileage: "50,500",
                        cost: "110",
                        shop: "Honda Dealership"
                    )
                ]
            )
        ]
    }
}
