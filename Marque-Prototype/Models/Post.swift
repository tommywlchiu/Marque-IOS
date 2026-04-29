import Foundation

struct Post: Identifiable, Equatable {
    let id: String
    let user: AppUser
    let car: Car
    let caption: String
    var likeCount: Int
    var commentCount: Int
    var isLiked: Bool
    let createdAt: Date

    static func == (lhs: Post, rhs: Post) -> Bool {
        lhs.id == rhs.id
    }
}
