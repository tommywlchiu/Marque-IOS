import Foundation
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import FirebaseStorage
import GoogleSignIn
import AuthenticationServices
import CryptoKit
import UIKit

enum AuthState: Equatable {
    case unauthenticated
    case authenticated(AppUser)
}

@MainActor
class AuthService: NSObject, ObservableObject {
    @Published var authState: AuthState = .unauthenticated
    @Published var hasSeenOnboarding: Bool
    @Published var hasCompletedProfileSetup: Bool = false
    @Published var isEmailVerified: Bool = false
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let onboardingKey = "marque_has_seen_onboarding"
    private let db = Firestore.firestore()
    private var stateListener: AuthStateDidChangeListenerHandle?
    private var currentNonce: String?
    private var appleCompletion: CheckedContinuation<Void, Error>?
    private var appleSignInController: ASAuthorizationController?
    private var isReauthenticating = false

    /// The Firebase provider ID for the current user's primary sign-in method.
    var signInProvider: String {
        Auth.auth().currentUser?.providerData.first?.providerID ?? "password"
    }

    private func userDocument(uid: String) -> DocumentReference {
        db.collection("users").document(uid)
    }

    private func usernameDocument(_ username: String) -> DocumentReference {
        db.collection("usernames").document(username.lowercased())
    }

