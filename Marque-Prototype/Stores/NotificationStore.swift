import Foundation
import FirebaseFirestore

@MainActor
class NotificationStore: ObservableObject {
    @Published var notifications: [AppNotification] = []

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
                self.notifications = snapshot.documents
                    .compactMap { doc -> AppNotification? in
                        do {
                            return try doc.data(as: AppNotification.self)
                        } catch {
                            print("[NotificationStore] Decode error for \(doc.documentID): \(error)")
                            return nil
                        }
                    }
                    .sorted { $0.createdAt > $1.createdAt }
            }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
        currentUID = nil
        notifications = []
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
