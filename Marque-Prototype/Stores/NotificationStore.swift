import Foundation
import FirebaseFirestore

@MainActor
class NotificationStore: ObservableObject {
    @Published var notifications: [AppNotification] = []

    // badgeCount drives the bell icon in the Explore toolbar.
    // It only increases when new unread notifications arrive and is only
    // zeroed by clearBadge() (called on inbox open) or markAllRead().
    // This lets the bell stay clear while the user is actively reading.
    @Published var badgeCount: Int = 0

    var unreadCount: Int { notifications.filter { !$0.isRead }.count }

    private var listener: ListenerRegistration?
    private var currentUID: String?
    private let db = Firestore.firestore()

    func startListening(uid: String) {
        guard uid != currentUID else { return }
        stopListening()
        currentUID = uid

        // Sort client-side to avoid requiring a composite Firestore index on createdAt.
        listener = db.collection("users").document(uid)
            .collection("notifications")
            .limit(to: 50)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if let error {
                    print("[NotificationStore] Listener error: \(error.localizedDescription)")
                    return
                }
                guard let snapshot else { return }
                let fresh = snapshot.documents
                    .compactMap { doc -> AppNotification? in
                        do {
                            return try doc.data(as: AppNotification.self)
                        } catch {
                            print("[NotificationStore] Decode error for \(doc.documentID): \(error)")
                            return nil
                        }
                    }
                    .sorted { $0.createdAt > $1.createdAt }
                // Only bump the badge — never shrink it from the listener.
                // The badge is zeroed only by clearBadge() or markAllRead().
                let freshUnread = fresh.filter { !$0.isRead }.count
                if freshUnread > self.badgeCount {
                    self.badgeCount = freshUnread
                }
                self.notifications = fresh
            }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
        currentUID = nil
        notifications = []
        badgeCount = 0
    }

    func clearBadge() {
        badgeCount = 0
    }

    func markRead(_ notification: AppNotification) {
        guard let uid = currentUID, let id = notification.id else { return }
        guard !notification.isRead else { return }
        db.collection("users").document(uid)
            .collection("notifications").document(id)
            .updateData(["isRead": true])
        if let i = notifications.firstIndex(where: { $0.id == id }) {
            notifications[i].isRead = true
        }
    }

    func markAllRead() {
        guard let uid = currentUID else { return }
        let unread = notifications.filter { !$0.isRead }
        guard !unread.isEmpty else { return }
        let batch = db.batch()
        for note in unread {
            guard let id = note.id else { continue }
            batch.updateData(
                ["isRead": true],
                forDocument: db.collection("users").document(uid)
                    .collection("notifications").document(id)
            )
        }
        batch.commit()
        for i in notifications.indices where !notifications[i].isRead {
            notifications[i].isRead = true
        }
        badgeCount = 0
    }

    // MARK: - Delete

    // Optimistic removal: drops the row locally first so the swipe animation is
    // immediate, then deletes the Firestore document. Reverts on failure.
    func delete(_ notification: AppNotification) async {
        guard let uid = currentUID, let id = notification.id else { return }

        let backup = notifications
        notifications.removeAll(where: { $0.id == id })

        do {
            try await db.collection("users").document(uid)
                .collection("notifications").document(id).delete()
        } catch {
            notifications = backup
            print("[NotificationStore] Delete error: \(error.localizedDescription)")
        }
    }

    // MARK: - Pull to refresh

    // Forces a server round-trip so the user sees the pull-to-refresh spinner
    // resolve against the network, not just the local cache. The live listener
    // picks up any deltas through its normal snapshot pipeline.
    func refresh() async {
        guard let uid = currentUID else { return }
        do {
            _ = try await db.collection("users").document(uid)
                .collection("notifications")
                .limit(to: 50)
                .getDocuments(source: .server)
        } catch {
            print("[NotificationStore] Refresh error: \(error.localizedDescription)")
        }
    }

    // MARK: - Write helpers (called from FollowStore)

    static func writeFollowNotification(
        to followedUID: String,
        actorUID: String,
        actorDisplayName: String,
        actorUsername: String,
        actorAvatarURL: String?
    ) {
        let db = Firestore.firestore()
        let data: [String: Any] = [
            "type": AppNotification.AppNotificationType.follow.rawValue,
            "actorUID": actorUID,
            "actorDisplayName": actorDisplayName,
            "actorUsername": actorUsername,
            "actorAvatarURL": actorAvatarURL ?? "",
            "isRead": false,
            "createdAt": FieldValue.serverTimestamp()
        ]
        db.collection("users").document(followedUID)
            .collection("notifications")
            .addDocument(data: data) { error in
                if let error {
                    print("[NotificationStore] Failed to write follow notification: \(error.localizedDescription)")
                }
            }
    }
}
