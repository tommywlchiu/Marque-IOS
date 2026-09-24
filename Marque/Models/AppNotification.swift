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
