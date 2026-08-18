import Foundation
import FirebaseRemoteConfig

// Reads Firebase Remote Config on launch and exposes each flag as an
// @Published property so SwiftUI views can gate on them reactively.
//
// Default values live here (not just server-side) so first launch — before the
// initial fetch completes — still gets deterministic behavior. Per FR-10.22
// the assistant defaults to OFF until an ops-set condition in the Firebase
// Console flips it (TestFlight cohort first, then a percentage rollout, then
// 100%).
@MainActor
class FeatureFlagsStore: ObservableObject {

    @Published private(set) var assistantEnabled: Bool = false

    private let config: RemoteConfig

    private enum Key: String {
        case assistantEnabled = "marque_assistant_enabled"
    }

    init() {
        config = RemoteConfig.remoteConfig()

        let settings = RemoteConfigSettings()
        // In debug, fetch every launch so we can flip flags in the Console
        // and see the change immediately on the next cold start.
        // In release the default cache TTL (12h) applies — trade of freshness
        // for fewer server calls, which is what we want in production.
        #if DEBUG
        settings.minimumFetchInterval = 0
        #endif
        config.configSettings = settings

        // Defaults get applied synchronously; the server fetch runs async.
        // Setting keys explicitly (rather than relying on a plist) keeps the
        // defaults visible in code alongside the property that reads them.
        config.setDefaults([
            Key.assistantEnabled.rawValue: NSNumber(value: false),
        ])
        applyValues()

        Task { await refresh() }
    }

    // Fetches the latest values from Firebase Remote Config and re-applies
    // them to the published properties. Called once on init; can be called
    // again from a manual "check for updates" affordance if we ever add one.
    func refresh() async {
        do {
            _ = try await config.fetchAndActivate()
            applyValues()
        } catch {
            // Silent — cached / default values remain in effect. Remote Config
            // fetches will retry on subsequent app launches.
        }
    }

    private func applyValues() {
        assistantEnabled = config[Key.assistantEnabled.rawValue].boolValue
    }
}
