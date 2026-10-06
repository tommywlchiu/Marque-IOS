import Foundation

/// How the owner has dressed their car's studio render in the Garage — layers
/// the app draws over the pre-rendered frames (`RenderedCarSpinView`), never
/// re-rendered per user. Private: stored on the owner's `Car`, never copied
/// to `PublicCar`.
///
/// Decoding is lenient: a value written by a newer app (a tint level this
/// build doesn't know) falls back to the default instead of failing the
/// whole car.
struct CarCustomization: Codable, Equatable {
    enum Tint: String, Codable, CaseIterable, Identifiable {
        case none, light, medium, limo

        var id: String { rawValue }

        var title: String {
            switch self {
            case .none: return "None"
            case .light: return "Light"
            case .medium: return "Medium"
            case .limo: return "Limo"
            }
        }

        /// How dark the glass goes: the black drawn through the window mask.
        var opacity: Float {
            switch self {
            case .none: return 0
            case .light: return 0.35
            case .medium: return 0.6
            case .limo: return 0.85
            }
        }
    }

    var tint: Tint = .none

    init(tint: Tint = .none) {
        self.tint = tint
    }

    private enum CodingKeys: String, CodingKey { case tint }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tint = (try? c.decodeIfPresent(Tint.self, forKey: .tint)) ?? .none
    }
}
