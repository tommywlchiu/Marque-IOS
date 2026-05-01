import Foundation
#if canImport(FirebaseAuth)
import FirebaseAuth
#endif

struct AppUser: Identifiable, Codable, Equatable {
    var id: String
    var displayName: String
    var username: String
    var bio: String
    var avatarURL: String?
    var location: String
    var followerCount: Int
    var followingCount: Int
    var isFollowing: Bool
    var isVerified: Bool
    var isProMember: Bool
    var joinedDate: Date

    // MARK: - Preview / Mock Data

    static let preview = AppUser(
        id: "preview-user-1",
        displayName: "Alex Johnson",
        username: "alexjdrives",
        bio: "Car enthusiast. Currently obsessed with German engineering. 🏎",
        avatarURL: nil,
        location: "San Francisco, CA",
        followerCount: 248,
        followingCount: 89,
        isFollowing: false,
        isVerified: false,
        isProMember: true,
        joinedDate: Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()
    )

    static let previewFollowers: [AppUser] = [
        AppUser(id: "u2", displayName: "Maria Lopez", username: "mariadrives", bio: "JDM forever", avatarURL: nil, location: "LA, CA", followerCount: 512, followingCount: 200, isFollowing: true, isVerified: false, isProMember: false, joinedDate: Date()),
        AppUser(id: "u3", displayName: "James Kim", username: "jkimcars", bio: "Track day enthusiast", avatarURL: nil, location: "Seattle, WA", followerCount: 88, followingCount: 34, isFollowing: false, isVerified: true, isProMember: true, joinedDate: Date()),
        AppUser(id: "u4", displayName: "Sarah Chen", username: "sarahchengarage", bio: "Restoring a 1969 Mustang", avatarURL: nil, location: "Austin, TX", followerCount: 1200, followingCount: 450, isFollowing: false, isVerified: true, isProMember: true, joinedDate: Date()),
    ]
}

#if canImport(FirebaseAuth)
extension AppUser {
    // Maps a live Firebase user + locally stored extras into an AppUser.
    // Fields not tracked by Firebase (bio, location, followerCount, etc.) come
    // from LocalProfile stored in UserDefaults; move them to Firestore in production.
    init(firebaseUser: FirebaseAuth.User, profile: (username: String, bio: String, location: String)) {
        id = firebaseUser.uid
        displayName = firebaseUser.displayName
            ?? firebaseUser.email?.components(separatedBy: "@").first
            ?? "User"
        username = profile.username
        bio = profile.bio
        avatarURL = firebaseUser.photoURL?.absoluteString
        location = profile.location
        followerCount = 0
        followingCount = 0
        isFollowing = false
        isVerified = false
        isProMember = false
        joinedDate = firebaseUser.metadata.creationDate ?? Date()
    }
}
#endif
