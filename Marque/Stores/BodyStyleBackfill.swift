import Foundation

/// Fills in a missing body style from the car's VIN (NHTSA decode), for cars
/// added before Add Car required one. The Garage picks a car's generic studio
/// render by body style, so a blank one would otherwise read as a sedan.
///
/// Same static-enum shape as `NotificationManager`: called from `Marque.swift`
/// whenever `CarStore.cars` changes, plus once with the current value (the
/// `.onChange` pitfall). Each car is tried once — a decode that comes back
/// without a body class isn't retried every launch; a network failure is.
/// Remembers car IDs, not VINs, so it keeps no second copy of the VIN.
@MainActor
enum BodyStyleBackfill {
    private static let attemptedKey = "bodyStyleBackfill.attemptedCarIDs"
    private static var inFlight = Set<UUID>()

    static func run(carStore: CarStore) {
        let attempted = Set(UserDefaults.standard.stringArray(forKey: attemptedKey) ?? [])
        let due = carStore.cars.filter { car in
            car.bodyStyle.isEmpty
                && car.vinNumber.trimmingCharacters(in: .whitespaces).count == 17
                && !attempted.contains(car.id.uuidString)
                && !inFlight.contains(car.id)
        }
        guard !due.isEmpty else { return }
        inFlight.formUnion(due.map(\.id))

        Task {
            for car in due {
                defer { inFlight.remove(car.id) }
                let vin = car.vinNumber.trimmingCharacters(in: .whitespaces)
                guard let result = try? await VINDecodeService.decode(vin: vin) else { continue }
                markAttempted(car.id)
                // Re-read: the user may have edited the car while the decode
                // ran, and their own choice always wins.
                guard !result.bodyStyle.isEmpty,
                      var current = carStore.cars.first(where: { $0.id == car.id }),
                      current.bodyStyle.isEmpty,
                      current.vinNumber.trimmingCharacters(in: .whitespaces) == vin
                else { continue }
                current.bodyStyle = result.bodyStyle
                carStore.updateCar(current)
            }
        }
    }

    private static func markAttempted(_ id: UUID) {
        var attempted = UserDefaults.standard.stringArray(forKey: attemptedKey) ?? []
        attempted.append(id.uuidString)
        UserDefaults.standard.set(attempted, forKey: attemptedKey)
    }
}
