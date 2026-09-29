import UIKit
import UserNotifications
import FirebaseMessaging

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, ObservableObject {
    /// Set by the notification delegate when the user taps a notification that
    /// carries a `carId`: a car-expiry local notification, or a like/comment
    /// push (the carId is the recipient's OWN car, so it opens in Garage).
    /// Consumers clear it after navigation so one-shot routing works correctly.
    @Published var pendingCarID: UUID?

    /// Set when the user taps a remote push (FCM). Consumers clear it after
    /// routing. For `.like` / `.comment` the car is also in `pendingCarID`.
    @Published var pendingPush: PushRoute?

    struct PushRoute: Equatable {
        enum Kind: String {
            case follow, like, comment
        }
        let kind: Kind
        /// Who followed / liked / commented.
        let actorUID: String?
        /// `Car.id.uuidString` of the recipient's car (like/comment only).
        let carId: String?
        /// The comment's document ID (comment only).
        let commentId: String?
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // Registers with APNs for a device token. This does NOT show the
        // permission prompt (NotificationManager.requestPermission does, at
        // its existing moments). Until permission is granted, pushes arrive
        // but aren't displayed.
        PushStore.registerForRemoteNotifications()
        return true
    }

    // Hands the APNs token to FCM explicitly. Firebase's method swizzling does
    // this too; setting it twice is harmless and keeps working if swizzling is
    // ever turned off (FirebaseAppDelegateProxyEnabled = NO).
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("[AppDelegate] Remote notification registration failed: \(error.localizedDescription)")
    }

    // Show a banner + play sound when a notification arrives while the app is foregrounded.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    // Extract the carId (and, for FCM pushes, the push type) from the payload
    // and hand it to the UI layer. FCM `data` keys arrive at the top level of
    // userInfo, next to "aps".
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let raw = userInfo["carId"] as? String {
            pendingCarID = UUID(uuidString: raw)
        }
        if let rawType = userInfo["type"] as? String, let kind = PushRoute.Kind(rawValue: rawType) {
            pendingPush = PushRoute(
                kind: kind,
                actorUID: userInfo["actorUID"] as? String,
                carId: userInfo["carId"] as? String,
                commentId: userInfo["commentId"] as? String
            )
        }
        completionHandler()
    }
}
