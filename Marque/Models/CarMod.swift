import Foundation

/// What kind of modification `CarMod.name` describes. A String raw value enum
/// (Firestore-friendly), with a display name and SF Symbol per case for the
/// frontend's picker/list UI.
///
/// Tolerant decoding: an unknown raw value (e.g. written by a future app
/// version with a new category) decodes as `.other` rather than failing the
/// whole car's decode.
enum ModCategory: String, CaseIterable, Codable, Identifiable {
    case engineTune
    case intake
    case exhaust
    case forcedInduction
    case fuel
    case suspension
    case brakes
    case wheels
    case tires
    case aeroBodyKit
    case wrapPaint
    case lighting
    case interior
    case audioTech
    case drivetrain
    case other

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = ModCategory(rawValue: raw) ?? .other
    }
    // No custom encode(to:): the compiler synthesizes it from rawValue, same
    // as CarValueSource. Only init(from:) needs the fallback.

    var displayName: String {
        switch self {
        case .engineTune: return "Engine / Tune"
        case .intake: return "Intake"
        case .exhaust: return "Exhaust"
        case .forcedInduction: return "Forced Induction"
        case .fuel: return "Fuel"
        case .suspension: return "Suspension"
        case .brakes: return "Brakes"
        case .wheels: return "Wheels"
        case .tires: return "Tires"
        case .aeroBodyKit: return "Aero / Body Kit"
        case .wrapPaint: return "Wrap / Paint"
        case .lighting: return "Lighting"
        case .interior: return "Interior"
        case .audioTech: return "Audio / Tech"
        case .drivetrain: return "Drivetrain"
        case .other: return "Other"
        }
    }

    /// SF Symbol suggestion for the frontend's category picker/list. Purely
    /// cosmetic — an invalid name here would render as a blank glyph, never a
    /// build or runtime failure, so double-check against the SF Symbols app
    /// rather than treating these as verified.
    var symbolName: String {
        switch self {
        case .engineTune: return "gauge"
        case .intake: return "wind"
        case .exhaust: return "flame.fill"
        case .forcedInduction: return "arrow.triangle.2.circlepath"
        case .fuel: return "fuelpump.fill"
        case .suspension: return "arrow.up.and.down"
        case .brakes: return "octagon.fill"
        case .wheels: return "circle.circle.fill"
        case .tires: return "smallcircle.filled.circle.fill"
        case .aeroBodyKit: return "airplane"
        case .wrapPaint: return "paintbrush.fill"
        case .lighting: return "lightbulb.fill"
        case .interior: return "car.side"
        case .audioTech: return "hifispeaker.fill"
        case .drivetrain: return "gearshape.2.fill"
        case .other: return "ellipsis.circle.fill"
        }
    }
}

/// A single modification on a car (exhaust, wheels, tune, ...). Lives inside
/// `Car.mods` (not normalized, same as MaintenanceRecord/ServiceReminder).
/// `notes` is private only — PublicCarMod never carries it.
struct CarMod: Identifiable, Codable, Equatable {
    var id: UUID
    var category: ModCategory
    /// Required. E.g. "Akrapovič Evolution exhaust".
    var name: String
    var brand: String?
    var installedAt: Date?
    /// Private only — never included in PublicCarMod.
    var notes: String?

    static let maxNameLength = 60
    static let maxBrandLength = 40
    static let maxNotesLength = 300

    init(
        id: UUID = UUID(),
        category: ModCategory = .other,
        name: String = "",
        brand: String? = nil,
        installedAt: Date? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.category = category
        self.name = name
        self.brand = brand
        self.installedAt = installedAt
        self.notes = notes
    }

    private enum CodingKeys: String, CodingKey {
        case id, category, name, brand, installedAt, notes
    }

    // Tolerant of older/partial docs: a missing id gets a fresh one, a
    // missing/malformed category falls back to .other (ModCategory's own
    // init already handles an unknown-but-present raw value).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        category = (try? c.decode(ModCategory.self, forKey: .category)) ?? .other
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        brand = try c.decodeIfPresent(String.self, forKey: .brand)
        installedAt = try c.decodeIfPresent(Date.self, forKey: .installedAt)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
    }
    // No custom encode(to:): synthesized from the stored properties above,
    // matching CodingKeys 1:1 (same pattern as PublicServiceRecord).

    /// A copy with `name`/`brand`/`notes` trimmed and clamped to their length
    /// caps, and an empty `brand`/`notes` normalized to nil. CarStore calls
    /// this before every write so a pasted oversized value can't bloat the
    /// car doc (or, for name/brand, the public projection).
    func clamped() -> CarMod {
        var copy = self
        copy.name = String(
            name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(CarMod.maxNameLength)
        )
        copy.brand = Self.clampedNonEmpty(brand, to: CarMod.maxBrandLength)
        copy.notes = Self.clampedNonEmpty(notes, to: CarMod.maxNotesLength)
        return copy
    }

    private static func clampedNonEmpty(_ s: String?, to limit: Int) -> String? {
        guard let trimmed = s?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return String(trimmed.prefix(limit))
    }
}
