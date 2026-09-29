import Foundation
import UIKit
import FirebaseFirestore
import FirebaseMessaging

/// Remote push (FCM) for new followers, likes and comments, plus the
/// per-type preferences the server honors.
///
/// - Device token: `users/{uid}/devices/{fcmToken}` = `{ token, platform: "ios", updatedAt }`.
///   Registered on sign-in and on every token refresh; the doc is deleted and
///   the FCM token invalidated on sign-out (`prepareForSignOut`, called from
///   AuthService.signOut via its `willSignOut` hook).
/// - Preferences: `users/{uid}/settings/notifications` = `{ follows, likes, comments }`.
///   Missing means on. The server's `sendPush` reads them before each push.
///
/// This store NEVER shows the permission prompt. AppDelegate registers for
/// remote notifications at launch (no prompt), which gets an APNs and FCM
/// token. Whether pushes are actually displayed depends on the user granting
/// notification permission, which the app already asks for through
/// `NotificationManager.requestPermission()` at its existing moments. The
/// frontend can call it again from a notification-settings screen.
@MainActor
final class PushStore: NSObject, ObservableObject {
    @Published private(set) var preferences = NotificationPreferences()
    /// False until the first snapshot of the preferences doc arrives.
    @Published private(set) var preferencesLoaded = false
    /// Current FCM registration token, if FCM has issued one. Diagnostic.
    @Published private(set) var fcmToken: String?

    private let db = Firestore.firestore()
    private var currentUID: String?
    private var preferencesListener: ListenerRegistration?
    /// The token doc written for `currentUID`, so a refresh can delete the
    /// old one.
    private var registeredToken: String?

    override init() {
        super.init()
        // Weakly held by FCM. Set here because @StateObject builds this after
        // FirebaseApp.configure() has run in the App's init.
        Messaging.messaging().delegate = self
    }

    // MARK: - Auth lifecycle

    func startListening(uid: String) {
        guard uid != currentUID else { return }
        stopListening()
        currentUID = uid

        preferencesListener = preferencesRef(uid).addSnapshotListener { [weak self] snapshot, error in
            guard let self, self.currentUID == uid else { return }
            if let error {
                print("[PushStore] Preferences listener error: \(error.localizedDescription)")
                return
            }
            self.preferences = NotificationPreferences(firestoreData: snapshot?.data())
            self.preferencesLoaded = true
        }

        // The delegate normally delivers the token at launch, possibly
        // before sign-in. Ask again so this account gets it now.
        Messaging.messaging().token { [weak self] token, _ in
            guard let token else { return }
            Task { @MainActor [weak self] in self?.handleToken(token) }
        }
        if let fcmToken { register(token: fcmToken, uid: uid) }
    }

    func stopListening() {
        preferencesListener?.remove()
        preferencesListener = nil
        currentUID = nil
        registeredToken = nil
        preferences = NotificationPreferences()
        preferencesLoaded = false
    }

    /// Call BEFORE Firebase Auth signs out, while the client can still write
    /// as this user (AuthService.signOut awaits it through `willSignOut`).
    /// Deletes this device's token doc and invalidates the FCM token itself,
    /// concurrently, and returns when both finish or after
    /// `signOutCleanupTimeout` seconds, whichever comes first. Offline, the
    /// Firestore delete stays queued and would otherwise never return. Even if
    /// the doc delete never lands, the invalidated token makes the server's next
    /// send fail as not-registered, and sendPush prunes it. A fresh token is
    /// issued for the next account that signs in.
    func prepareForSignOut() async {
        let uid = currentUID
        let token = registeredToken
        currentUID = nil
        registeredToken = nil
        fcmToken = nil
        let docRef = (uid != nil && token != nil) ? devicesRef(uid!).document(token!) : nil
        await Self.run(timeout: Self.signOutCleanupTimeout) {
            async let docDeleted: Void = {
                guard let docRef else { return }
                do { try await docRef.delete() } catch {
                    print("[PushStore] Token doc delete failed: \(error.localizedDescription)")
                }
            }()
            async let tokenDeleted: Void = {
                do { try await Messaging.messaging().deleteToken() } catch {
                    print("[PushStore] FCM deleteToken failed: \(error.localizedDescription)")
                }
            }()
            _ = await (docDeleted, tokenDeleted)
        }
    }

