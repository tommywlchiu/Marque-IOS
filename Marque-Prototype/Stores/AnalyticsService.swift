//
//  AnalyticsService.swift
//  Marque-Prototype
//
//  FR-11: Analytics & Instrumentation. PostHog-backed product analytics.
//
//  Follows the NotificationManager pattern: a struct of static functions, no
//  ObservableObject and no environment injection. Analytics is fire-and-forget
//  and holds no observable state.
//
//  Design: one typed `static func` per event in FR-11.4 rather than a general
//  purpose `capture(name:properties:)`. The generic capture is private, which:
//    - enforces the FR-11.2 naming convention (snake_case, object_verb past
//      tense) in exactly one place, so it cannot drift at a call site
//    - makes FR-11.6 (no PII) structural — a caller physically cannot pass a
//      VIN, plate, policy number, email, note, or Assistant message body
//      because the signatures only accept enums, Bools, and counts
//    - removes the possibility of a typo silently splitting one event in two
//

import Foundation
import PostHog

struct AnalyticsService {

    // MARK: - Credentials

    // A PostHog *project* API key is a publishable client-side key: it can write
    // events but cannot read data. It is not a secret and is safe to commit.
    private static let projectToken = "phc_CNdbuZqwqVCe7sZ44AYW7wmFiRLewZsEVbKnD7x4nx52"
    private static let host = "https://us.i.posthog.com"

    // MARK: - Lifecycle

    /// Initializes the PostHog SDK. Call once, as early as possible in app startup.
    /// Calling it again is a no-op inside the SDK.
    static func configure() {
        let config = PostHogConfig(projectToken: projectToken, host: host)

        // --- FR-11.7: first-party product analytics only, no cross-app tracking ---
        //
        // The SDK has no IDFA / advertising-identifier code path at all: PostHog
        // removed `enableAdvertisingCapturing` and `adSupportBlock` and shifted
        // IDFA collection to the client (it would have to be passed in as
        // `$device_advertisingId`). There is therefore no flag to disable — the
        // guarantee is that this file never links AdSupport or
        // AppTrackingTransparency and never sets that property. Keeping it that
        // way is what keeps Marque outside the ATT prompt requirement.
        //
        // Session replay records screen contents, which would capture exactly the
        // PII FR-11.6 forbids (VIN, plate, insurance fields, notes, Assistant
        // messages). Explicitly off rather than relying on the default.
        config.sessionReplay = false

        // Surveys render PostHog-controlled UI inside the app and are unrelated to
        // measurement. Default is true, so this must be set.
        config.surveys = false

        // --- Autocapture off: every FR-11.4 event is deliberate and named ---
        //
        // UIKit element-interaction autocapture would emit unnamed noise and can
        // incidentally capture the text of the control it captured — i.e. PII.
        config.captureElementInteractions = false

        // `$screen` autocapture would send view titles. Several Marque screens are
        // titled with `Car.displayName`, and screen-name stamping then attaches
        // that to every later event.
        config.captureScreenViews = false

        // SDK-side lifecycle events ("Application Opened"/"Installed"/"Updated")
        // would double-count against `app_opened` / `app_launch_completed` below,
        // which are the instrumented lifecycle events FR-11.4 specifies.
        config.captureApplicationLifecycleEvents = false

        // Nothing this service uses needs method swizzling (manual capture,
        // identify, alias, reset). Disabling it means no autocapture, screen-view,
        // replay, or survey integration can be installed at all, which is a
        // structural backstop for the four flags above. Marque uses local
        // notifications only (see NotificationManager), so losing PostHog's APNs
        // token swizzling costs nothing.
        config.enableSwizzling = false

        // Belt and braces alongside `enableSwizzling = false`: do not register the
        // device's APNs token with PostHog and do not capture notification opens.
        config.capturePushNotificationSubscriptions = false
        config.capturePushNotificationOpened = false

        // FR-11.8: crash reporting is explicitly *not* PostHog's job (a separate
        // crash reporter is required). Default is already false; pinned so an SDK
        // default change cannot quietly start shipping crash payloads here.
        config.errorTrackingConfig.autoCapture = false

        // Person profiles are created on identify/alias only — anonymous events
        // carry no profile, and the anonymous -> identified merge still happens at
        // `identify` so the FR-11.3 install -> signup funnel survives. This is the
        // SDK default; pinned because the value is load-bearing for FR-11.3.
        config.personProfiles = .identifiedOnly

        // Debug builds log every capture/flush to the console, which is the only
        // way to confirm an event actually left the device without reading the
        // PostHog dashboard. Compiled out of release, so it can stay.
        #if DEBUG
        config.debug = true
        #endif

        PostHogSDK.shared.setup(config)
    }

