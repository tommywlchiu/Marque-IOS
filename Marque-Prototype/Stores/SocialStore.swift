import Foundation

@MainActor
class SocialStore: ObservableObject {
    @Published var posts: [Post] = []

    // Keyed by postID → ordered comments
    @Published private(set) var commentsCache: [String: [Comment]] = [:]

    init() {
        posts = Self.seedPosts()
        commentsCache = Self.seedComments()
    }

    // MARK: - Post actions

    func toggleLike(postID: String) {
        guard let index = posts.firstIndex(where: { $0.id == postID }) else { return }
        posts[index].isLiked.toggle()
        posts[index].likeCount += posts[index].isLiked ? 1 : -1
    }

    // MARK: - Comment actions

    func comments(for postID: String) -> [Comment] {
        commentsCache[postID] ?? []
    }

    func addComment(_ text: String, to postID: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let comment = Comment(
            id: UUID().uuidString,
            postID: postID,
            author: AppUser.preview,
            text: trimmed,
            createdAt: Date(),
            likeCount: 0,
            isLikedByMe: false
        )
        commentsCache[postID, default: []].append(comment)

        if let index = posts.firstIndex(where: { $0.id == postID }) {
            posts[index].commentCount += 1
        }
    }

    func toggleCommentLike(commentID: String, postID: String) {
        guard var list = commentsCache[postID],
              let i = list.firstIndex(where: { $0.id == commentID }) else { return }
        list[i].isLikedByMe.toggle()
        list[i].likeCount += list[i].isLikedByMe ? 1 : -1
        commentsCache[postID] = list
    }

    // MARK: - Seed data

    private static func seedPosts() -> [Post] {
        let cars = CarStore.previewCars
        let users = AppUser.previewFollowers
        let cal = Calendar.current
        let now = Date()
        return [
            Post(id: "p1", user: users[0], car: cars[0],
                 caption: "Just got the tires rotated. Running smooth!",
                 likeCount: 48, commentCount: 6, isLiked: false,
                 createdAt: cal.date(byAdding: .hour, value: -2, to: now) ?? now),
            Post(id: "p2", user: users[1], car: cars[1],
                 caption: "Track day prep complete 🔧",
                 likeCount: 122, commentCount: 18, isLiked: true,
                 createdAt: cal.date(byAdding: .day, value: -1, to: now) ?? now),
            Post(id: "p3", user: users[2], car: cars[2],
                 caption: "Weekend wash day vibes.",
                 likeCount: 77, commentCount: 9, isLiked: false,
                 createdAt: cal.date(byAdding: .day, value: -2, to: now) ?? now),
            Post(id: "p4", user: users[0], car: cars[1],
                 caption: "Hit 50k miles — still going strong.",
                 likeCount: 33, commentCount: 4, isLiked: false,
                 createdAt: cal.date(byAdding: .day, value: -3, to: now) ?? now),
        ]
    }

    private static func seedComments() -> [String: [Comment]] {
        let users = AppUser.previewFollowers
        let cal = Calendar.current
        let now = Date()
        return [
            "p1": [
                Comment(id: "c1", postID: "p1", author: users[1],
                        text: "Nice! What tires did you go with?",
                        createdAt: cal.date(byAdding: .hour, value: -1, to: now) ?? now,
                        likeCount: 3, isLikedByMe: false),
                Comment(id: "c2", postID: "p1", author: users[2],
                        text: "Michelin all the way 🙌",
                        createdAt: cal.date(byAdding: .minute, value: -30, to: now) ?? now,
                        likeCount: 1, isLikedByMe: true),
            ],
            "p2": [
                Comment(id: "c3", postID: "p2", author: users[2],
                        text: "Which track are you hitting? Laguna Seca?",
                        createdAt: cal.date(byAdding: .hour, value: -20, to: now) ?? now,
                        likeCount: 5, isLikedByMe: false),
                Comment(id: "c4", postID: "p2", author: users[0],
                        text: "Let me know if you need a co-driver 😂",
                        createdAt: cal.date(byAdding: .hour, value: -18, to: now) ?? now,
                        likeCount: 8, isLikedByMe: false),
                Comment(id: "c5", postID: "p2", author: users[1],
                        text: "That prep checklist is 🔥",
                        createdAt: cal.date(byAdding: .hour, value: -10, to: now) ?? now,
                        likeCount: 2, isLikedByMe: false),
            ],
            "p3": [
                Comment(id: "c6", postID: "p3", author: users[0],
                        text: "Looking clean! What soap do you use?",
                        createdAt: cal.date(byAdding: .day, value: -2, to: now) ?? now,
                        likeCount: 0, isLikedByMe: false),
            ],
        ]
    }

}
