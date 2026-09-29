import Foundation

/// Push notification preferences at `users/{uid}/settings/notifications`.
/// The server's `sendPush` reads them before every push. A missing doc or
/// field means ON, so these default to true.
struct NotificationPreferences: Equatable {
    enum Kind: String, CaseIterable, Identifiable {
        /// Firestore field names; also the server's PushPreference values.
        case follows, likes, comments

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .follows: return "New followers"
            case .likes: return "Likes on your cars"
            case .comments: return "Comments on your cars"
            }
        }
    }

    var follows = true
    var likes = true
    var comments = true

    subscript(kind: Kind) -> Bool {
        get {
            switch kind {
            case .follows: return follows
            case .likes: return likes
            case .comments: return comments
            }
        }
        set {
            switch kind {
            case .follows: follows = newValue
            case .likes: likes = newValue
            case .comments: comments = newValue
            }
        }
    }

    init() {}

    init(firestoreData data: [String: Any]?) {
        follows = (data?["follows"] as? Bool) ?? true
        likes = (data?["likes"] as? Bool) ?? true
        comments = (data?["comments"] as? Bool) ?? true
    }
}
