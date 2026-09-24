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

@MainActor
class BlockStore: ObservableObject {
    @Published private(set) var blockedUIDs: Set<String> = []
    @Published private(set) var lastError: String?

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
