import WidgetKit
import SwiftUI

struct MarqueGarageWidget: Widget {
    let kind = "MarqueGarageWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SelectCarIntent.self, provider: GarageWidgetProvider()) { entry in
            GarageWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Garage")
        .description("Your car's mileage and status. Follows the car selected in Garage, or pin one.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
        .contentMarginsDisabled()
    }
}
