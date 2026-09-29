import Foundation

/// Where `Car.estimatedValue` came from.
enum CarValueSource: String, Codable, CaseIterable {
    /// Typed in by the owner (including an AI estimate the owner then edited).
    case owner
    /// An AI estimate the owner accepted as-is.
    case ai
}

/// Condition the owner picks before tapping "Estimate". Raw values are the
/// exact strings the `estimateCarValue` callable accepts.
enum ValueCondition: String, CaseIterable, Identifiable, Codable {
    case excellent, good, fair, poor

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .excellent: return "Excellent"
        case .good: return "Good"
        case .fair: return "Fair"
        case .poor: return "Poor"
        }
    }
}

/// The result of `CarStore.estimateValue(for:condition:region:)`. All amounts
/// are whole US dollars, low <= mid <= high. It's an estimate, not an appraisal.
struct ValueEstimate: Equatable {
    enum Confidence: String, Codable {
        case low, medium, high
    }

    let low: Double
    let mid: Double
    let high: Double
    /// One sentence, at most 200 characters.
    let rationale: String
    let confidence: Confidence
    /// Today's usage of the per-user daily allowance (10/day for everyone).
    let estimatesUsedToday: Int
    let dailyLimit: Int
}

/// Rounds an exact value into the coarse public range shown on Explore.
/// Pure and deterministic, so it's easy to unit-test. The exact value is never
/// published.
///
/// Bucket width scales with price:
///   under $20k        -> $1k buckets   ($12,400  -> "$12k–$13k")
///   $20k to $100k     -> $5k buckets   ($31,250  -> "$30k–$35k")
///   $100k to $250k    -> $10k buckets  ($187,000 -> "$180k–$190k")
///   $250k and up      -> $25k buckets  ($1,010,000 -> "$1M–$1.025M")
/// Under $1,000 -> "Under $1k". Non-finite, zero or negative -> nil.
/// The output always matches the `valueRange` pattern in firestore.rules.
enum CarValueRange {
    static func publicLabel(for value: Double) -> String? {
        guard value.isFinite, value > 0 else { return nil }
        let step = bucketSize(for: value)
        let low = (value / step).rounded(.down) * step
        if low == 0 { return "Under $1k" }
        return "\(format(low))–\(format(low + step))"
    }

    static func bucketSize(for value: Double) -> Double {
        switch value {
        case ..<20_000: return 1_000
        case ..<100_000: return 5_000
        case ..<250_000: return 10_000
        default: return 25_000
        }
    }

    /// "$30k", "$975k", "$1M", "$1.025M".
    static func format(_ amount: Double) -> String {
        if amount >= 1_000_000 {
            var s = String(format: "%.3f", amount / 1_000_000)
            while s.hasSuffix("0") { s.removeLast() }
            if s.hasSuffix(".") { s.removeLast() }
            return "$\(s)M"
        }
        return "$\(Int((amount / 1_000).rounded()))k"
    }
}

/// The car's last AI valuation, saved server-only by `estimateCarValue` at
/// `users/{uid}/usage/valuation_{carId}` (owner-readable, never
/// client-writable). It's the ONLY source of the public value range (owner
/// decision): the server sets `publicCars/{carId}.valueRange` to
/// `CarValueRange.publicLabel(for: mid)` while the car is public, "Show on
/// public profile" (`Car.showValuePublicly`) is on, and `applies(to:)` holds.
/// A value the owner typed never appears publicly.
struct CarValuation: Equatable {
    struct Snapshot: Equatable {
        var year: String
        var make: String
        var model: String
        var trim: String
        var mileage: String
    }

    let carId: String
    let low: Double
    let mid: Double
    let high: Double
    let confidence: ValueEstimate.Confidence
    let condition: ValueCondition?
    /// The car as it was recorded when estimated (read server-side).
    let carSnapshot: Snapshot
    let createdAt: Date?

    /// Mirrors VALUATION_MAX_AGE_MS / VALUATION_MAX_MILEAGE_DRIFT in
    /// functions/src/valueRange.ts. Change both together.
    static let maxAge: TimeInterval = 365 * 24 * 60 * 60
    static let maxMileageDrift = 20_000

    /// The public range this valuation produces.
    var publicLabel: String? { CarValueRange.publicLabel(for: mid) }

    /// Mirrors `valuationStillApplies` on the server: the same year, make,
    /// model and trim (case/whitespace-insensitive), not driven more than
    /// `maxMileageDrift` miles since, and under `maxAge` old. When this turns
    /// false (e.g. the owner edits the model), the server removes the public
    /// range until the car is estimated again.
    func applies(to car: Car, now: Date = Date()) -> Bool {
        func norm(_ s: String) -> String {
            s.trimmingCharacters(in: .whitespacesAndNewlines)
                .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
                .lowercased()
        }
        guard norm(carSnapshot.year) == norm(car.year),
              norm(carSnapshot.make) == norm(car.make),
              norm(carSnapshot.model) == norm(car.model),
              norm(carSnapshot.trim) == norm(car.trim)
        else { return false }
        if let then = Self.parseMileage(carSnapshot.mileage), let current = Self.parseMileage(car.mileage),
           current - then > Self.maxMileageDrift {
            return false
        }
        guard let createdAt, now.timeIntervalSince(createdAt) <= Self.maxAge else { return false }
        return true
    }

    static func parseMileage(_ s: String) -> Int? {
        let digits = s.filter { $0 != "," && !$0.isWhitespace }
        guard (1...9).contains(digits.count), digits.allSatisfy(\.isASCII), digits.allSatisfy(\.isNumber) else { return nil }
        return Int(digits)
    }

    /// Decodes a `valuation_{carId}` usage doc; nil if it isn't one.
    init?(firestoreData d: [String: Any], createdAt: Date?) {
        guard d["kind"] as? String == "valuation",
              let carId = d["carId"] as? String,
              let low = (d["low"] as? NSNumber)?.doubleValue,
              let mid = (d["mid"] as? NSNumber)?.doubleValue,
              let high = (d["high"] as? NSNumber)?.doubleValue
        else { return nil }
        let snap = d["carSnapshot"] as? [String: Any] ?? [:]
        func str(_ k: String) -> String { snap[k] as? String ?? "" }
        self.carId = carId
        self.low = low
        self.mid = mid
        self.high = high
        self.confidence = (d["confidence"] as? String).flatMap(ValueEstimate.Confidence.init(rawValue:)) ?? .low
        self.condition = (d["condition"] as? String).flatMap(ValueCondition.init(rawValue:))
        self.carSnapshot = Snapshot(year: str("year"), make: str("make"), model: str("model"), trim: str("trim"), mileage: str("mileage"))
        self.createdAt = createdAt
    }
}
