import Foundation
import UIKit
import FirebaseFunctions

// POC service: ships a driver-license photo to the parseDriverLicense Cloud
// Function, which calls Claude with vision + a JSON-schema constraint and
// returns the extracted fields. The view layer owns the photo picker, loading
// UI, and the confirmation sheet — this struct just handles the round-trip.
struct DocumentScanService {

    struct DriverLicenseResult {
        let number: String
        let state: String
        let expiryDate: Date?
        let modelError: String?
    }

    struct InsuranceCardResult {
        let provider: String
        let policyNumber: String
        let effectiveDate: Date?
        let expiryDate: Date?
        let modelError: String?
    }

    struct MaintenanceReceiptResult {
        let serviceType: String
        let date: Date?
        let mileage: String
        let cost: String
        let shop: String
        let description: String
        let modelError: String?
    }

    // Identifies the kind of document the user was scanning so alert titles
    // and messages can name it correctly ("Couldn't Read Receipt" instead of
    // the pre-existing hard-coded "Couldn't Read License").
    enum DocumentKind: Sendable {
        case driverLicense
        case insuranceCard
        case maintenanceReceipt

        // Lowercase noun for use inside a sentence
        // ("Try a clearer photo with the whole receipt in frame.").
        var noun: String {
            switch self {
            case .driverLicense: return "license"
            case .insuranceCard: return "insurance card"
            case .maintenanceReceipt: return "receipt"
            }
        }

        // Title-cased noun for the alert title ("Couldn't Read Receipt").
        var titleCased: String {
            switch self {
            case .driverLicense: return "License"
            case .insuranceCard: return "Insurance Card"
            case .maintenanceReceipt: return "Receipt"
            }
        }

        // FR-11.4 `document_scan_completed.doc_type`. Kept as a mapping rather
        // than reusing this enum in AnalyticsService so the wire values stay
        // owned by AnalyticsService (renaming a case here can't silently break a
        // saved insight).
        var analyticsType: AnalyticsService.DocumentType {
            switch self {
            case .driverLicense: return .driverLicense
            case .insuranceCard: return .insuranceCard
            case .maintenanceReceipt: return .maintenanceReceipt
            }
        }
    }

    // Categorizes failures so the UI can choose an appropriate title + body
    // and we don't blame the user (or the model) for an infrastructure issue.
    //
    // The two cases that surface document-specific copy — imageEncodingFailed
    // and modelCouldntRead — carry a DocumentKind so all three scan flows
    // (license / insurance / receipt) get correctly-named messages.
    enum ScanError: LocalizedError {
        case imageEncodingFailed(DocumentKind)
        case offline
        case serviceUnavailable(String)
        case authRequired
        case modelCouldntRead(String, DocumentKind)
        case malformedResponse
        case cameraUnsupported
        case unknown(String)

        var errorDescription: String? {
            switch self {
            case .imageEncodingFailed:
                return "Couldn't read that photo. Try a different one."
            case .offline:
                return "No internet connection. Check your network and try again."
            case .serviceUnavailable(let detail):
                return "Scan service isn't available right now. \(detail)"
            case .authRequired:
                return "You need to be signed in to scan documents."
            case .modelCouldntRead(let reason, let kind):
                return reason.isEmpty
                    ? "Couldn't read the \(kind.noun). Try a clearer photo with the whole \(kind.noun) in frame."
                    : reason
            case .malformedResponse:
                return "Got an unexpected response from the scan service."
            case .cameraUnsupported:
                return "Document scanning requires a device with a camera. The simulator can't scan documents — try on a physical device."
            case .unknown(let detail):
                return "Something went wrong while scanning. \(detail)"
            }
        }

        // Title for the alert — neutral when we can't blame the photo.
        var alertTitle: String {
            switch self {
            case .modelCouldntRead(_, let kind), .imageEncodingFailed(let kind):
                return "Couldn't Read \(kind.titleCased)"
            case .offline, .serviceUnavailable, .malformedResponse, .unknown:
                return "Scan Failed"
            case .authRequired:
                return "Sign In Required"
            case .cameraUnsupported:
                return "Camera Unavailable"
            }
        }
    }

