import Foundation
import FirebaseAuth

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

    // Driver License — private to this user, never exposed publicly. Stored
    // for personal reference (same role as VIN/insurance policy on the car).
    var driverLicenseNumber: String = ""
    var driverLicenseState: String = ""
    var driverLicenseExpiryDate: Date? = nil

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

}

extension AppUser {
    // Maps a live Firebase user + locally stored extras into an AppUser.
    // Fields not tracked by Firebase (bio, location, followerCount, etc.) come
    // from LocalProfile stored in UserDefaults; move them to Firestore in production.
    init(firebaseUser: FirebaseAuth.User, profile: (
        username: String,
        bio: String,
        location: String,
        avatarFileName: String?,
        avatarStorageURL: String?,
        driverLicenseNumber: String,
        driverLicenseState: String,
        driverLicenseExpiryDate: Date?
    )) {
        id = firebaseUser.uid
        displayName = firebaseUser.displayName ?? "User"
        username = profile.username
        bio = profile.bio
        avatarURL = profile.avatarStorageURL ?? profile.avatarFileName ?? firebaseUser.photoURL?.absoluteString
        location = profile.location
        followerCount = 0
        followingCount = 0
        isFollowing = false
        isVerified = false
        isProMember = false
        joinedDate = firebaseUser.metadata.creationDate ?? Date()
        driverLicenseNumber = profile.driverLicenseNumber
        driverLicenseState = profile.driverLicenseState
        driverLicenseExpiryDate = profile.driverLicenseExpiryDate
    }
}
