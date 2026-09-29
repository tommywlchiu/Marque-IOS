import Foundation
import FirebaseFirestore

/// A comment on a public car: `publicCars/{carId}/comments/{id}`.
///
/// The author fields are a snapshot of the author's profile when they posted
/// (firestore.rules requires them to equal `users/{authorUID}` at write time),
/// so a later username or avatar change doesn't rewrite old comments.
struct CarComment: Identifiable, Codable, Equatable {
    @DocumentID var documentID: String?
    let authorUID: String
    let authorUsername: String
    let authorDisplayName: String
    /// Empty string when the author has no avatar.
    let authorAvatarURL: String
    /// 1–500 characters.
    let text: String
    /// Server timestamp. While a just-posted comment is still pending, this is
    /// the local estimate (CommentStore decodes with `.estimate`).
    let createdAt: Date

    /// Stable identity for SwiftUI lists. A decoded comment always has a
    /// document ID.
    var id: String { documentID ?? "\(authorUID)-\(createdAt.timeIntervalSince1970)" }

    var avatarURL: URL? {
        authorAvatarURL.isEmpty ? nil : URL(string: authorAvatarURL)
    }

    /// Length limit enforced by firestore.rules (`text.size() <= 500`, which
    /// counts characters, not bytes).
    static let maxLength = 500
}