    // Maps a Firebase Functions error code to one of our ScanError variants.
    // Reference: FunctionsErrorCode raw values in the Firebase iOS SDK.
    private static func scanError(from error: Error) -> ScanError {
        let ns = error as NSError
        // Network errors come back under NSURLErrorDomain. Firebase wraps some,
        // but the underlying NSURLErrorNotConnectedToInternet still surfaces.
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
            case .notFound,
                 .unavailable,
                 .unimplemented:
                // The function URL didn't resolve — almost always a deploy
                // or region misconfig, NOT a model failure. Tell the truth.
                return .serviceUnavailable(ns.localizedDescription)
            case .deadlineExceeded:
                return .offline
            case .internal,
                 .unknown,
                 .dataLoss,
                 .aborted:
                return .unknown(ns.localizedDescription)
            case .invalidArgument,
                 .failedPrecondition,
                 .outOfRange:
                return .malformedResponse
            default:
                return .unknown(ns.localizedDescription)
            }
        }
        return .unknown(ns.localizedDescription)
    }

    private let functions = Functions.functions()

    private static let isoDateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()

    func scanDriverLicense(image: UIImage) async throws -> DriverLicenseResult {
        let data = try await callParser(name: "parseDriverLicense", image: image, kind: .driverLicense)

        let number = (data["number"] as? String) ?? ""
        let state = (data["state"] as? String) ?? ""
        let expiryString = (data["expiryDate"] as? String) ?? ""
        let modelError = (data["error"] as? String) ?? ""

        let allEmpty = number.isEmpty && state.isEmpty && expiryString.isEmpty
        if !modelError.isEmpty, allEmpty {
            throw ScanError.modelCouldntRead(modelError, .driverLicense)
        }

        // FR-14.5 / FR-11.4: only on a successful extraction. Everything that
        // counts as a failure (encode error, transport error, malformed payload,
        // model read nothing) has already thrown by this point.
        AnalyticsService.documentScanCompleted(docType: DocumentKind.driverLicense.analyticsType)

        return DriverLicenseResult(
            number: number,
            state: state.uppercased(),
            expiryDate: Self.parseISODate(expiryString),
            modelError: modelError.isEmpty ? nil : modelError
        )
    }

    func scanInsuranceCard(image: UIImage) async throws -> InsuranceCardResult {
        let data = try await callParser(name: "parseInsuranceCard", image: image, kind: .insuranceCard)

        let provider = (data["provider"] as? String) ?? ""
        let policyNumber = (data["policyNumber"] as? String) ?? ""
        let effectiveString = (data["effectiveDate"] as? String) ?? ""
        let expiryString = (data["expiryDate"] as? String) ?? ""
        let modelError = (data["error"] as? String) ?? ""

        let allEmpty = provider.isEmpty && policyNumber.isEmpty
            && effectiveString.isEmpty && expiryString.isEmpty
        if !modelError.isEmpty, allEmpty {
            throw ScanError.modelCouldntRead(modelError, .insuranceCard)
        }

        AnalyticsService.documentScanCompleted(docType: DocumentKind.insuranceCard.analyticsType)

        return InsuranceCardResult(
            provider: provider,
            policyNumber: policyNumber,
            effectiveDate: Self.parseISODate(effectiveString),
            expiryDate: Self.parseISODate(expiryString),
            modelError: modelError.isEmpty ? nil : modelError
        )
    }

    func scanMaintenanceReceipt(image: UIImage) async throws -> MaintenanceReceiptResult {
        let data = try await callParser(name: "parseMaintenanceReceipt", image: image, kind: .maintenanceReceipt)

        let serviceType = (data["serviceType"] as? String) ?? ""
        let dateString = (data["date"] as? String) ?? ""
        let mileage = (data["mileage"] as? String) ?? ""
        let cost = (data["cost"] as? String) ?? ""
        let shop = (data["shop"] as? String) ?? ""
        let description = (data["description"] as? String) ?? ""
        let modelError = (data["error"] as? String) ?? ""

        let allEmpty = serviceType.isEmpty && dateString.isEmpty
            && mileage.isEmpty && cost.isEmpty && shop.isEmpty && description.isEmpty
        if !modelError.isEmpty, allEmpty {
            throw ScanError.modelCouldntRead(modelError, .maintenanceReceipt)
        }

        AnalyticsService.documentScanCompleted(docType: DocumentKind.maintenanceReceipt.analyticsType)

        return MaintenanceReceiptResult(
            serviceType: serviceType,
            date: Self.parseISODate(dateString),
            mileage: mileage,
            cost: cost,
            shop: shop,
            description: description,
            modelError: modelError.isEmpty ? nil : modelError
        )
    }

    // MARK: - Shared plumbing

    // Compresses the image to JPEG, base64-encodes it, and calls the named
    // parser Cloud Function. `kind` names the document in the alert title
    // when image encoding fails (the only ScanError this helper throws that
    // carries document-specific copy).
    private func callParser(name: String, image: UIImage, kind: DocumentKind) async throws -> [String: Any] {
        guard let jpeg = image.compressedJPEGData(maxBytes: 1_000_000) else {
            throw ScanError.imageEncodingFailed(kind)
        }

        let payload: [String: Any] = [
            "imageBase64": jpeg.base64EncodedString(),
            "mediaType": "image/jpeg",
        ]

        let result: HTTPSCallableResult
        do {
            result = try await functions.httpsCallable(name).call(payload)
        } catch {
            #if DEBUG
            let ns = error as NSError
            print("[DocumentScanService] \(name) failed — domain=\(ns.domain) code=\(ns.code) msg=\(ns.localizedDescription)")
            #endif
            throw Self.scanError(from: error)
        }

        guard let data = result.data as? [String: Any] else {
            throw ScanError.malformedResponse
        }
        return data
    }

    private static func parseISODate(_ s: String) -> Date? {
        s.isEmpty ? nil : isoDateFormatter.date(from: s)
    }
}

private extension UIImage {
    // Iteratively drops JPEG quality until the encoded payload fits under
    // `maxBytes`. We don't downsample dimensions here — Claude vision handles
    // up to ~2576px on the long edge on Opus 4.7, and the iOS PhotosPicker
    // hands us reasonably sized images.
    func compressedJPEGData(maxBytes: Int) -> Data? {
        var quality: CGFloat = 0.8
        var data = jpegData(compressionQuality: quality)
        while let current = data, current.count > maxBytes, quality > 0.2 {
            quality -= 0.15
            data = jpegData(compressionQuality: quality)
        }
        return data
    }
}
