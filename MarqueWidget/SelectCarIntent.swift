import AppIntents

/// The car a given widget instance shows (long-press ▸ Edit Widget). The
/// default, "Current Car", follows whichever car is selected in the Garage and
/// switches with it; picking a specific car pins the widget to it, mirroring
/// Tesla's multi-vehicle widget picker. Backed by whatever `WidgetSharedStore`
/// has on hand — the widget process never queries Firestore directly.
struct CarEntity: AppEntity, Identifiable {
    let id: String
    let displayName: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Car"
    static var defaultQuery = CarEntityQuery()

    /// The "follow the Garage" choice.
    static let currentCar = CarEntity(id: WidgetSharedStore.followSelectedCarID, displayName: "Current Car")

    var isCurrentCar: Bool { id == WidgetSharedStore.followSelectedCarID }

    var displayRepresentation: DisplayRepresentation {
        isCurrentCar
            ? DisplayRepresentation(title: "Current Car", subtitle: "Follows the car selected in Garage")
            : DisplayRepresentation(title: "\(displayName)")
    }
}

struct CarEntityQuery: EntityQuery {
    func entities(for identifiers: [CarEntity.ID]) async throws -> [CarEntity] {
        let cars = WidgetSharedStore.readCars()
        return identifiers.compactMap { id in
            if id == WidgetSharedStore.followSelectedCarID { return CarEntity.currentCar }
            return cars.first { $0.id == id }.map { CarEntity(id: $0.id, displayName: $0.displayName) }
        }
    }

    func suggestedEntities() async throws -> [CarEntity] {
        [CarEntity.currentCar] + WidgetSharedStore.readCars().map { CarEntity(id: $0.id, displayName: $0.displayName) }
    }

    func defaultResult() async -> CarEntity? { CarEntity.currentCar }
}

struct SelectCarIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Choose Car"
    static var description = IntentDescription("Show the car selected in Garage, or pin this widget to one car.")

    /// Named `vehicle`, not `car`: the first version defaulted to the first car
    /// and stored it, pinning every existing widget. A new parameter name drops
    /// that stored value, so those widgets start following the Garage.
    /// Non-optional so the query's `defaultResult()` ("Current Car") is what a
    /// freshly added widget starts with.
    @Parameter(title: "Car")
    var vehicle: CarEntity
}