    /// Upper bound on how long sign-out waits for the push cleanup.
    static let signOutCleanupTimeout: Double = 3

    /// Runs `operation` and returns when it finishes or `timeout` seconds pass,
    /// whichever is first. Unlike a task group, it does NOT wait for an
    /// operation that ignores cancellation (a Firestore write queued offline
    /// never completes); that work carries on in the background.
    private static func run(timeout: Double, _ operation: @escaping () async -> Void) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let once = ResumeOnce(continuation)
            Task { await operation(); once.resume() }
            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                once.resume()
            }
        }
    }

    /// Registers the current FCM token for the signed-in user again. Call when
    /// an earlier registration may have been denied, which happens for a new
    /// account before its users/{uid} profile doc exists (the devices rule
    /// requires it). Marque.swift calls this when profile setup completes.
    func refreshRegistration() {
        guard let uid = currentUID, let fcmToken else { return }
        register(token: fcmToken, uid: uid)
    }

    // MARK: - Preferences

    /// Turns one push type on or off (merge write). Updates `preferences`
    /// optimistically and rolls back if the write fails.
    func setPreference(_ kind: NotificationPreferences.Kind, enabled: Bool) async throws {
        guard let uid = currentUID else { return }
        let previous = preferences
        preferences[kind] = enabled
        do {
            try await preferencesRef(uid).setData([
                kind.rawValue: enabled,
                "updatedAt": FieldValue.serverTimestamp(),
            ], merge: true)
        } catch {
            if currentUID == uid { preferences = previous }
            throw error
        }
    }

    // MARK: - Registration

    /// Registers with APNs for remote notifications. Does not prompt. Called
    /// from AppDelegate at launch; safe to call again.
    static func registerForRemoteNotifications() {
        UIApplication.shared.registerForRemoteNotifications()
    }

    fileprivate func handleToken(_ token: String) {
        fcmToken = token
        guard let uid = currentUID else { return }
        register(token: token, uid: uid)
    }

    private func register(token: String, uid: String) {
        #if DEBUG
        // For sending a test push from the Firebase console (Messaging →
        // "Send test message"). Debug only; the token is a device secret.
        print("[PushStore] FCM token: \(token)")
        #endif
        guard token != registeredToken else { return }
        if let old = registeredToken {
            devicesRef(uid).document(old).delete(completion: nil)
        }
        registeredToken = token
        devicesRef(uid).document(token).setData([
            "token": token,
            "platform": "ios",
            "updatedAt": FieldValue.serverTimestamp(),
        ]) { [weak self] error in
            guard let error else { return }
            print("[PushStore] Token registration failed: \(error.localizedDescription)")
            // Forget it so refreshRegistration (or the next token callback)
            // tries again instead of assuming it's registered.
            Task { @MainActor [weak self] in
                guard let self, self.currentUID == uid, self.registeredToken == token else { return }
                self.registeredToken = nil
            }
        }
    }

    private func devicesRef(_ uid: String) -> CollectionReference {
        db.collection("users").document(uid).collection("devices")
    }

    private func preferencesRef(_ uid: String) -> DocumentReference {
        db.collection("users").document(uid).collection("settings").document("notifications")
    }
}

extension PushStore: MessagingDelegate {
    /// Initial token and every refresh.
    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken else { return }
        Task { @MainActor [weak self] in self?.handleToken(fcmToken) }
    }
}

/// Resumes a continuation exactly once, from whichever caller gets there first.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    private let continuation: CheckedContinuation<Void, Never>

    init(_ continuation: CheckedContinuation<Void, Never>) {
        self.continuation = continuation
    }

    func resume() {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return }
        done = true
        continuation.resume()
    }
}
