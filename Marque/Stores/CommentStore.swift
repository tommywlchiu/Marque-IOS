import Foundation
import FirebaseFirestore

/// Comments on public cars: `publicCars/{carId}/comments/{id}`.
///
/// Auth lifecycle like the other stores (`startListening(uid:)` /
/// `stopListening()` from Marque.swift). A car detail screen calls
/// `listen(to:)` when it appears and `stopListeningToCar()` when it goes
/// away; one car at a time.
///
/// App Store guideline 1.2:
///   - filtering: `post` runs `CommentFilter` first; the server re-checks
///     (onCarCommentWritten) and deletes anything that slips through.
///   - reporting: `report(_:on:reason:)` writes to `reports/`.
///   - blocking: the rules deny comments between blocked users in either
///     direction; for display, hide blocked authors with
///     `visibleComments(hiding: blockStore.blockedUIDs)`.
@MainActor
final class CommentStore: ObservableObject {
    /// The listened-to car's comments, oldest first (newest last), at most
    /// `pageLimit` (the newest ones).
    @Published private(set) var comments: [CarComment] = []
    @Published private(set) var carId: String?
    @Published private(set) var isLoading = false
    /// Listener errors only. `post`/`delete`/`report` throw instead.
    @Published private(set) var lastError: String?

    static let pageLimit = 100

    enum CommentError: LocalizedError, Equatable {
        case empty
        case tooLong
        case notAllowed
        case notSignedIn
        case profileIncomplete
        case rejected

        var errorDescription: String? {
            switch self {
            case .empty: return "Write something first."
            case .tooLong: return "Comments can be at most \(CarComment.maxLength) characters."
            case .notAllowed: return "That comment contains language that isn't allowed."
            case .notSignedIn: return "Sign in to comment."
            case .profileIncomplete: return "Finish setting up your profile to comment."
            case .rejected: return "Couldn't post your comment. You may not be able to comment on this car."
            }
        }
    }

    private let db = Firestore.firestore()
    private var currentUID: String?
    private var listener: ListenerRegistration?

    // MARK: - Auth lifecycle

    func startListening(uid: String) {
        guard uid != currentUID else { return }
        stopListening()
        currentUID = uid
    }

    func stopListening() {
        stopListeningToCar()
        currentUID = nil
    }

    // MARK: - Per-car listener

    func listen(to carId: String, attempt: Int = 0) {
        guard carId != self.carId || listener == nil else { return }
        stopListeningToCar()
        self.carId = carId
        isLoading = true
        listener = commentsRef(carId)
            .order(by: "createdAt", descending: true)
            .limit(to: Self.pageLimit)
            .addSnapshotListener(includeMetadataChanges: false) { [weak self] snapshot, error in
                guard let self, self.carId == carId else { return }
                self.isLoading = false
                if let error {
                    // Right after a car goes public, the page asks for comments
                    // before the public doc exists on the server, and the rules
                    // (comments are readable only while the car is public) deny
                    // it. A denied listener is dead, so retry a few times
                    // before surfacing the error.
                    let ns = error as NSError
                    if ns.domain == FirestoreErrorDomain,
                       ns.code == FirestoreErrorCode.permissionDenied.rawValue,
                       attempt < Self.maxListenRetries {
                        self.listener?.remove()
                        self.listener = nil
                        self.isLoading = true
                        Task { @MainActor [weak self] in
                            try? await Task.sleep(for: .seconds(Double(attempt + 1)))
                            guard let self, self.carId == carId, self.listener == nil else { return }
                            self.carId = nil
                            self.listen(to: carId, attempt: attempt + 1)
                        }
                        return
                    }
                    self.lastError = error.localizedDescription
                    return
                }
                guard let snapshot else { return }
                self.lastError = nil
                self.comments = snapshot.documents
                    .compactMap { try? $0.data(as: CarComment.self, with: .estimate) }
                    .reversed()
            }
    }

    private static let maxListenRetries = 3

