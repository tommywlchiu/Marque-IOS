import AppIntents

/// The car a given widget instance is pinned to (long-press ▸ Edit Widget),
/// mirroring Tesla's own multi-vehicle widget picker. Backed by whatever
/// `WidgetSharedStore` has on hand — the widget process never queries
/// Firestore directly.
struct CarEntity: AppEntity, Identifiable {
    let id: String
    let displayName: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Car"
    static var defaultQuery = CarEntityQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(displayName)")
    }
}

struct CarEntityQuery: EntityQuery {
    func entities(for identifiers: [CarEntity.ID]) async throws -> [CarEntity] {
        WidgetSharedStore.readCars()
            .filter { identifiers.contains($0.id) }
            .map { CarEntity(id: $0.id, displayName: $0.displayName) }
    }

    func suggestedEntities() async throws -> [CarEntity] {
        WidgetSharedStore.readCars().map { CarEntity(id: $0.id, displayName: $0.displayName) }
    }

    func defaultResult() async -> CarEntity? {
        try? await suggestedEntities().first
    }
}

struct SelectCarIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Choose Car"
    static var description = IntentDescription("Choose which car this widget shows.")

    @Parameter(title: "Car")
    var car: CarEntity?
}