    /// FR-11.3 — identify the user by Firebase `uid` so identity survives reinstall
    /// and matches server-side records.
    ///
    /// This *aliases* rather than merely setting the distinct ID. `identify` emits
    /// `$identify` carrying `$anon_distinct_id` (the pre-signup anonymous ID), and
    /// the follow-up `alias` call emits `$create_alias` binding that same anonymous
    /// ID to the uid. Both point at the same merge, which keeps the install ->
    /// signup funnel connected even if the `$identify` merge is skipped — the SDK
    /// only emits it on the first identify for a given stored identity.
    static func identify(uid: String) {
        guard !uid.isEmpty else { return }

        let previousId = PostHogSDK.shared.getDistinctId()
        PostHogSDK.shared.identify(uid)

        // Nothing to alias if this device is already identified as this uid
        // (every launch after the first), and self-aliasing would be a no-op merge.
        guard previousId != uid else { return }
        PostHogSDK.shared.alias(previousId)
    }

    /// Call on sign-out. Clears the stored identity so the next user on this device
    /// starts from a fresh anonymous ID instead of being merged into the previous
    /// person. Queued events are flushed first so they ship under the identity that
    /// produced them.
    static func reset() {
        PostHogSDK.shared.flush()
        PostHogSDK.shared.reset()
    }

    // MARK: - Enumerated property values
    //
    // Raw values are the wire values in FR-11.4's table. Changing one breaks every
    // saved insight built on it.

    /// `signup_completed.method`
    enum AuthMethod: String {
        case apple
        case google
        case email
    }

    /// `car_added.entry_method`
    enum CarEntryMethod: String {
        case vin
        case manual
    }

    /// `paywall_viewed.trigger` — FR-11.5 calls this the single most important
    /// property in the table; it must never be omitted, hence no default value.
    enum PaywallTrigger: String {
        case carLimit = "car_limit"
        case assistantCap = "assistant_cap"
        case scanCap = "scan_cap"
        case settings
    }

    /// `purchase_completed.plan`
    enum SubscriptionPlan: String {
        case monthly
        case annual
    }

    /// `document_scan_completed.doc_type` — mirrors the three scanners that exist
    /// (`DocumentScanService.DocumentKind` / the `parse*` Cloud Functions).
    enum DocumentType: String {
        case driverLicense = "driver_license"
        case insuranceCard = "insurance_card"
        case maintenanceReceipt = "maintenance_receipt"
    }

    /// `onboarding_step_viewed.step` — the FR-13.2 sequence. `garage` is the
    /// terminal destination, not a step, so it is not a case here.
    enum OnboardingStep: String {
        case valueFraming = "value_framing"
        case authentication
        case profileSetup = "profile_setup"
        case addFirstCar = "add_first_car"
    }

    // MARK: - App lifecycle events

    /// Serves D1/D7/D30 retention.
    static func appOpened(isFirstOpen: Bool) {
        capture("app_opened", ["is_first_open": isFirstOpen])
    }

    /// Serves the cold-launch <2s target.
    static func appLaunchCompleted(durationMs: Int) {
        capture("app_launch_completed", ["duration_ms": durationMs])
    }

