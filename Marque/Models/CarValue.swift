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
