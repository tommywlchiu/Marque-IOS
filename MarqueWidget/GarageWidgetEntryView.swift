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
            case .accessoryRectangular:
                AccessoryRectangularView(car: car)
            case .accessoryInline:
                AccessoryInlineView(car: car)
            default:
                MediumGarageWidgetView(car: car)
            }
        } else {
            EmptyGarageWidgetView()
        }
    }
}

/// The car's hero image, or a symbol until one has been produced for it.
private struct WidgetHeroImage: View {
    let car: WidgetCarSnapshot
    var symbolPadding: CGFloat = 22

    var body: some View {
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
                .padding(symbolPadding)
        }
    }
}

private struct SmallGarageWidgetView: View {
    let car: WidgetCarSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            WidgetHeroImage(car: car, symbolPadding: 14)
                .frame(maxWidth: .infinity)
                .frame(height: 64)
                .accessibilityHidden(true)
            Spacer(minLength: 0)
            HStack(spacing: 5) {
                if car.needsAttention {
                    Circle().fill(GarageTheme.accentDot).frame(width: 6, height: 6)
                }
                Text(car.displayName)
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(GarageTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Text(car.statusText)
                .font(.caption2.weight(.medium))
                .foregroundColor(GarageTheme.secondaryText)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(car.displayName). \(car.statusText)")
    }
}

/// Lock Screen widget: name and status in the system's monochrome style.
private struct AccessoryRectangularView: View {
    let car: WidgetCarSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(car.displayName)
                .font(.headline)
                .lineLimit(1)
            Text(car.statusText)
                .font(.caption)
                .lineLimit(2)
            if let mileage = car.mileageText {
                Text(mileage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(car.displayName). \(car.statusText)")
    }
}

private struct AccessoryInlineView: View {
    let car: WidgetCarSnapshot

    var body: some View {
        Label(car.needsAttention ? car.statusText : car.displayName, systemImage: "car.side.fill")
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
            WidgetHeroImage(car: car)
                .frame(width: 112)
                .padding(.trailing, 6)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(car.displayName). \(car.statusText).\(car.mileageText.map { " \($0)." } ?? "")")
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
