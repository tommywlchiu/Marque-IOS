import Foundation

struct Comment: Identifiable, Equatable {
    let id: String
    let postID: String
    let author: AppUser
    let text: String
    let createdAt: Date
    var likeCount: Int
    var isLikedByMe: Bool
}