    override init() {
        hasSeenOnboarding = UserDefaults.standard.bool(forKey: onboardingKey)
        super.init()

        stateListener = Auth.auth().addStateDidChangeListener { [weak self] _, firebaseUser in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let fu = firebaseUser {
                    let p = LocalProfile.load(uid: fu.uid)
                    self.hasCompletedProfileSetup = p.hasCompletedProfileSetup
                    self.isEmailVerified = fu.isEmailVerified
                    self.authState = .authenticated(AppUser(firebaseUser: fu, profile: (
                        username: p.username,
                        bio: p.bio,
                        location: p.location,
                        avatarFileName: p.avatarFileName,
                        avatarStorageURL: p.avatarStorageURL,
                        driverLicenseNumber: p.driverLicenseNumber,
                        driverLicenseState: p.driverLicenseState,
                        driverLicenseExpiryDate: p.driverLicenseExpiryDate
                    )))
                    // Hydrate isPro from Firestore so cross-device Pro unlocks
                    // without requiring "Restore Purchases". The Cloud Function
                    // keeps this field authoritative via App Store Server Notifications.
                    Task { await self.syncProStatusFromFirestore(uid: fu.uid) }
                } else {
                    self.hasCompletedProfileSetup = false
                    self.isEmailVerified = false
                    self.authState = .unauthenticated
                }
            }
        }
    }

    deinit {
        if let stateListener { Auth.auth().removeStateDidChangeListener(stateListener) }
    }

    var currentUser: AppUser? {
        guard case .authenticated(let user) = authState else { return nil }
        return user
    }

    var isAuthenticated: Bool {
        if case .authenticated = authState { return true }
        return false
    }

    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: onboardingKey)
        hasSeenOnboarding = true
    }

    // MARK: - Email / Password

    func signIn(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await Auth.auth().signIn(withEmail: email, password: password)
        } catch {
            errorMessage = authErrorMessage(from: error)
        }
    }

    func signUp(displayName: String, username: String, email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            let changeRequest = result.user.createProfileChangeRequest()
            changeRequest.displayName = displayName.trimmingCharacters(in: .whitespaces)
            try await changeRequest.commitChanges()

            // Send the verification email as part of signup so the user
            // lands on VerifyEmailView with a fresh link already in their inbox.
            // Failure is non-fatal — the user can hit "Resend" if it didn't arrive.
            try? await result.user.sendEmailVerification()

            let trimmedUsername = username.trimmingCharacters(in: .whitespaces)
            let trimmedName = displayName.trimmingCharacters(in: .whitespaces)
            let resolved = !trimmedUsername.isEmpty ? trimmedUsername : trimmedName
            LocalProfile(username: resolved, bio: "", location: "", avatarFileName: nil).save(uid: result.user.uid)
        } catch {
            errorMessage = authErrorMessage(from: error)
        }
    }

    // MARK: - Email Verification

    // Re-sends the verification link. Returns true on success so the caller
    // can show a "sent" confirmation and start its cooldown.
    func resendVerificationEmail() async -> Bool {
        guard let firebaseUser = Auth.auth().currentUser else { return false }
        do {
            try await firebaseUser.sendEmailVerification()
            return true
        } catch {
            errorMessage = authErrorMessage(from: error)
            return false
        }
    }

    // Refreshes the Firebase user so isEmailVerified reflects what the server
    // sees right now (the state listener doesn't fire on reload). Call this
    // when the user taps "I've Verified" or when the app returns to foreground.
    func reloadEmailVerification() async {
        guard let firebaseUser = Auth.auth().currentUser else { return }
        try? await firebaseUser.reload()
        isEmailVerified = Auth.auth().currentUser?.isEmailVerified ?? false
    }

    // MARK: - Apple Sign In

    func signInWithApple() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await performAppleSignIn()
        } catch {
            let asError = error as? ASAuthorizationError
            if asError?.code != .canceled {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func performAppleSignIn() async throws {
        let nonce = randomNonceString()
        currentNonce = nonce

        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.appleCompletion = continuation
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            self.appleSignInController = controller
            controller.performRequests()
        }
    }

    // MARK: - Google Sign In

    func signInWithGoogle() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard let clientID = FirebaseApp.app()?.options.clientID else {
            errorMessage = "Firebase configuration error."
            return
        }

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)

        guard let windowScene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let rootVC = windowScene.keyWindow?.rootViewController else {
            errorMessage = "Unable to present sign-in."
            return
        }

        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootVC)
            guard let idToken = result.user.idToken?.tokenString else {
                errorMessage = "Google Sign In failed: missing ID token."
                return
            }
            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: result.user.accessToken.tokenString
            )
            try await Auth.auth().signIn(with: credential)
        } catch {
            let nsError = error as NSError
            if nsError.domain != kGIDSignInErrorDomain || nsError.code != GIDSignInError.canceled.rawValue {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Password Reset

    func resetPassword(email: String) async -> Bool {
        isLoading = true
        defer { isLoading = false }
        do {
            try await Auth.auth().sendPasswordReset(withEmail: email)
            return true
        } catch {
            errorMessage = authErrorMessage(from: error)
            return false
        }
    }

    // MARK: - Profile Update

    // Driver license is stored separately from the public profile fields.
    // It lives only in LocalProfile (UserDefaults) for now — kept off Firestore
    // to avoid syncing personal ID numbers to the cloud until we have a
    // compelling reason to (e.g., cross-device retrieval).
    func updateDriverLicense(number: String, state: String, expiryDate: Date?) {
        guard case .authenticated(var user) = authState,
              let firebaseUser = Auth.auth().currentUser else { return }

        let trimmedNumber = number.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedState = state.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        var profile = LocalProfile.load(uid: firebaseUser.uid)
        profile.driverLicenseNumber = trimmedNumber
        profile.driverLicenseState = trimmedState
        profile.driverLicenseExpiryDate = expiryDate
        profile.save(uid: firebaseUser.uid)

        user.driverLicenseNumber = trimmedNumber
        user.driverLicenseState = trimmedState
        user.driverLicenseExpiryDate = expiryDate
        authState = .authenticated(user)
    }

    func updateProfile(displayName: String, username: String, bio: String, location: String, avatarFileName: String? = nil) {
        guard case .authenticated(var user) = authState,
              let firebaseUser = Auth.auth().currentUser else { return }
        let uid = firebaseUser.uid

        let changeRequest = firebaseUser.createProfileChangeRequest()
        changeRequest.displayName = displayName
        changeRequest.commitChanges(completion: nil)

        var profile = LocalProfile.load(uid: uid)
        profile.username = username
        profile.bio = bio
        profile.location = location
        if let avatarFileName { profile.avatarFileName = avatarFileName }
        profile.save(uid: uid)

        // Update the in-memory user immediately so SwiftUI re-renders the avatar
        // this frame. UserAvatar tries ImageManager.loadImage(fileName:) first,
        // so a filename value works for instant local display while the cloud
        // upload runs in the background below.
        user.displayName = displayName
        user.username = username
        user.bio = bio
        user.location = location
        if let avatarFileName { user.avatarURL = avatarFileName }
        authState = .authenticated(user)

        // Sync non-avatar fields to Firestore right away. When the avatar
        // changed, defer the avatarURL write until we have the Storage URL —
        // writing the stale storage URL here would immediately overwrite the
        // fresh one from the background upload.
        // Username and isPro are intentionally excluded: username needs the
        // atomic claim in completeProfileSetup, isPro is owned by SubscriptionStore.
        var firestorePayload: [String: Any] = [
            "displayName": displayName,
            "bio": bio,
        ]
        if avatarFileName == nil {
            firestorePayload["avatarURL"] = profile.avatarStorageURL ?? firebaseUser.photoURL?.absoluteString ?? ""
        }
        userDocument(uid: uid).setData(firestorePayload, merge: true)

        if let avatarFileName {
            Task { await self.uploadAvatarToStorage(uid: uid, fileName: avatarFileName) }
        }
    }

    // Uploads a locally-saved avatar to Firebase Storage, then reconciles the
    // storage URL to LocalProfile, Firestore, Firebase Auth's photoURL, and
    // the in-memory AppUser. On failure the local image stays visible; the
    // user can retry by saving the profile again.
    private func uploadAvatarToStorage(uid: String, fileName: String) async {
        guard let image = ImageManager.loadImage(fileName: fileName),
              let data = image.jpegData(compressionQuality: 0.8) else { return }
        do {
            let ref = Storage.storage().reference().child("users/\(uid)/avatar.jpg")
            _ = try await ref.putDataAsync(data)
            let url = try await ref.downloadURL()
            let urlString = url.absoluteString

            var stored = LocalProfile.load(uid: uid)
            stored.avatarStorageURL = urlString
            stored.save(uid: uid)

            try? await userDocument(uid: uid).setData(["avatarURL": urlString], merge: true)

            if let firebaseUser = Auth.auth().currentUser, firebaseUser.uid == uid {
                let change = firebaseUser.createProfileChangeRequest()
                change.photoURL = url
                try? await change.commitChanges()
            }

            // Swap the in-memory user's avatarURL to the remote URL so future
            // renders (and any subsequent cache invalidations) prefer the
            // authoritative Storage URL over the local filename.
            if case .authenticated(var current) = self.authState, current.id == uid {
                current.avatarURL = urlString
                self.authState = .authenticated(current)
            }
        } catch {
            // Non-fatal — the local file is still displayed. Log left off to
            // avoid noise; the user can retry from Edit Profile.
        }
    }

    // MARK: - Profile Setup

    func checkUsernameAvailability(_ username: String) async -> Bool {
        do {
            let doc = try await usernameDocument(username).getDocument()
            if let uid = doc.data()?["uid"] as? String { return uid == currentUser?.id }
            return !doc.exists
        } catch {
            // Optimistically allow — server-side check in completeProfileSetup is the real guard.
            return true
        }
    }

    func completeProfileSetup(displayName: String, username: String, bio: String, avatarImage: UIImage?) async throws {
        guard let firebaseUser = Auth.auth().currentUser else { return }
        let uid = firebaseUser.uid

        // Check username availability BEFORE uploading anything to avoid orphaned Storage files.
        let usernameRef = usernameDocument(username)
        let existing = try await usernameRef.getDocument()
        if let existingUID = existing.data()?["uid"] as? String, existingUID != uid {
            throw ProfileSetupError.usernameTaken
        }

        var avatarStorageURL: String? = nil
        let changeRequest = firebaseUser.createProfileChangeRequest()
        if !displayName.isEmpty { changeRequest.displayName = displayName }

        if let image = avatarImage, let data = image.jpegData(compressionQuality: 0.8) {
            let ref = Storage.storage().reference().child("users/\(uid)/avatar.jpg")
            _ = try await ref.putDataAsync(data)
            let url = try await ref.downloadURL()
            avatarStorageURL = url.absoluteString
            changeRequest.photoURL = url
        }
        try await changeRequest.commitChanges()

        let resolvedDisplayName = displayName.isEmpty ? (firebaseUser.displayName ?? "User") : displayName

        let batch = db.batch()
        batch.setData(["uid": uid], forDocument: usernameRef)
        // merge: true is load-bearing, not cosmetic. This screen re-appears on a
        // reinstall or a new device (hasCompletedProfileSetup lives in
        // UserDefaults), and a non-merge setData on an existing profile REMOVES
        // every key it doesn't list — including the server-owned `isPro`.
        // firestore.rules counts removals as affected keys, so that write is
        // now denied outright and profile setup would throw.
        batch.setData([
            "username": username.lowercased(),
            "displayName": resolvedDisplayName,
            "bio": bio,
            "avatarURL": avatarStorageURL ?? firebaseUser.photoURL?.absoluteString ?? "",
            "createdAt": FieldValue.serverTimestamp()
        ], forDocument: userDocument(uid: uid), merge: true)
        try await batch.commit()

        var profile = LocalProfile.load(uid: uid)
        profile.username = username
        profile.bio = bio
        profile.avatarStorageURL = avatarStorageURL
        profile.hasCompletedProfileSetup = true
        profile.save(uid: uid)

        hasCompletedProfileSetup = true
        if case .authenticated(var user) = authState {
            user.displayName = resolvedDisplayName
            user.username = username
            user.bio = bio
            if let avatarStorageURL { user.avatarURL = avatarStorageURL }
            authState = .authenticated(user)
        }
    }

    // MARK: - Username Change

    func changeUsername(to newUsername: String) async throws {
        guard let firebaseUser = Auth.auth().currentUser,
              case .authenticated(var user) = authState else { return }

        let uid = firebaseUser.uid
        let trimmed = newUsername.trimmingCharacters(in: .whitespaces).lowercased()
        let currentUsername = user.username.lowercased()
        guard trimmed != currentUsername else { return }

        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        guard trimmed.count >= 3, trimmed.count <= 30,
              trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw ProfileSetupError.invalidUsername
        }

        let newRef = usernameDocument(trimmed)
        let existing = try await newRef.getDocument()
        if let existingUID = existing.data()?["uid"] as? String, existingUID != uid {
            throw ProfileSetupError.usernameTaken
        }

        // Atomic: claim new username, release old, update user doc
        let batch = db.batch()
        batch.setData(["uid": uid], forDocument: newRef)
        if !currentUsername.isEmpty {
            batch.deleteDocument(usernameDocument(currentUsername))
        }
        batch.setData(["username": trimmed], forDocument: userDocument(uid: uid), merge: true)
        try await batch.commit()

        // Update local profile
        var profile = LocalProfile.load(uid: uid)
        profile.username = trimmed
        profile.save(uid: uid)

        user.username = trimmed
        authState = .authenticated(user)

        // Backfill ownerUsername in all public cars (eventually consistent — separate batch)
        if let snapshot = try? await db.collection("publicCars")
            .whereField("ownerUID", isEqualTo: uid)
            .getDocuments(), !snapshot.documents.isEmpty {
            let publicBatch = db.batch()
            for doc in snapshot.documents {
                publicBatch.updateData(["ownerUsername": trimmed], forDocument: doc.reference)
            }
            try? await publicBatch.commit()
        }
    }

    // MARK: - Pro Status

    // Pro state is owned by StoreKit on each device. Firestore `users/{uid}.isPro`
    // is server-controlled (Cloud Function via App Store Server Notifications) — the
    // client must NOT write it directly, as the security rules now reject any such
    // write to prevent paywall bypass. Until Cloud Functions are wired up, cross-device
    // unlock relies on the user tapping "Restore Purchases" on each device.
    func setProStatus(_ isPro: Bool) {
        if case .authenticated(var user) = authState {
            user.isProMember = isPro
            authState = .authenticated(user)
        }
    }

    // Reads isPro from Firestore and promotes the user to Pro if the field is
    // true. Only promotes — never demotes — so StoreKit remains the authority
    // for the current device's active entitlement while Firestore provides the
    // cross-device unlock written by the Cloud Function.
    private func syncProStatusFromFirestore(uid: String) async {
        guard let data = try? await userDocument(uid: uid).getDocument().data(),
              let isPro = data["isPro"] as? Bool,
              isPro else { return }
        setProStatus(true)
    }

    // MARK: - Sign Out

    func signOut() {
        try? Auth.auth().signOut()
    }

    // MARK: - Re-authentication

    func reauthenticate(password: String) async throws {
        guard let firebaseUser = Auth.auth().currentUser,
              let email = firebaseUser.email else { return }
        let credential = EmailAuthProvider.credential(withEmail: email, password: password)
        try await firebaseUser.reauthenticate(with: credential)
    }

    func reauthenticateWithApple() async throws {
        isReauthenticating = true
        defer { isReauthenticating = false }
        try await performAppleSignIn()
    }

    func reauthenticateWithGoogle() async throws {
        guard let clientID = FirebaseApp.app()?.options.clientID else { return }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)

        guard let windowScene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let rootVC = windowScene.keyWindow?.rootViewController else { return }

        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootVC)
        guard let idToken = result.user.idToken?.tokenString else {
            throw NSError(domain: "AuthService", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Google re-auth failed: missing ID token."])
        }
        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: result.user.accessToken.tokenString
        )
        guard let firebaseUser = Auth.auth().currentUser else { return }
        try await firebaseUser.reauthenticate(with: credential)
    }

    // MARK: - Delete Account

    func deleteAccount() async throws {
        guard let firebaseUser = Auth.auth().currentUser else { return }
        let uid = firebaseUser.uid
        let storage = Storage.storage().reference()

        // Collect car documents before deletion — needed to clean up Storage paths.
        let carsSnapshot = try? await db.collection("users").document(uid)
            .collection("cars").getDocuments()

        // 1. Remove this user's entries from the public Explore feed.
        if let snapshot = try? await db.collection("publicCars")
            .whereField("ownerUID", isEqualTo: uid).getDocuments(),
           !snapshot.documents.isEmpty {
            let batch = db.batch()
            snapshot.documents.prefix(500).forEach { batch.deleteDocument($0.reference) }
            try? await batch.commit()
        }

        // 2. Release the username so another user can claim it.
        if let username = currentUser?.username.lowercased(), !username.isEmpty {
            try? await db.collection("usernames").document(username).delete()
        }

        // 3. Fan-out relationship cleanup: remove this user from the followers
        //    subcollection of every user they follow (users/{followedUID}/followers/{uid}).
        //    Permitted because the followers/{followerId} rule binds
        //    request.auth.uid == followerId and we ARE the follower.
        //
        //    The mirror direction (users/{followerUID}/following/{uid}) is NOT done here:
        //    the following/{followedId} rule binds the path owner, not the deleting user,
        //    so it is denied. onAuthUserDeleted removes those reverse pointers with the
        //    Admin SDK. Do not widen that rule — it would let any user delete other
        //    people's follow relationships.
        if let followingSnap = try? await db.collection("users").document(uid)
            .collection("following").getDocuments(),
           !followingSnap.documents.isEmpty {
            let batch = db.batch()
            for doc in followingSnap.documents.prefix(500) {
                batch.deleteDocument(
                    db.collection("users").document(doc.documentID)
                        .collection("followers").document(uid)
                )
            }
            try? await batch.commit()
        }

        // 4. Delete the subcollections under users/{uid} that the rules actually let
        //    the owner delete, so the user sees their data disappear immediately.
        //    Deliberately EXCLUDES:
        //      followers/     — rule binds followerId, not the owner → denied
        //      notifications/ — rule grants read/update/create only  → denied
        //      usage/         — `allow write: if false` (server-only) → denied
        //    Listing a denied path still costs a billed read per document and produces
        //    zero writes, so those paths are left entirely to onAuthUserDeleted, which
        //    recursively deletes users/{uid} and everything beneath it with the Admin SDK.
        //
        //    ALSO deliberately excludes following/ — even though the owner CAN delete it.
        //    onAuthUserDeleted reads users/{uid}/following in its read phase to clean the
        //    reverse pointers under other users' documents. This step runs before
        //    firebaseUser.delete() fires that trigger, so deleting the list here destroys
        //    the server's only record of which pointers need cleanup. Step 3a above
        //    normally handles them first, but its commit is wrapped in `try?` — if it
        //    fails, the server is the sole remaining recovery path and needs this list
        //    intact. recursiveDelete removes it server-side anyway.
        for sub in ["cars", "blocked"] {
            if let snapshot = try? await db.collection("users").document(uid)
                .collection(sub).getDocuments(), !snapshot.documents.isEmpty {
                let batch = db.batch()
                snapshot.documents.prefix(500).forEach { batch.deleteDocument($0.reference) }
                try? await batch.commit()
            }
        }

        // 4a. Delete Marque Assistant conversations and their message subcollections
        //     (PRD FR-10.15, EC-22). Firestore doesn't cascade subcollections, so
        //     each conversation's messages must be batch-deleted BEFORE the parent
        //     conversation doc is removed. Best-effort: any per-conversation
        //     failure is logged-and-continued so it doesn't block the wider cascade.
        if let convSnap = try? await db.collection("users").document(uid)
            .collection("conversations").getDocuments(), !convSnap.documents.isEmpty {
            for convDoc in convSnap.documents {
                let messagesRef = convDoc.reference.collection("messages")
                // Page through messages 500 at a time — a busy conversation can
                // exceed a single WriteBatch's 500-op limit.
                while let msgSnap = try? await messagesRef.limit(to: 500).getDocuments(),
                      !msgSnap.documents.isEmpty {
                    let batch = db.batch()
                    msgSnap.documents.forEach { batch.deleteDocument($0.reference) }
                    guard (try? await batch.commit()) != nil else { break }
                    if msgSnap.documents.count < 500 { break }
                }
                // Delete the conversation doc only after its messages are gone.
                try? await convDoc.reference.delete()
            }
        }

        // 5. The users/{uid} profile document is deleted SERVER-SIDE by
        //    onAuthUserDeleted, not here. `match /users/{userId}` grants
        //    `allow create, update` only, and Firestore decomposes `write` into
        //    create/update/delete — enumerating create+update DENIES delete, so a
        //    client-side delete here would always fail. Do not widen that rule: it
        //    would let someone wipe their profile while leaving server-only usage/
        //    data behind. The Cloud Function reads `username` off this document
        //    before deleting it, so the usernames/{username} reservation in step 2
        //    is released even if this client cascade is interrupted — but only if
        //    the interruption happens AFTER step 7's firebaseUser.delete() call
        //    succeeds. onAuthUserDeleted is an Auth trigger: it never fires (and
        //    the reservation is never released) if this cascade dies before that
        //    call, including if step 2 itself failed and the app crashes or the
        //    network drops before reaching step 7.

        // 6. Delete Storage files (best-effort — failures don't block account deletion).
        storage.child("users/\(uid)/avatar.jpg").delete(completion: nil)
        for doc in carsSnapshot?.documents ?? [] {
            let carId = doc.documentID
            let fileNames = (doc.data()["photoFileNames"] as? [String]) ?? []
            for fileName in fileNames {
                storage.child("users/\(uid)/cars/\(carId)/\(fileName)").delete(completion: nil)
            }
        }

        // 7. Delete the Firebase Auth account.
        //    Throws AuthErrorCode.requiresRecentLogin if the credential is stale.
        try await firebaseUser.delete()

        // 8. Clear local caches (auth state listener fires automatically after step 7,
        //    transitioning the app to .unauthenticated — these are belt-and-suspenders).
        UserDefaults.standard.removeObject(forKey: "marque_profile_\(uid)")
        UserDefaults.standard.removeObject(forKey: "marque_saved_cars_\(uid)")
        UserDefaults.standard.removeObject(forKey: "marque_pending_uploads_\(uid)")
    }

    // MARK: - Helpers

    private func authErrorMessage(from error: Error) -> String {
        let code = AuthErrorCode(_bridgedNSError: error as NSError)
        switch code {
        case .wrongPassword, .invalidCredential:
            return "Incorrect email or password."
        case .invalidEmail:
            return "Please enter a valid email address."
        case .emailAlreadyInUse:
            return "An account with this email already exists."
        case .weakPassword:
            return "Password must be at least 8 characters."
        case .userNotFound:
            return "No account found with this email."
        case .networkError:
            return "Network error. Please check your connection."
        default:
            return error.localizedDescription
        }
    }

    private func randomNonceString(length: Int = 32) -> String {
        var randomBytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(randomBytes.map { byte in charset[Int(byte) % charset.count] })
    }

    private func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .compactMap { String(format: "%02x", $0) }
            .joined()
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension AuthService: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard
            let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let idTokenData = credential.identityToken,
            let idToken = String(data: idTokenData, encoding: .utf8)
        else {
            Task { @MainActor in self.appleCompletion?.resume(throwing: URLError(.badServerResponse)) }
            return
        }

        Task {
            do {
                let firebaseCredential = OAuthProvider.appleCredential(
                    withIDToken: idToken,
                    rawNonce: await self.currentNonce,
                    fullName: credential.fullName
                )
                if await self.isReauthenticating {
                    try await Auth.auth().currentUser?.reauthenticate(with: firebaseCredential)
                } else {
                    try await Auth.auth().signIn(with: firebaseCredential)
                }
                await MainActor.run {
                    self.appleSignInController = nil
                    self.appleCompletion?.resume()
                }
            } catch {
                await MainActor.run {
                    self.appleSignInController = nil
                    self.appleCompletion?.resume(throwing: error)
                }
            }
        }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        Task { @MainActor in
            self.appleSignInController = nil
            self.appleCompletion?.resume(throwing: error)
        }
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding

