import Foundation

/// Open NHTSA recalls, keyed by make+model+year (not by car — every owner of
/// the same model shares the same recall list). In-memory for the running
/// session only: recall data is public and free to re-fetch, and the volume
/// is tiny (one NHTSA call per distinct make/model/year the user's garage
/// has, once per launch), so there's no need for the disk-cache-with-TTL
/// machinery `CarCutoutRenderer` or the render catalog use for genuinely
/// expensive fetches.
@MainActor
final class RecallStore: ObservableObject {
    @Published private(set) var recallsByVehicle: [String: [Recall]] = [:]
    private var fetching: Set<String> = []

    private static func key(make: String, model: String, year: String) -> String {
        "\(make.lowercased())|\(model.lowercased())|\(year)"
    }

    func recalls(for car: Car) -> [Recall] {
        recallsByVehicle[Self.key(make: car.make, model: car.model, year: car.year)] ?? []
    }

    /// Fetches once per distinct make+model+year per session; a second call
    /// for a car that shares that key with one already loaded (or loading)
    /// is a no-op.
    func ensureLoaded(for car: Car) {
        guard !car.make.isEmpty, !car.model.isEmpty, !car.year.isEmpty else { return }
        let key = Self.key(make: car.make, model: car.model, year: car.year)
        guard recallsByVehicle[key] == nil, !fetching.contains(key) else { return }
        fetching.insert(key)
        Task {
            defer { fetching.remove(key) }
            guard let recalls = try? await RecallService.fetchRecalls(make: car.make, model: car.model, year: car.year) else { return }
            recallsByVehicle[key] = recalls
        }
    }
}
