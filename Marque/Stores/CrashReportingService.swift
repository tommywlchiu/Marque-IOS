//
//  CrashReportingService.swift
//  Marque-Prototype
//
//  FR-11.8: crash reporting is explicitly NOT PostHog's job (see AnalyticsService)
//  — the >99.5% crash-free target in Section 9 requires a dedicated crash
//  reporter. Firebase Crashlytics fills that gap, reusing the GoogleService-Info.plist
//  already required for the other Firebase products.
//
//  Follows the NotificationManager / AnalyticsService pattern: a struct of
//  static functions, no ObservableObject and no environment injection.
//

import FirebaseCrashlytics

struct CrashReportingService {

    /// Ties crash reports to the reporting uid, mirroring `AnalyticsService.identify`,
    /// so a production crash can be traced back to the account that hit it.
    static func identify(uid: String) {
        Crashlytics.crashlytics().setUserID(uid)
    }

    /// Call on sign-out. Crashlytics has no `reset()` analog to PostHog's —
    /// clearing the user ID is the closest equivalent.
    static func reset() {
        Crashlytics.crashlytics().setUserID("")
    }
}
