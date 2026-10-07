import Foundation

/// Fills in a car's range from EPA figures (`FuelEconomyService`): straight
/// from the EPA for electric cars and plug-in hybrids, and tank size × combined
/// MPG for hybrids and diesels once the owner has entered a tank size.
///
/// Same static-enum shape as `BodyStyleBackfill`, called from the same two
/// places in `Marque.swift`. Never overwrites a range the owner typed; an EPA
/// estimate (`fullRangeIsEstimate`) is refreshed when the details it came from
/// change (year, make, model, trim, engine, drive, fuel type, tank size). Each
/// combination is looked up once — a miss isn't retried every launch, a
/// network failure is.
@MainActor
enum RangeBackfill {
    private static let attemptedKey = "rangeBackfill.attempted"
    private static var inFlight = Set<UUID>()

    static func run(carStore: CarStore) {
        let attempted = Set(UserDefaults.standard.stringArray(forKey: attemptedKey) ?? [])
        let due = carStore.cars.filter { (car: Car) -> Bool in
            guard car.fullRange == nil || car.fullRangeIsEstimate, car.rangeKind != nil else { return false }
            // A hybrid's or diesel's estimate is tank size × MPG.
            if Car.tracksTankSize(fuelType: car.fuelType) && car.tankGallons == nil { return false }
            return !attempted.contains(key(car)) && !inFlight.contains(car.id)
        }
        guard !due.isEmpty else { return }
        inFlight.formUnion(due.map(\.id))

        Task {
            for car in due {
                defer { inFlight.remove(car.id) }
                let figures: FuelEconomyService.Figures?
                do { figures = try await FuelEconomyService.lookup(query(car)) } catch { continue }
                markAttempted(key(car))
                // Re-read: the owner may have edited the car meanwhile, and
                // their own number always wins.
                guard var current = carStore.cars.first(where: { $0.id == car.id }),
                      key(current) == key(car),
                      current.fullRange == nil || current.fullRangeIsEstimate,
                      let range = figures.flatMap({ range(for: current, $0) }),
                      range != current.fullRange
                else { continue }
                current.fullRange = range
                current.fullRangeIsEstimate = true
                carStore.updateCar(current)
            }
        }
    }

    private static func range(for car: Car, _ f: FuelEconomyService.Figures) -> Int? {
        if let r = f.range { return r }
        guard let mpg = f.combinedMPG, let gallons = car.tankGallons else { return nil }
        return Int((Double(mpg) * gallons).rounded())
    }

    private static func query(_ car: Car) -> FuelEconomyService.Query {
        .init(year: car.year, make: car.make, model: car.model, trim: car.trim,
              engine: car.engine, driveType: car.driveType, fuelType: car.fuelType)
    }

    /// Everything the estimate depends on. Car ID included so two identical
    /// cars are each filled.
    private static func key(_ car: Car) -> String {
        [car.id.uuidString, car.year, car.make, car.model, car.trim, car.engine,
         car.driveType, car.fuelType, car.tankGallons.map { "\($0)" } ?? ""]
            .joined(separator: "|")
    }

    private static func markAttempted(_ key: String) {
        var attempted = UserDefaults.standard.stringArray(forKey: attemptedKey) ?? []
        attempted.append(key)
        UserDefaults.standard.set(Array(attempted.suffix(200)), forKey: attemptedKey)
    }
}
