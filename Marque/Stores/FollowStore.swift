import Foundation
import FirebaseFirestore

@MainActor
class FollowStore: ObservableObject {
    @Published private(set) var followingUIDs: Set<String> = []
    @Published private(set) var followerUIDs: Set<String> = []
    var followerCount: Int { followerUIDs.count }

    private var followingListener: ListenerRegistration?
    private var followerListener: ListenerRegistration?
    private var currentUID: String?
    private let db = Firestore.firestore()

    var followingCount: Int { followingUIDs.count }

    private func followingRef(from followerUID: String, to followedUID: String) -> DocumentReference {
        db.collection("users").document(followerUID).collection("following").document(followedUID)
    }

    private func followerRef(of followedUID: String, by followerUID: String) -> DocumentReference {
        db.collection("users").document(followedUID).collection("followers").document(followerUID)
    }

    func startListening(uid: String) {
        guard uid != currentUID else { return }
        stopListening()
        currentUID = uid

        followingListener = db.collection("users").document(uid)
            .collection("following")
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self, let snapshot else { return }
                self.followingUIDs = Set(snapshot.documents.map { $0.documentID })
            }

        followerListener = db.collection("users").document(uid)
            .collection("followers")
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self, let snapshot else { return }
                self.followerUIDs = Set(snapshot.documents.map { $0.documentID })
            }
    }

    func stopListening() {
        followingListener?.remove()
        followerListener?.remove()
        followingListener = nil
        followerListener = nil
        currentUID = nil
        followingUIDs = []
        followerUIDs = []
    }

    func isFollowing(_ uid: String) -> Bool {
        followingUIDs.contains(uid)
    }

    /// Optimistically drops `uid` from both local follow sets. Called from
    /// MarqueApp when BlockStore reports a fresh block, so a mutual
    /// follow/follower relationship disappears from the UI immediately rather
    /// than waiting on the server-side cascade (the `onUserBlocked` trigger,
    /// which deletes the actual Firestore edges) and this store's own
    /// listeners to catch up. Purely a local cache edit — the listeners
    /// remain the source of truth and reconcile on their next snapshot.
    func removeLocal(uid: String) {
        followingUIDs.remove(uid)
        followerUIDs.remove(uid)
    }

    func follow(
        uid: String,
        actorDisplayName: String = "",
        actorUsername: String = "",
        actorAvatarURL: String? = nil
    ) async {
        guard let currentUID, currentUID != uid else { return }

        followingUIDs.insert(uid)

        let batch = db.batch()
        batch.setData(["followedAt": FieldValue.serverTimestamp()], forDocument: followingRef(from: currentUID, to: uid))
        batch.setData(["followedAt": FieldValue.serverTimestamp()], forDocument: followerRef(of: uid, by: currentUID))

        do {
            try await batch.commit()
            // FR-11.4 `user_followed` — committed follows only. Deliberately not
            // mirrored in unfollow(): the event measures follow rate, and an
            // unfollow is not a follow.
            AnalyticsService.userFollowed()
            NotificationStore.writeFollowNotification(
                to: uid,
                actorUID: currentUID,
                actorDisplayName: actorDisplayName,
                actorUsername: actorUsername,
                actorAvatarURL: actorAvatarURL
            )
        } catch {
            followingUIDs.remove(uid)
        }
    }

    func unfollow(uid: String) async {
        guard let currentUID else { return }

        // Optimistic update
        followingUIDs.remove(uid)

        let batch = db.batch()
        batch.deleteDocument(followingRef(from: currentUID, to: uid))
        batch.deleteDocument(followerRef(of: uid, by: currentUID))

        do {
            try await batch.commit()
        } catch {
            followingUIDs.insert(uid)
        }
    }

    func followingFeed(from cars: [PublicCar]) -> [PublicCar] {
        cars.filter { followingUIDs.contains($0.ownerUID) }
    }
}
