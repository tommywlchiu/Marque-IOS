import SwiftUI
import WidgetKit

/// Tesla-widget-style: a dark card, the car's name and one status line, its
/// mileage, and its hero image bleeding off the trailing edge. Reuses
/// `GarageTheme`'s palette (shared with the app target, not duplicated) so a
/// widget always matches the Garage tab exactly.
struct GarageWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: GarageWidgetEntry

    var body: some View {
        content
            .containerBackground(GarageTheme.background, for: .widget)
            .widgetURL(deepLinkURL)
    }

    /// Opens straight to this car in the Garage, reusing the same
    /// `AppDelegate.pendingCarID` path a like/comment push already uses.
    private var deepLinkURL: URL? {
        guard let id = entry.car?.id, id != "placeholder" else { return nil }
        return URL(string: "marque://car/\(id)")
    }

    @ViewBuilder
    private var content: some View {
        if let car = entry.car {
            switch family {
            case .systemSmall:
                SmallGarageWidgetView(car: car)
            default:
                MediumGarageWidgetView(car: car)
            }
        } else {
            EmptyGarageWidgetView()
        }
    }
}

private struct SmallGarageWidgetView: View {
    let car: WidgetCarSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Spacer(minLength: 0)
            HStack(spacing: 5) {
                if car.needsAttention {
                    Circle().fill(GarageTheme.accentDot).frame(width: 6, height: 6)
                }
                Text(car.displayName)
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(GarageTheme.primaryText)
                    .lineLimit(2)
            }
            Text(car.statusText)
                .font(.caption2.weight(.medium))
                .foregroundColor(GarageTheme.secondaryText)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }
}

private struct MediumGarageWidgetView: View {
    let car: WidgetCarSnapshot

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(car.displayName)
                    .font(.headline.weight(.bold))
                    .foregroundColor(GarageTheme.primaryText)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if car.needsAttention {
                        Circle().fill(GarageTheme.accentDot).frame(width: 6, height: 6)
                    }
                    Text(car.statusText)
                        .font(.caption.weight(.medium))
                        .foregroundColor(GarageTheme.secondaryText)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                if let mileage = car.mileageText {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(mileage)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(GarageTheme.primaryText)
                        Text("MILEAGE")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(GarageTheme.tertiaryText)
                            .tracking(0.5)
                    }
                }
            }
            .padding(16)
            Spacer(minLength: 0)
            heroImage
                .frame(width: 112)
                .padding(.trailing, 6)
        }
    }

    @ViewBuilder
    private var heroImage: some View {
        if let fileName = car.heroImageFileName,
           let url = WidgetSharedStore.heroImageURL(fileName: fileName),
           let data = try? Data(contentsOf: url),
           let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "car.side.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(GarageTheme.tertiaryText)
                .padding(22)
        }
    }
}

private struct EmptyGarageWidgetView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "car.side.fill")
                .font(.title2)
                .foregroundColor(GarageTheme.tertiaryText)
            Text("Add a car in Marque")
                .font(.caption)
                .foregroundColor(GarageTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
