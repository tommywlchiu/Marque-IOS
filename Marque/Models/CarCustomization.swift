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

    enum Stance: String, Codable, CaseIterable, Identifiable {
        case stock, lowered, lifted

        var id: String { rawValue }
        var title: String { rawValue.capitalized }

        /// How far the body moves relative to the wheels, in meters.
        var lift: Double {
            switch self {
            case .stock: return 0
            case .lowered: return -0.05
            case .lifted: return 0.06
            }
        }
    }

    var tint: Tint = .none
    var stance: Stance = .stock
    /// A wheel style id from the render catalog's `wheelStyles`; nil = the
    /// car's own wheels.
    var wheels: String?

    init(tint: Tint = .none, stance: Stance = .stock, wheels: String? = nil) {
        self.tint = tint
        self.stance = stance
        self.wheels = wheels
    }

    private enum CodingKeys: String, CodingKey { case tint, stance, wheels }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tint = (try? c.decodeIfPresent(Tint.self, forKey: .tint)) ?? .none
        stance = (try? c.decodeIfPresent(Stance.self, forKey: .stance)) ?? .stock
        wheels = try? c.decodeIfPresent(String.self, forKey: .wheels)
    }
}