extension AuthService: ASAuthorizationControllerPresentationContextProviding {
    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
                .flatMap { $0.keyWindow } ?? UIWindow()
        }
    }
}

// MARK: - LocalProfile
// Local cache for fields Firestore owns. Written on profile setup and profile edits.

private struct LocalProfile: Codable {
    var username: String
    var bio: String
    var location: String
    var avatarFileName: String?
    var avatarStorageURL: String?
    var hasCompletedProfileSetup: Bool
    var driverLicenseNumber: String
    var driverLicenseState: String
    var driverLicenseExpiryDate: Date?

    init(username: String = "", bio: String = "", location: String = "",
         avatarFileName: String? = nil, avatarStorageURL: String? = nil,
         hasCompletedProfileSetup: Bool = false,
         driverLicenseNumber: String = "",
         driverLicenseState: String = "",
         driverLicenseExpiryDate: Date? = nil) {
        self.username = username
        self.bio = bio
        self.location = location
        self.avatarFileName = avatarFileName
        self.avatarStorageURL = avatarStorageURL
        self.hasCompletedProfileSetup = hasCompletedProfileSetup
        self.driverLicenseNumber = driverLicenseNumber
        self.driverLicenseState = driverLicenseState
        self.driverLicenseExpiryDate = driverLicenseExpiryDate
    }