    func stopListeningToCar() {
        listener?.remove()
        listener = nil
        carId = nil
        comments = []
        isLoading = false
        lastError = nil
    }

    /// `comments` minus any whose author is in `blockedUIDs` (pass
    /// `blockStore.blockedUIDs`). Covers comments written before a block, and
    /// comments by someone who blocked you but whose older comments remain.
    func visibleComments(hiding blockedUIDs: Set<String>) -> [CarComment] {
        comments.filter { !blockedUIDs.contains($0.authorUID) }
    }

    /// True if the current user may delete `comment`: its author, or the owner
    /// of the car it's on (pass `PublicCar.ownerUID`).
    func canDelete(_ comment: CarComment, carOwnerUID: String) -> Bool {
        guard let currentUID else { return false }
        return comment.authorUID == currentUID || carOwnerUID == currentUID
    }

    // MARK: - Write

    /// Posts `text` on `carId`. Trims whitespace, checks 1–500 characters and
    /// the word filter, then writes with the author fields read from the
    /// user's own `users/{uid}` doc (the rules require an exact match, so this
    /// never uses possibly-stale local profile copies). Throws `CommentError`.
    func post(text: String, on carId: String) async throws {
        guard let uid = currentUID else { throw CommentError.notSignedIn }
        // Drop the zero-width/bidi characters the rules reject (pasted text
        // often carries them), then trim. Whitespace-only, or only U+200D,
        // counts as empty, matching the rule's "one visible character" check.
        let trimmed = CommentFilter.removingRejectedInvisibles(text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.unicodeScalars.contains(where: { !$0.properties.isWhitespace && $0.value != 0x200D }) else {
            throw CommentError.empty
        }
        // Rules count characters (Unicode code points), not bytes.
        guard trimmed.unicodeScalars.count <= CarComment.maxLength else { throw CommentError.tooLong }
        guard CommentFilter.isAllowed(trimmed) else { throw CommentError.notAllowed }

        let profile: [String: Any]
        do {
            profile = try await db.collection("users").document(uid).getDocument().data() ?? [:]
        } catch {
            throw CommentError.rejected
        }
        guard let username = profile["username"] as? String, !username.isEmpty else {
            throw CommentError.profileIncomplete
        }

        let data: [String: Any] = [
            "authorUID": uid,
            "authorUsername": username,
            "authorDisplayName": (profile["displayName"] as? String) ?? "",
            "authorAvatarURL": (profile["avatarURL"] as? String) ?? "",
            "text": trimmed,
            "createdAt": FieldValue.serverTimestamp(),
        ]
        do {
            _ = try await commentsRef(carId).addDocument(data: data)
        } catch {
            print("[CommentStore] post failed: \(error.localizedDescription)")
            throw CommentError.rejected
        }
    }

    /// Deletes `comment` from `carId`. Allowed for its author and the car's
    /// owner (see `canDelete`). Removed from `comments` optimistically.
    func delete(_ comment: CarComment, on carId: String) async throws {
        guard let id = comment.documentID else { return }
        let backup = comments
        if self.carId == carId { comments.removeAll { $0.documentID == id } }
        do {
            try await commentsRef(carId).document(id).delete()
        } catch {
            if self.carId == carId { comments = backup }
            throw error
        }
    }

    /// Reports `comment` for moderation (`reports/`, create-only). The report
    /// carries `contentId = ReportContent.comment(carId:commentId:)`.
    func report(_ comment: CarComment, on carId: String, reason: ReportReason) async throws {
        guard let uid = currentUID else { throw CommentError.notSignedIn }
        guard let id = comment.documentID else { return }
        _ = try await db.collection("reports").addDocument(data: [
            "reporterUID": uid,
            "reportedUID": comment.authorUID,
            "reason": reason.rawValue,
            "createdAt": FieldValue.serverTimestamp(),
            "contentId": ReportContent.comment(carId: carId, commentId: id),
        ])
    }

    private func commentsRef(_ carId: String) -> CollectionReference {
        db.collection("publicCars").document(carId).collection("comments")
    }
}
