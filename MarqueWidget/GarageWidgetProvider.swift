import WidgetKit

struct GarageWidgetEntry: TimelineEntry {
    let date: Date
    let car: WidgetCarSnapshot?
}

struct GarageWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> GarageWidgetEntry {
        GarageWidgetEntry(date: Date(), car: WidgetCarSnapshot(
            id: "placeholder", displayName: "Your Car", mileageText: "25,000 mi",
            statusText: "All caught up", needsAttention: false, heroImageFileName: nil
        ))
    }

    func snapshot(for configuration: SelectCarIntent, in context: Context) async -> GarageWidgetEntry {
        entry(for: configuration)
    }

    func timeline(for configuration: SelectCarIntent, in context: Context) async -> Timeline<GarageWidgetEntry> {
        // A status line can go stale (midnight rolls a reminder into "due
        // soon", a new day changes "Expires in N days") even with no car
        // data change. The app rewrites them whenever it comes forward and
        // whenever a car changes (and pokes WidgetCenter.reloadAllTimelines());
        // this asks the system to reload just after midnight, with a 4-hour
        // cap as a backstop.
        let entry = entry(for: configuration)
        let calendar = Calendar.current
        let midnight = calendar.nextDate(after: Date(), matching: DateComponents(hour: 0, minute: 5), matchingPolicy: .nextTime)
        let cap = Date().addingTimeInterval(4 * 3600)
        return Timeline(entries: [entry], policy: .after(min(midnight ?? cap, cap)))
    }

    private func entry(for configuration: SelectCarIntent) -> GarageWidgetEntry {
        let cars = WidgetSharedStore.readCars()
        // "Current Car" (the default, or no choice at all) follows the Garage.
        // A pinned car that no longer exists falls back to following it too.
        let pinned = (configuration.vehicle.isCurrentCar ? nil : configuration.vehicle.id).flatMap { id in cars.first { $0.id == id } }
        let selected = pinned
            ?? WidgetSharedStore.readSelectedCarID().flatMap { id in cars.first { $0.id == id } }
            ?? cars.first
        return GarageWidgetEntry(date: Date(), car: selected)
    }
}
