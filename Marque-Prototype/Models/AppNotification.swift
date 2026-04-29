import Foundation

struct AppNotification: Identifiable, Equatable {
    let id: String
    let actor: AppUser
    let type: NotificationType
    let postID: String?
    let createdAt: Date
    var isRead: Bool

    enum NotificationType {
        case like(postCaption: String)
        case comment(text: String)
        case follow
        case mention(postCaption: String)
    }

    static func == (lhs: AppNotification, rhs: AppNotification) -> Bool {
        lhs.id == rhs.id
    }

    var body: String {
        switch type {
        case .like(let caption):
            return "liked your post\(caption.isEmpty ? "." : ": \"\(caption)\"")"
        case .comment(let text):
            return "commented: \"\(text)\""
        case .follow:
            return "started following you."
        case .mention(let caption):
            return "mentioned you in a post\(caption.isEmpty ? "." : ": \"\(caption)\"")"
        }
    }
}
