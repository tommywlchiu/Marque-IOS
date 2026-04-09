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
        cars.remove(atOffsets: offsets)
    }

    func deleteCar(_ car: Car) {
        cars.removeAll { $0.id == car.id }
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
