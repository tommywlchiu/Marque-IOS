import Foundation
import SwiftUI
import UIKit
import SmartcarAuth
import FirebaseFunctions

/// Manages Smartcar Connect — OAuth-based linking of users' cars (Tesla, Ford,
/// BMW, etc.) so we can read live odometer values without manual entry.
///
/// **Phase 2 (current):** OAuth flow is wired up. The user can launch
/// Smartcar Connect, authenticate, and the SDK returns an auth code via the
/// `marque://smartcar-callback` redirect. The code is then handed to the
/// Phase 3 Cloud Function for token exchange.
///
/// **Phase 3 will fill** `finalizeConnection`, `sync`, and `disconnect` with
/// real Cloud Function calls.
@MainActor
final class SmartcarStore: ObservableObject {

    enum ConnectionState: Equatable {
        case idle
        case launching        // Smartcar Connect sheet about to appear
        case authenticating   // user is on Smartcar's hosted page
        case finalizing       // exchanging code → tokens server-side
        case error(String)
    }

    @Published private(set) var state: ConnectionState = .idle
    @Published private(set) var syncingCarIds: Set<UUID> = []

    // MARK: - Feature flag

    // Set to true once the Smartcar integration is fully debugged and ready.
    static let isEnabled = false

    // MARK: - Configuration

    // Smartcar Application ID — public by design, embedded in the client.
    // Test-mode application; switch the `mode:` parameter to `.live` for
    // production once Smartcar has approved your live application.
    private static let applicationId = "f82de192-8c8b-4193-adae-325cab5beffd"
    private static let redirectUri = "marque://smartcar-callback"

    // Permissions we request from the user. `read_vehicle_info` for make/model/year,
    // `read_vin` to match Smartcar vehicles to existing Marque cars by VIN, and
    // `read_odometer` for live mileage. Marking each `required` ensures Smartcar
    // won't return a partially-authorised connection.
    private static let scope = ["read_vehicle_info", "read_odometer", "read_vin"]

    // MARK: - Cloud Functions

    private let functions = Functions.functions()

    // MARK: - SDK

    private lazy var auth: SmartcarAuth = {
        SmartcarAuth(
            applicationId: Self.applicationId,
            redirectUri: Self.redirectUri,
            scope: Self.scope,
            completionHandler: { [weak self] code, oauthState, _, _, error in
                Task { @MainActor in
                    self?.handleAuthResult(code: code, oauthState: oauthState, error: error)
                }
            },
            mode: .simulated
        )
    }()

    // Tracks which Marque car the user is trying to link, so when the code
    // comes back we know which Car to update. Also acts as a CSRF guard: the
    // `state` query parameter on the redirect must match this token.
    private var pendingConnection: PendingConnection?

    private struct PendingConnection {
        let carId: UUID
        let vinHint: String
        let stateToken: String
    }

    // MARK: - Brand support

    // Subset of Smartcar's supported brands. Lowercased makes — match against
    // car.make to decide whether to show the "Connect" affordance.
    private static let supportedMakes: Set<String> = [
        "acura", "alfa romeo", "audi", "bmw", "buick", "cadillac",
        "chevrolet", "chrysler", "dodge", "fiat", "ford", "gmc",
        "honda", "hyundai", "infiniti", "jaguar", "jeep", "kia",
        "land rover", "lexus", "lincoln", "lucid", "mazda",
        "mercedes-benz", "mini", "mitsubishi", "nissan", "polestar",
        "porsche", "ram", "rivian", "subaru", "tesla", "toyota",
        "volkswagen", "volvo"
    ]

    static func isSupported(make: String) -> Bool {
        supportedMakes.contains(
            make.lowercased().trimmingCharacters(in: .whitespaces)
        )
    }

    // Display-cased version of the make for UI copy ("your Tesla", "your BMW").
    static func displayBrand(for make: String) -> String {
        let trimmed = make.trimmingCharacters(in: .whitespaces)
        let allCaps: Set<String> = ["bmw", "gmc", "ram"]
        if allCaps.contains(trimmed.lowercased()) {
            return trimmed.uppercased()
        }
        return trimmed.capitalized
    }

    // MARK: - Connect flow

    /// Launches Smartcar Connect for the given Marque car. When the user
    /// finishes (or cancels), `handleAuthResult` is called via the SDK's
    /// completion handler.
    func startConnection(for car: Car) {
        guard let presenter = topViewController() else {
            state = .error("Couldn't find a view controller to present from.")
            return
        }

        state = .launching

        // A fresh random state token per attempt — also serves as our CSRF
        // check when the redirect comes back.
        let stateToken = UUID().uuidString
        pendingConnection = PendingConnection(
            carId: car.id,
            vinHint: car.vinNumber.trimmingCharacters(in: .whitespaces),
            stateToken: stateToken
        )

        // Hint Smartcar which brand to skip the chooser for. If the make
        // isn't supported, fall through to the brand picker.
        let normalizedMake = car.make.lowercased().trimmingCharacters(in: .whitespaces)
        let bypassMake = Self.supportedMakes.contains(normalizedMake) ? normalizedMake : nil

        var urlBuilder = SCUrlBuilder(
            applicationId: Self.applicationId,
            redirectUri: Self.redirectUri,
            scope: Self.scope,
            mode: .simulated
        )
        .setState(state: stateToken)
        .setSingleSelect(singleSelect: true)

        if let bypassMake {
            urlBuilder = urlBuilder.setMakeBypass(make: bypassMake)
        }

        let url = urlBuilder.build()
        auth.launchAuthFlow(url: url, viewController: presenter)
        state = .authenticating
    }