    // MARK: - Onboarding events

    /// FR-13.5 — identifies where users abandon onboarding (mitigates R-01).
    ///
    /// No call site yet: the FR-13 onboarding flow is not built. Wire this from
    /// each step of that flow when it lands.
    static func onboardingStepViewed(step: OnboardingStep) {
        capture("onboarding_step_viewed", ["step": step.rawValue])
    }

    /// Serves R-01 (activation).
    ///
    /// No call site yet: the FR-13 onboarding flow is not built.
    static func onboardingCompleted(addedCar: Bool, skipped: Bool) {
        capture("onboarding_completed", ["added_car": addedCar, "skipped": skipped])
    }

    // MARK: - Auth events

    /// Serves signup rate and auth-method distribution.
    static func signupCompleted(method: AuthMethod) {
        capture("signup_completed", ["method": method.rawValue])
    }

    // MARK: - Garage events

    /// Serves activation and time-to-first-car (FR-13.7 targets <3 min from
    /// `signup_completed`). `secondsSinceSignup` is omitted when the signup date is
    /// unknown rather than sent as a sentinel.
    static func carAdded(entryMethod: CarEntryMethod, secondsSinceSignup: Int? = nil) {
        var properties: [String: Any] = ["entry_method": entryMethod.rawValue]
        if let secondsSinceSignup {
            properties["seconds_since_signup"] = secondsSinceSignup
        }
        capture("car_added", properties)
    }

    /// Serves photo upload rate.
    static func carPhotoAdded() {
        capture("car_photo_added")
    }

    /// Serves records per active car.
    static func maintenanceRecordAdded() {
        capture("maintenance_record_added")
    }

    /// Serves public car rate.
    static func carVisibilityChanged(isPublic: Bool) {
        capture("car_visibility_changed", ["is_public": isPublic])
    }

    // MARK: - Social events

    /// Serves follow rate.
    static func userFollowed() {
        capture("user_followed")
    }

    // MARK: - Notification events

    /// Serves notification opt-in rate.
    static func notificationPermissionResult(granted: Bool) {
        capture("notification_permission_result", ["granted": granted])
    }

    // MARK: - Assistant events

    /// Serves Assistant engagement. Carries only whether the message was scoped to
    /// a car — never the message body (FR-11.6).
    static func assistantMessageSent(wasScopedToCar: Bool) {
        capture("assistant_message_sent", ["was_scoped_to_car": wasScopedToCar])
    }

    /// Pro demand signal; half of the R-13 cap calibration.
    static func assistantCapReached() {
        capture("assistant_cap_reached")
    }

    // MARK: - Document scanning events

    /// Serves scanning engagement. FR-14.5: emit only on a successful extraction.
    static func documentScanCompleted(docType: DocumentType) {
        capture("document_scan_completed", ["doc_type": docType.rawValue])
    }

    /// Pro demand signal; the other half of the R-13 cap calibration.
    ///
    /// No call site yet: the FR-14.4 server-side document-scan allowance is not
    /// built, so there is no cap to reach. Wire this where that cap is enforced.
    static func documentScanCapReached() {
        capture("document_scan_cap_reached")
    }

    // MARK: - Monetization events

    /// FR-11.5 — `trigger` is the only way to learn which Pro gate converts.
    static func paywallViewed(trigger: PaywallTrigger) {
        capture("paywall_viewed", ["trigger": trigger.rawValue])
    }

    /// Serves conversion rate and the monthly/annual plan split.
    static func purchaseCompleted(plan: SubscriptionPlan) {
        capture("purchase_completed", ["plan": plan.rawValue])
    }

    // MARK: - Private

    /// The single capture path. Private on purpose — see the file header.
    private static func capture(_ event: String, _ properties: [String: Any]? = nil) {
        PostHogSDK.shared.capture(event, properties: properties)
    }
}
