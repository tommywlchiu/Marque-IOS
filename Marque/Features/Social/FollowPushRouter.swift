import SwiftUI

/// Routes a tapped "new follower" push (`AppDelegate.pendingPush`, kind
/// `.follow`): the follower's public profile when the inbox knows their
/// username, otherwise the Notifications inbox. Attach to the root of each
/// tab; only the tab on screen acts, and it clears `pendingPush`.
///
/// Like and comment pushes are routed by `CarListView` through
/// `pendingCarID` (the recipient's own car), not here.
struct FollowPushRouter: ViewModifier {
    @EnvironmentObject private var appDelegate: AppDelegate
    @EnvironmentObject private var notificationStore: NotificationStore

    @State private var isOnScreen = false
    @State private var destination: Destination?

    enum Destination: Identifiable {
        case profile(uid: String, username: String)
        case inbox

        var id: String {
            switch self {
            case .profile(let uid, _): return "profile-\(uid)"
            case .inbox: return "inbox"
            }
        }
    }

    func body(content: Content) -> some View {
        content
            .onAppear {
                isOnScreen = true
                route()
            }
            .onDisappear { isOnScreen = false }
            .onChange(of: appDelegate.pendingPush) { _, _ in route() }
            .sheet(item: $destination) { destination in
                FollowPushDestinationView(destination: destination)
            }
    }

    private func route() {
        guard isOnScreen, let push = appDelegate.pendingPush, push.kind == .follow else { return }
        appDelegate.pendingPush = nil
        if let uid = push.actorUID,
           let note = notificationStore.notifications.first(where: { $0.type == .follow && $0.actorUID == uid }),
           !note.actorUsername.isEmpty {
            destination = .profile(uid: uid, username: note.actorUsername)
        } else {
            destination = .inbox
        }
    }
}

private struct FollowPushDestinationView: View {
    let destination: FollowPushRouter.Destination
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                switch destination {
                case .profile(let uid, let username):
                    PublicProfileView(ownerUID: uid, ownerUsername: username)
                case .inbox:
                    NotificationsInboxView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
