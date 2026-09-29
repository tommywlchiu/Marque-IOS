import Foundation
import FirebaseFunctions

// Calls the `estimateCarValue` Cloud Function. Stateless, the same shape as
// AIServiceSuggestionService (single struct, single method, typed error).
// Reached through CarStore.estimateValue(for:condition:region:).
//
// Sends only year/make/model/trim/mileage/condition/region. Never the VIN,
// plate, notes, insurance or photos; the server ignores anything else anyway.
struct CarValueService {

    private let functions = Functions.functions()

    enum ValueError: LocalizedError, Equatable {
        case offline
        case unavailable
        case authRequired
        case emailNotVerified
        case dailyLimit
        /// The car's year/make/model is missing or invalid, or the model
        /// couldn't produce an estimate for it. Not charged against the allowance.
        case cannotEstimate
        case malformedResponse
        case unknown(String)

        var errorDescription: String? {
            switch self {
            case .offline:
                return "No internet connection. Try again when you're back online."
            case .unavailable:
                return "Value estimates are unavailable right now. Try again later."
            case .authRequired:
                return "Sign in required."
            case .emailNotVerified:
                return "Verify your email address to use value estimates."
            case .dailyLimit:
                return "You've reached today's limit of value estimates. Try again tomorrow."
            case .cannotEstimate:
                return "Couldn't estimate a value for this car. Check the year, make and model."
            case .malformedResponse:
                return "Unexpected response from the estimate service."
            case .unknown(let detail):
                return detail.isEmpty ? "Something went wrong." : detail
            }
        }
    }

    // The server bounds this to ±1 day of its UTC date; it's the key of the
    // daily counter (usage/valuations_{clientDate}). Local calendar, not UTC.
    private static let clientDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone.current
        return df
    }()

    func estimate(for car: Car, condition: ValueCondition, region: String? = nil) async throws -> ValueEstimate {
        var payload: [String: Any] = [
            "year": car.year,
            "make": car.make,
            "model": car.model,
            "condition": condition.rawValue,
            "clientDate": Self.clientDateFormatter.string(from: Date()),
        ]
        if !car.trim.isEmpty { payload["trim"] = car.trim }
        if let miles = car.mileageValue { payload["mileage"] = miles }
        if let region = region?.trimmingCharacters(in: .whitespacesAndNewlines), !region.isEmpty {
            payload["region"] = region
        }

        let result: HTTPSCallableResult
        do {
            result = try await functions.httpsCallable("estimateCarValue").call(payload)
        } catch {
            #if DEBUG
            let ns = error as NSError
            print("[CarValueService] estimateCarValue failed — domain=\(ns.domain) code=\(ns.code) msg=\(ns.localizedDescription)")
            #endif
            throw Self.translate(error)
        }

        guard let data = result.data as? [String: Any],
              let low = (data["low"] as? NSNumber)?.doubleValue,
              let mid = (data["mid"] as? NSNumber)?.doubleValue,
              let high = (data["high"] as? NSNumber)?.doubleValue,
              low > 0, low <= mid, mid <= high
        else {
            throw ValueError.malformedResponse
        }
        let confidence = (data["confidence"] as? String).flatMap(ValueEstimate.Confidence.init(rawValue:)) ?? .low
        let allowance = data["valuationAllowance"] as? [String: Any]
        return ValueEstimate(
            low: low,
            mid: mid,
            high: high,
            rationale: (data["rationale"] as? String) ?? "",
            confidence: confidence,
            estimatesUsedToday: (allowance?["used"] as? NSNumber)?.intValue ?? 0,
            dailyLimit: (allowance?["limit"] as? NSNumber)?.intValue ?? 10
        )
    }

    private static func translate(_ error: Error) -> ValueError {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorNotConnectedToInternet,
                 NSURLErrorNetworkConnectionLost,
                 NSURLErrorTimedOut:
                return .offline
            default:
                return .unknown(ns.localizedDescription)
            }
        }
        if ns.domain == FunctionsErrorDomain,
           let code = FunctionsErrorCode(rawValue: ns.code) {
            switch code {
            case .unauthenticated:
                return .authRequired
            case .permissionDenied:
                return .emailNotVerified
            case .resourceExhausted:
                return .dailyLimit
            case .deadlineExceeded:
                return .offline
            case .notFound, .unavailable, .unimplemented, .internal:
                return .unavailable
            case .failedPrecondition:
                return .cannotEstimate
            case .invalidArgument, .outOfRange:
                // The server's own message: a missing year/make/model, or
                // "Your device's date looks wrong…".
                return .unknown(ns.localizedDescription)
            default:
                return .unknown(ns.localizedDescription)
            }
        }
        return .unknown(ns.localizedDescription)
    }
}
