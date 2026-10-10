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

    /// A seat-color option from the render catalog's `<car>/seats/` layers
    /// (`CarRenderLibrary.Entry.seats`); `.standard` draws nothing extra —
    /// the car's own seats, already baked into its frames. Most cars have no
    /// seats add-on at all (the model's interior isn't a separable material),
    /// so this only ever shows as a choice for the few that do.
    enum SeatColor: String, Codable, CaseIterable, Identifiable {
        case standard, black

        var id: String { rawValue }
        var title: String { self == .standard ? "Standard" : "Black" }
    }

    /// The rear-wing spoiler's finish — a selectable material on the same
    /// extra, not a second extra: `carbon` draws the `spoiler-carbon` layer
    /// in place of `spoiler`.
    enum SpoilerFinish: String, Codable, CaseIterable, Identifiable {
        case gloss, carbon

        var id: String { rawValue }
        var title: String { self == .gloss ? "Gloss Black" : "Carbon Fiber" }
    }

    /// The studio pass to show: `day` is the original, always-rendered set;
    /// `night` swaps in the catalog's `<car>/night2/<color>/` frames (same
    /// crop as day, so the car never jumps on toggle) — the studio dimmed
    /// and cooled, headlights/taillights/signals actually glowing. Only cars
    /// with a night pass rendered offer the choice; everything else (tint,
    /// wheels, extras, seats) still composites from its day-lit layer either
    /// way — those don't have night variants yet.
    enum LightingMode: String, Codable, CaseIterable, Identifiable {
        case day, night

        var id: String { rawValue }
        var title: String { self == .day ? "Day" : "Night" }
    }

    var tint: Tint = .none
    var stance: Stance = .stock
    /// A wheel style id from the render catalog's `wheelStyles`; nil = the
    /// car's own wheels.
    var wheels: String?
    /// The extras shown, in drawing order (never both rack and box).
    private(set) var extras: [Extra] = []
    var seatColor: SeatColor = .standard
    var spoilerFinish: SpoilerFinish = .gloss
    var lightingMode: LightingMode = .day
    /// Blacks out the car's chrome/bright trim — grille surround and rings,
    /// mirror caps, window trim — the catalog's `<car>/blackOptic/` layer
    /// (`CarRenderLibrary.Entry.blackOptic`). Only a car with that layer
    /// rendered offers the toggle; everything else keeps its default chrome.
    var blackOptic: Bool = false

    init(tint: Tint = .none, stance: Stance = .stock, wheels: String? = nil, extras: [Extra] = [],
         seatColor: SeatColor = .standard, spoilerFinish: SpoilerFinish = .gloss, lightingMode: LightingMode = .day,
         blackOptic: Bool = false) {
        self.tint = tint
        self.stance = stance
        self.wheels = wheels
        self.extras = Self.normalized(extras)
        self.seatColor = seatColor
        self.spoilerFinish = spoilerFinish
        self.lightingMode = lightingMode
        self.blackOptic = blackOptic
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

    private enum CodingKeys: String, CodingKey { case tint, stance, wheels, extras, seatColor, spoilerFinish, lightingMode, blackOptic }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tint = (try? c.decodeIfPresent(Tint.self, forKey: .tint)) ?? .none
        stance = (try? c.decodeIfPresent(Stance.self, forKey: .stance)) ?? .stock
        wheels = try? c.decodeIfPresent(String.self, forKey: .wheels)
        // An id this build doesn't know is dropped, not the whole list.
        let ids = (try? c.decodeIfPresent([String].self, forKey: .extras)) ?? []
        extras = Self.normalized(ids.compactMap(Extra.init(rawValue:)))
        seatColor = (try? c.decodeIfPresent(SeatColor.self, forKey: .seatColor)) ?? .standard
        spoilerFinish = (try? c.decodeIfPresent(SpoilerFinish.self, forKey: .spoilerFinish)) ?? .gloss
        lightingMode = (try? c.decodeIfPresent(LightingMode.self, forKey: .lightingMode)) ?? .day
        blackOptic = (try? c.decodeIfPresent(Bool.self, forKey: .blackOptic)) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(tint, forKey: .tint)
        try c.encode(stance, forKey: .stance)
        try c.encodeIfPresent(wheels, forKey: .wheels)
        if !extras.isEmpty { try c.encode(extras, forKey: .extras) }
        if seatColor != .standard { try c.encode(seatColor, forKey: .seatColor) }
        if spoilerFinish != .gloss { try c.encode(spoilerFinish, forKey: .spoilerFinish) }
        if lightingMode != .day { try c.encode(lightingMode, forKey: .lightingMode) }
        if blackOptic { try c.encode(blackOptic, forKey: .blackOptic) }
    }
}
