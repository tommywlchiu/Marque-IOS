import Foundation
import FirebaseFirestore

enum ReportReason: String, CaseIterable, Identifiable {
    case spam         = "Spam or misleading"
    case inappropriate = "Inappropriate content"
    case harassment   = "Harassment or bullying"
    case fake         = "Fake account or impersonation"
    case other        = "Other"

    var id: String { rawValue }
}

/// `contentId` values for `reports/` (BlockStore.report / CommentStore.report):
/// the Firestore path of the reported content, so a moderator can open it
/// directly. `reportedUID` is always the content's author/owner.
enum ReportContent {
    /// A comment. reportedUID = the comment's authorUID.
    static func comment(carId: String, commentId: String) -> String {
        "publicCars/\(carId)/comments/\(commentId)"
    }

    /// A public car's engine sound clip. reportedUID = the car's ownerUID.
    static func engineSound(carId: String) -> String {
        "publicCars/\(carId)/engineSound"
    }

    /// A public car listing (photos, notes). reportedUID = the car's ownerUID.
    static func car(carId: String) -> String {
        "publicCars/\(carId)"
    }
}

@MainActor
class BlockStore: ObservableObject {
    @Published private(set) var blockedUIDs: Set<String> = []
    @Published private(set) var lastError: String?
    // Set to the just-blocked uid on a successful block(), so
    // Marque_PrototypeApp can tell FollowStore to drop any local follow
    // state for that uid immediately, without BlockStore knowing about
    // FollowStore directly (stores stay decoupled — see CLAUDE.md). The
    // server-side cascade (onUserBlocked trigger) removes the actual
    // Firestore edges; this only fixes up this device's local cache so the
    // UI doesn't wait on that round trip.
    @Published private(set) var lastBlockedUID: String?

    private var listener: ListenerRegistration?
    private var currentUID: String?
    private let db = Firestore.firestore()

    func startListening(uid: String) {
        guard uid != currentUID else { return }
        stopListening()
        currentUID = uid
        listener = db.collection("users").document(uid).collection("blocked")
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self, let snapshot else { return }
                self.blockedUIDs = Set(snapshot.documents.map { $0.documentID })
            }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
        currentUID = nil
        blockedUIDs = []
        lastBlockedUID = nil
    }

    func isBlocked(_ uid: String) -> Bool {
        blockedUIDs.contains(uid)
    }

    func block(uid: String) async {
        guard let currentUID else { return }
        blockedUIDs.insert(uid)
        do {
            try await db.collection("users").document(currentUID)
                .collection("blocked").document(uid)
                .setData(["blockedAt": FieldValue.serverTimestamp()])
            lastBlockedUID = uid
        } catch {
            blockedUIDs.remove(uid)
        }
    }

    func unblock(uid: String) async {
        guard let currentUID else { return }
        blockedUIDs.remove(uid)
        do {
            try await db.collection("users").document(currentUID)
                .collection("blocked").document(uid)
                .delete()
        } catch {
            blockedUIDs.insert(uid)
        }
    }

    func report(reportedUID: String, reason: ReportReason, contentId: String? = nil) async throws {
        guard let currentUID else { throw NSError(domain: "BlockStore", code: 401) }
        var data: [String: Any] = [
            "reporterUID": currentUID,
            "reportedUID": reportedUID,
            "reason": reason.rawValue,
            "createdAt": FieldValue.serverTimestamp()
        ]
        if let contentId { data["contentId"] = contentId }
        do {
            _ = try await db.collection("reports").addDocument(data: data)
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    func filter<T>(_ items: [T], ownerUID: KeyPath<T, String>) -> [T] {
        items.filter { !blockedUIDs.contains($0[keyPath: ownerUID]) }
    }
}
