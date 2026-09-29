import Foundation
import FirebaseFirestore

struct AppNotification: Identifiable, Codable, Equatable {
    @DocumentID var id: String?
    var type: AppNotificationType
    var actorUID: String
    var actorDisplayName: String
    var actorUsername: String
    var actorAvatarURL: String?
    var caption: String?
    var postID: String?
    var isRead: Bool
    var createdAt: Date

    enum AppNotificationType: String, Codable {
        case follow, like, comment, mention
    }

    /// For `.like` / `.comment` notifications (written server-side by
    /// onCarLikeWritten / onCarCommentWritten): the id of the recipient's own
    /// car that was liked or commented on (`Car.id.uuidString`). `caption` is
    /// the car's name for a like, and an 80-character preview of the comment.
    var carID: String? { postID }

    static func == (lhs: AppNotification, rhs: AppNotification) -> Bool {
        lhs.id == rhs.id
    }

    var body: String {
        switch type {
        case .follow:
            return "started following you."
        case .like:
            return "liked your car" + (caption.map { ": \"\($0)\"" } ?? ".")
        case .comment:
            return "commented" + (caption.map { ": \"\($0)\"" } ?? ".")
        case .mention:
            return "mentioned you" + (caption.map { " in: \"\($0)\"" } ?? ".")
        }
    }
}
