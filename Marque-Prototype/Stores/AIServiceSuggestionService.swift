import Foundation
import FirebaseFunctions

// Calls the `suggestServiceReminders` Cloud Function and coerces the JSON
// response into `[AIServiceSuggestion]`. Stateless — mirror of the
// DocumentScanService pattern (single struct, single method, typed error).
//
// The caller is responsible for falling back to `ServiceReminderEngine` when
// this throws. Both sources produce the same conceptual shape so the UI can
// swap them transparently.
struct AIServiceSuggestionService {

    private let functions = Functions.functions()

    // Rejects the sheet with a friendly message + tells the UI to fall back
    // to rule-based suggestions. `unknown` carries the raw description for
    // console/debug context.
    enum SuggestionError: LocalizedError {
        case offline
        case unavailable
        case authRequired
        case malformedResponse
        case unknown(String)

        var errorDescription: String? {
            switch self {
            case .offline:
                return "No internet — using built-in suggestions instead."
            case .unavailable:
                return "AI suggestions unavailable right now — using built-in suggestions."
            case .authRequired:
                return "Sign in required."
            case .malformedResponse:
                return "Unexpected response from the suggestion service."
            case .unknown(let detail):
                return detail.isEmpty ? "Something went wrong." : detail
            }
        }
    }

    private static let isoDateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()

    private static let clientDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone.current
        return df
    }()

    func suggest(for car: Car) async throws -> [AIServiceSuggestion] {
        let carPayload: [String: Any] = [
            "make": car.make,
            "model": car.model,
            "year": car.year,
            "trim": car.trim,
            "mileage": car.mileage,
            "fuelType": car.fuelType,
            "transmission": car.transmission,
            "driveType": car.driveType,
            "engine": car.engine,
            "bodyStyle": car.bodyStyle,
        ]

        // Last 24 months of maintenance — enough context for the model to see
        // recurring service cadence without blowing input tokens for cars with
        // very long histories.
        let cutoff = Calendar.current.date(byAdding: .month, value: -24, to: Date()) ?? Date()
        let historyPayload: [[String: Any]] = car.maintenanceRecords
            .filter { $0.date >= cutoff }
            .sorted { $0.date > $1.date }
            .map { record in
                var dict: [String: Any] = [
                    "serviceType": record.serviceType,
                    "date": Self.isoDateFormatter.string(from: record.date),
                ]
                if !record.mileage.isEmpty { dict["mileage"] = record.mileage }
                return dict
            }

        let activePayload: [[String: Any]] = car.serviceReminders
            .filter { !$0.isCompleted }
            .map { reminder in
                var dict: [String: Any] = ["serviceType": reminder.serviceType]
                if let dueDate = reminder.dueDate {
                    dict["dueDate"] = Self.isoDateFormatter.string(from: dueDate)
                }
                if let dueMileage = reminder.dueMileage {
                    dict["dueMileage"] = dueMileage
                }
                return dict
            }

        let payload: [String: Any] = [
            "car": carPayload,
            "maintenanceHistory": historyPayload,
            "activeReminders": activePayload,
            "clientDate": Self.clientDateFormatter.string(from: Date()),
        ]

        let result: HTTPSCallableResult
        do {
            result = try await functions.httpsCallable("suggestServiceReminders").call(payload)
        } catch {
            #if DEBUG
            let ns = error as NSError
            print("[AIServiceSuggestionService] suggestServiceReminders failed — domain=\(ns.domain) code=\(ns.code) msg=\(ns.localizedDescription)")
            #endif
            throw Self.translate(error)
        }

        guard let data = result.data as? [String: Any],
              let items = data["suggestions"] as? [[String: Any]] else {
            throw SuggestionError.malformedResponse
        }

        return items.compactMap { item in
            guard let serviceType = item["serviceType"] as? String, !serviceType.isEmpty,
                  let reasoning = item["reasoning"] as? String,
                  let priorityRaw = item["priority"] as? String,
                  let priority = AIServiceSuggestion.Priority(rawValue: priorityRaw)
            else { return nil }

            let dueDateString = (item["dueDate"] as? String) ?? ""
            let dueDate = dueDateString.isEmpty ? nil : Self.isoDateFormatter.date(from: dueDateString)
            let dueMileage = item["dueMileage"] as? Int

            return AIServiceSuggestion(
                serviceType: serviceType,
                dueDate: dueDate,
                dueMileage: dueMileage,
                reasoning: reasoning,
                priority: priority
            )
        }
    }

    private static func translate(_ error: Error) -> SuggestionError {
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
            case .deadlineExceeded:
                return .offline
            case .notFound, .unavailable, .unimplemented:
                return .unavailable
            case .invalidArgument, .failedPrecondition, .outOfRange:
                return .malformedResponse
            default:
                return .unknown(ns.localizedDescription)
            }
        }
        return .unknown(ns.localizedDescription)
    }
}
