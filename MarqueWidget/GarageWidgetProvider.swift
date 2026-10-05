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
        // data change; refresh a few times a day as a backstop. The app
        // itself also pokes WidgetCenter.reloadAllTimelines() whenever a
        // car's data actually changes, which is the primary refresh path.
        let entry = entry(for: configuration)
        let next = Calendar.current.date(byAdding: .hour, value: 4, to: Date()) ?? Date().addingTimeInterval(4 * 3600)
        return Timeline(entries: [entry], policy: .after(next))
    }

    private func entry(for configuration: SelectCarIntent) -> GarageWidgetEntry {
        let cars = WidgetSharedStore.readCars()
        let selected = configuration.car.flatMap { chosen in cars.first { $0.id == chosen.id } } ?? cars.first
        return GarageWidgetEntry(date: Date(), car: selected)
    }
}
