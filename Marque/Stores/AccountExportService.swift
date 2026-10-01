import Foundation
import FirebaseAuth
import FirebaseFunctions

// FR-15.7 / GDPR Art. 20 — the "give me everything you have on me" export,
// separate from the FR-15.1-15.6 PDF/CSV service-history report. Calls the
// `exportAccountData` Cloud Function (which gathers everything the server
// holds via the Admin SDK, including paths firestore.rules deny the client),
// merges in the UserDefaults-only driver-license fields the server can never
// see (FR-09.4), and writes the result to a temp file for the share sheet.
//
// Stateless, single-method struct-of-statics — mirror of the
// AIServiceSuggestionService / DocumentScanService pattern.
enum AccountExportService {
    enum ExportError: LocalizedError {
        case limitReached
        case tooLarge
        case notSignedIn
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .limitReached:
                return "You've reached today's export limit. Try again tomorrow."
            case .tooLarge:
                return "Your account data is too large to export right now. Contact support for help."
            case .notSignedIn:
                return "Sign in to export your account data."
            case .failed(let detail):
                return detail.isEmpty ? "Couldn't export your account data. Try again." : detail
            }
        }
    }

    // Local-timezone, not ISO8601DateFormatter's UTC default — this is only
    // ever used to name a file for today's date as the device sees it.
    private static let filenameDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = .current
        return df
    }()

    /// Calls `exportAccountData`, merges in the device-only data the server
    /// can't see, writes pretty-printed JSON to a temp file, and returns its
    /// URL for the share sheet.
    @MainActor
    static func exportAccountData() async throws -> URL {
        guard let user = Auth.auth().currentUser else {
            throw ExportError.notSignedIn
        }
        let uid = user.uid

        let result: HTTPSCallableResult
        do {
            result = try await Functions.functions().httpsCallable("exportAccountData").call()
        } catch {
            throw Self.translate(error)
        }

        guard var payload = result.data as? [String: Any] else {
            throw ExportError.failed("Unexpected response from the export service.")
        }

        // Merged locally: the server has no way to see UserDefaults-only
        // fields, so this can't be part of the callable's response.
        payload["deviceOnly"] = AuthService.deviceOnlyExportFields(uid: uid)

        let jsonData: Data
        do {
            jsonData = try JSONSerialization.data(
                withJSONObject: payload,
                options: [.prettyPrinted, .sortedKeys]
            )
        } catch {
            throw ExportError.failed("Couldn't format your export file.")
        }

        let filename = "Marque-account-data-\(filenameDateFormatter.string(from: Date())).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try jsonData.write(to: url, options: .atomic)
        } catch {
            throw ExportError.failed("Couldn't save your export file.")
        }
        return url
    }

    private static func translate(_ error: Error) -> ExportError {
        let ns = error as NSError
        if ns.domain == FunctionsErrorDomain, let code = FunctionsErrorCode(rawValue: ns.code) {
            switch code {
            case .unauthenticated:
                return .notSignedIn
            case .resourceExhausted:
                return .limitReached
            case .failedPrecondition:
                return .tooLarge
            default:
                return .failed(ns.localizedDescription)
            }
        }
        return .failed(ns.localizedDescription)
    }
}
