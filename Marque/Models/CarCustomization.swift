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

    /// Roof and body extras: ids of the layers in the render catalog
    /// (`<car>/extras/<id>/`). A cargo box sits on its own crossbars, so it
    /// replaces a plain rack rather than adding to it.
    enum Extra: String, Codable, CaseIterable, Identifiable {
        case rack, box, lightbar, spoiler

        var id: String { rawValue }

        var title: String {
            switch self {
            case .rack: return "Crossbars"
            case .box: return "Cargo Box"
            case .lightbar: return "Light Bar"
            case .spoiler: return "Rear Wing"
            }
        }

        /// Drawing order, back to front.
        var order: Int {
            switch self {
            case .spoiler: return 0
            case .rack, .box: return 1
            case .lightbar: return 2
            }
        }
    }

    var tint: Tint = .none
    var stance: Stance = .stock
    /// A wheel style id from the render catalog's `wheelStyles`; nil = the
    /// car's own wheels.
    var wheels: String?
    /// The extras shown, in drawing order (never both rack and box).
    private(set) var extras: [Extra] = []

    init(tint: Tint = .none, stance: Stance = .stock, wheels: String? = nil, extras: [Extra] = []) {
        self.tint = tint
        self.stance = stance
        self.wheels = wheels
        self.extras = Self.normalized(extras)
    }

    /// Turns one extra on or off; a cargo box and plain crossbars replace
    /// each other.
    mutating func setExtra(_ extra: Extra, on: Bool) {
        var set = extras.filter { $0 != extra }
        if on {
            if extra == .box { set.removeAll { $0 == .rack } }
            if extra == .rack { set.removeAll { $0 == .box } }
            set.append(extra)
        }
        extras = Self.normalized(set)
    }

    private static func normalized(_ extras: [Extra]) -> [Extra] {
        var set = Array(Set(extras))
        if set.contains(.box) { set.removeAll { $0 == .rack } }
        return set.sorted { ($0.order, $0.rawValue) < ($1.order, $1.rawValue) }
    }

    private enum CodingKeys: String, CodingKey { case tint, stance, wheels, extras }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tint = (try? c.decodeIfPresent(Tint.self, forKey: .tint)) ?? .none
        stance = (try? c.decodeIfPresent(Stance.self, forKey: .stance)) ?? .stock
        wheels = try? c.decodeIfPresent(String.self, forKey: .wheels)
        // An id this build doesn't know is dropped, not the whole list.
        let ids = (try? c.decodeIfPresent([String].self, forKey: .extras)) ?? []
        extras = Self.normalized(ids.compactMap(Extra.init(rawValue:)))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(tint, forKey: .tint)
        try c.encode(stance, forKey: .stance)
        try c.encodeIfPresent(wheels, forKey: .wheels)
        if !extras.isEmpty { try c.encode(extras, forKey: .extras) }
    }
}