    /// Called from `Marque_PrototypeApp.onOpenURL` when the user is redirected
    /// back to the app after completing Smartcar Connect. Returns true if the
    /// URL was a Smartcar callback we recognised (so the app knows to consume it).
    func handleCallback(_ url: URL) -> Bool {
        guard url.scheme == "marque", url.host == "smartcar-callback" else {
            return false
        }
        auth.handleCallback(callbackUrl: url)
        return true
    }

    private func handleAuthResult(code: String?, oauthState: String?, error: AuthorizationError?) {
        print("[Smartcar] handleAuthResult — code: \(code?.prefix(8).description ?? "nil"), state: \(oauthState?.prefix(8).description ?? "nil"), error: \(error.map { String(describing: $0.type) } ?? "none"), pendingSet: \(pendingConnection != nil)")

        if let error {
            if error.type == .userExitedFlow {
                print("[Smartcar] User exited flow — returning to idle")
                state = .idle
                pendingConnection = nil
                return
            }
            print("[Smartcar] Auth error: \(error.type) — \(error.errorDescription ?? "")")
            state = .error(friendlyMessage(for: error))
            pendingConnection = nil
            return
        }

        guard let code, let pending = pendingConnection else {
            print("[Smartcar] Guard failed — code nil: \(code == nil), pendingConnection nil: \(pendingConnection == nil)")
            state = .error("No authorization code was returned.")
            pendingConnection = nil
            return
        }

        guard oauthState == pending.stateToken else {
            print("[Smartcar] CSRF mismatch — got: \(oauthState ?? "nil"), expected: \(pending.stateToken.prefix(8))")
            state = .error("Authorization state mismatch — please try again.")
            pendingConnection = nil
            return
        }

        print("[Smartcar] Auth successful — calling finalizeConnection")
        state = .finalizing
        let pendingCopy = pending
        pendingConnection = nil
        Task { await finalizeConnection(code: code, pending: pendingCopy) }
    }

    /// Calls the smartcarExchangeCode Cloud Function. The function does the
    /// token exchange, picks the best vehicle match, persists the connection
    /// server-side, and writes the connection metadata + initial mileage to
    /// the Car document — which the iOS Firestore listener picks up
    /// automatically and reflects in the UI.
    private func finalizeConnection(code: String, pending: PendingConnection) async {
        let callable = functions.httpsCallable("smartcarExchangeCode")
        do {
            _ = try await callable.call([
                "code": code,
                "carId": pending.carId.uuidString,
                "redirectUri": Self.redirectUri,
                "vinHint": pending.vinHint
            ])
            state = .idle
        } catch {
            state = .error(callableErrorMessage(error))
        }
    }

    // MARK: - Sync / Disconnect

    func sync(_ car: Car) async {
        guard let vehicleId = car.smartcarVehicleId else { return }
        syncingCarIds.insert(car.id)
        defer { syncingCarIds.remove(car.id) }

        let callable = functions.httpsCallable("smartcarReadOdometer")
        do {
            _ = try await callable.call(["vehicleId": vehicleId])
            // Car document update happens server-side; listener updates the UI.
        } catch {
            state = .error(callableErrorMessage(error))
        }
    }

    func disconnect(_ car: Car) async {
        guard let vehicleId = car.smartcarVehicleId else { return }
        let callable = functions.httpsCallable("smartcarDisconnect")
        do {
            _ = try await callable.call(["vehicleId": vehicleId])
        } catch {
            state = .error(callableErrorMessage(error))
        }
    }

    // Maps Firebase Functions errors to friendly user-facing copy.
    private func callableErrorMessage(_ error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == FunctionsErrorDomain {
            if let message = nsError.userInfo[FunctionsErrorDetailsKey] as? String, !message.isEmpty {
                return message
            }
            return nsError.localizedDescription
        }
        return nsError.localizedDescription
    }

    // MARK: - Helpers

    func isSyncing(_ car: Car) -> Bool {
        syncingCarIds.contains(car.id)
    }

    func clearError() {
        if case .error = state { state = .idle }
    }

    // Find the topmost presented view controller to launch the SDK from.
    // Smartcar uses SFSafariViewController, which requires a presenter.
    private func topViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let window = scene.windows.first(where: { $0.isKeyWindow }) else {
            return nil
        }
        var top = window.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }

    private func friendlyMessage(for error: AuthorizationError) -> String {
        switch error.type {
        case .accessDenied:
            return "You denied access. To connect, tap Allow on the Smartcar screen."
        case .vehicleIncompatible:
            return "This vehicle isn't compatible with Smartcar yet."
        case .noVehicles:
            return "No vehicles were found in this account."
        case .invalidSubscription:
            return "Your Smartcar subscription doesn't include this vehicle."
        case .configurationError:
            return "Smartcar is misconfigured — check the redirect URI and client ID."
        case .serverError:
            return "Smartcar's servers are having trouble. Try again in a moment."
        case .missingAuthCode, .missingQueryParameters:
            return "Connection didn't complete. Please try again."
        case .userExitedFlow:
            return ""        // handled silently in handleAuthResult
        case .unknownError:
            return error.errorDescription ?? "Something went wrong. Please try again."
        @unknown default:
            return error.errorDescription ?? "Something went wrong. Please try again."
        }
    }
}
