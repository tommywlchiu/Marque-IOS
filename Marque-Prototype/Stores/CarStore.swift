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
}
