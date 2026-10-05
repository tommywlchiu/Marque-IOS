import WidgetKit
import SwiftUI

struct MarqueGarageWidget: Widget {
    let kind = "MarqueGarageWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SelectCarIntent.self, provider: GarageWidgetProvider()) { entry in
            GarageWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Garage")
        .description("Your car's mileage and status, Tesla-widget style.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}