    // Backward-compatible decode — older records without the license fields
    // still decode cleanly.
    private enum CodingKeys: String, CodingKey {
        case username, bio, location, avatarFileName, avatarStorageURL
        case hasCompletedProfileSetup
        case driverLicenseNumber, driverLicenseState, driverLicenseExpiryDate
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        username = try c.decodeIfPresent(String.self, forKey: .username) ?? ""
        bio = try c.decodeIfPresent(String.self, forKey: .bio) ?? ""
        location = try c.decodeIfPresent(String.self, forKey: .location) ?? ""
        avatarFileName = try c.decodeIfPresent(String.self, forKey: .avatarFileName)
        avatarStorageURL = try c.decodeIfPresent(String.self, forKey: .avatarStorageURL)
        hasCompletedProfileSetup = try c.decodeIfPresent(Bool.self, forKey: .hasCompletedProfileSetup) ?? false
        driverLicenseNumber = try c.decodeIfPresent(String.self, forKey: .driverLicenseNumber) ?? ""
        driverLicenseState = try c.decodeIfPresent(String.self, forKey: .driverLicenseState) ?? ""
        driverLicenseExpiryDate = try c.decodeIfPresent(Date.self, forKey: .driverLicenseExpiryDate)
    }

    static func load(uid: String) -> LocalProfile {
        guard
            let data = UserDefaults.standard.data(forKey: "marque_profile_\(uid)"),
            let profile = try? JSONDecoder().decode(LocalProfile.self, from: data)
        else { return LocalProfile() }
        return profile
    }

    func save(uid: String) {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: "marque_profile_\(uid)")
        }
    }
}

enum ProfileSetupError: LocalizedError {
    case usernameTaken
    case invalidUsername

    var errorDescription: String? {
        switch self {
        case .usernameTaken:    return "That username is already taken. Please choose another."
        case .invalidUsername:  return "Username must be 3–30 characters, letters, numbers and underscores only."
        }
    }
}

