import Foundation

/// EPA-rated range by Tesla model/year/trim, researched from Tesla's own
/// historical spec sheets, Wikipedia's Model 3/Model Y articles, and EPA
/// range-tracking sites (evkx.net, InsideEVs), October 2026. Lets
/// `EditVehicleDetailsSheet` offer a "Range Type" picker for a Tesla instead
/// of (well, alongside — the number stays editable after) a blank numeric
/// field: Tesla's own variant names are well known and finite, so a curated
/// local table is both faster and more reliable for them than
/// `FuelEconomyService`'s live fueleconomy.gov fuzzy-match, which still
/// drives every other make.
///
/// Not a guarantee for every build combination — wheel size and some
/// mid-year running changes shift a given trim's EPA number by single-digit
/// miles even within one model year (Tesla's own site shows this), and
/// Tesla has re-rated the same trim retroactively more than once (the 2023
/// Model Y refresh dropped Long Range AWD from 330 to 310 mid-year, for
/// example). These are the figures Tesla and the EPA published for that
/// trim's model year; picking one still leaves the number editable for a
/// car whose actual window sticker reads differently.
enum TeslaRangeCatalog {
    struct Variant: Identifiable {
        let name: String
        let miles: Int
        var id: String { name }
    }

    /// Range variants for this Tesla model/year, best match first, or nil if
    /// the model isn't one of the two in the render catalog (Model S and X
    /// aren't covered — narrower research, add them the same way if wanted).
    static func variants(model: String, year: String) -> [Variant]? {
        guard let y = Int(year.trimmingCharacters(in: .whitespaces)) else { return nil }
        let m = model.lowercased()
        if m.contains("model 3") || m == "3" {
            return model3(y)
        }
        if m.contains("model y") || m == "y" {
            return modelY(y)
        }
        return nil
    }

    private static func model3(_ year: Int) -> [Variant]? {
        switch year {
        case ..<2017: return nil
        case 2017: return [v("Long Range RWD", 310)]
        case 2018: return [v("Mid Range RWD", 264), v("Long Range RWD", 310), v("Long Range AWD", 310), v("Performance", 310)]
        case 2019: return [v("Standard Range", 220), v("Standard Range Plus", 240), v("Mid Range", 264), v("Long Range AWD", 325), v("Performance", 325)]
        case 2020: return [v("Standard Range Plus", 250), v("Long Range AWD", 322), v("Performance", 299)]
        case 2021: return [v("Standard Range Plus", 263), v("Long Range AWD", 353), v("Performance", 315)]
        case 2022: return [v("Standard Range", 272), v("Long Range AWD", 358), v("Performance", 315)]
        case 2023: return [v("Rear-Wheel Drive", 272), v("Long Range AWD", 333), v("Performance", 315)]  // mid-year "Highland" refresh re-rated Long Range/Performance down
        case 2024...: return [v("Rear-Wheel Drive", 272), v("Long Range RWD", 363), v("Long Range AWD", 341), v("Performance", 296)]
        default: return nil
        }
    }

    private static func modelY(_ year: Int) -> [Variant]? {
        switch year {
        case ..<2020: return nil
        case 2020: return [v("Long Range AWD", 316), v("Performance", 303)]
        case 2021: return [v("Standard Range RWD", 244), v("Long Range AWD", 326), v("Performance", 303)]
        case 2022: return [v("Long Range AWD", 330), v("Performance", 303)]
        case 2023: return [v("Rear-Wheel Drive", 260), v("Long Range AWD", 310), v("Performance", 285)]  // mid-year EPA re-rating dropped Long Range from 330 and Performance from 303
        case 2024...: return [v("Rear-Wheel Drive", 260), v("Long Range RWD", 320), v("Long Range AWD", 311), v("Performance", 277)]
        default: return nil
        }
    }

    private static func v(_ name: String, _ miles: Int) -> Variant { Variant(name: name, miles: miles) }
}
