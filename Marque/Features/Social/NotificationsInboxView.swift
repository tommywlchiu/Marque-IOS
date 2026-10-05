import SwiftUI

struct NotificationsInboxView: View {
    @EnvironmentObject var notificationStore: NotificationStore
    @EnvironmentObject var carStore: CarStore
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var appDelegate: AppDelegate
    @Environment(\.dismiss) private var dismiss

    /// Actor profile opened from a row's avatar (the row itself opens the car).
    @State private var actorProfile: UserRef?
    @State private var blockTarget: UserRef?

    var body: some View {
        Group {
            if notificationStore.notifications.isEmpty {
                emptyState
            } else {
                notificationList
            }
        }
        .onAppear { notificationStore.clearBadge() }
        .navigationDestination(item: $actorProfile) { user in
            PublicProfileView(ownerUID: user.uid, ownerUsername: user.username)
        }
        .modifier(BlockUserConfirmation(target: $blockTarget))
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if notificationStore.unreadCount > 0 {
                ToolbarItem(placement: .primaryAction) {
                    Button("Mark All Read") {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            notificationStore.markAllRead()
                        }
                    }
                    .font(.subheadline)
                }
            }
        }
    }

    // MARK: - List

    private var notificationList: some View {
        List {
            ForEach(NotificationTimeGroup.allCases) { group in
                let items = group.items(from: notificationStore.notifications)
                if !items.isEmpty {
                    Section {
                        ForEach(items) { note in
                            row(for: note)
                        }
                    } header: {
                        Text(group.title)
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(.secondary)
                            .textCase(nil)
                    }
                }
            }
        }
        .listStyle(.plain)
        .refreshable {
            await notificationStore.refresh()
        }
        .animation(.easeInOut(duration: 0.25), value: notificationStore.notifications)
    }

    /// The recipient's own car a like/comment is about, if it's still in the garage.
    private func car(for note: AppNotification) -> Car? {
        guard note.type == .like || note.type == .comment, let id = note.carID else { return nil }
        return carStore.cars.first(where: { $0.id.uuidString == id })
    }

    /// A like/comment on the user's own car opens that car in the Garage
    /// (comments on its Public Sharing screen), the same route as tapping the
    /// push itself — `MainTabView` switches to the Garage on `pendingCarID`.
    private func openInGarage(_ car: Car, for note: AppNotification) {
        notificationStore.markRead(note)
        appDelegate.pendingPush = AppDelegate.PushRoute(
            kind: note.type == .comment ? .comment : .like,
            actorUID: note.actorUID,
            carId: car.id.uuidString,
            commentId: nil
        )
        appDelegate.pendingCarID = car.id
        // Closes the inbox (popped from Explore, or the follow-push sheet) so
        // returning to that tab later shows its root rather than the inbox.
        dismiss()
    }

    @ViewBuilder
    private func rowLink(for note: AppNotification) -> some View {
        let label = NotificationRow(notification: note) {
            notificationStore.markRead(note)
            actorProfile = actorRef(for: note)
        }
        if let car = car(for: note) {
            Button { openInGarage(car, for: note) } label: { label }
                .buttonStyle(.plain)
        } else {
            NavigationLink {
                PublicProfileView(ownerUID: note.actorUID, ownerUsername: note.actorUsername)
                // Marking read here is cleaner than a simultaneous gesture on the
                // NavigationLink — a competing TapGesture on the link suppresses the
                // link's own push recogniser, causing the avatar (and row body) to
                // appear unresponsive to navigation.
                .onAppear { notificationStore.markRead(note) }
            } label: { label }
        }
    }

    private func row(for note: AppNotification) -> some View {
        rowLink(for: note)
        .contextMenu {
            Button { actorProfile = actorRef(for: note) } label: {
                Label("View @\(note.actorUsername)", systemImage: "person.crop.circle")
            }
            if note.actorUID != authService.currentUser?.id {
                Button(role: .destructive) { blockTarget = actorRef(for: note) } label: {
                    Label("Block @\(note.actorUsername)", systemImage: "person.crop.circle.badge.minus")
                }
            }
        }
        .listRowBackground(note.isRead ? Color.clear : Color.accentColor.opacity(0.07))
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                Task { await notificationStore.delete(note) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func actorRef(for note: AppNotification) -> UserRef {
        UserRef(uid: note.actorUID, username: note.actorUsername)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        MarqueEmptyState(
            icon: "bell.slash",
            title: "No Notifications",
            subtitle: "When someone follows you or interacts with your cars, it will appear here."
        )
    }
}

// MARK: - Time grouping

private enum NotificationTimeGroup: CaseIterable, Identifiable {
    case today, thisWeek, earlier

    var id: Self { self }

    var title: String {
        switch self {
        case .today:    return "Today"
        case .thisWeek: return "This Week"
        case .earlier:  return "Earlier"
        }
    }

    func items(from notifications: [AppNotification]) -> [AppNotification] {
        let cal = Calendar.current
        let now = Date()
        // Anchor the week window to the start of "today" so notifications from
        // yesterday at any hour still bucket into "This Week" correctly.
        let startOfToday = cal.startOfDay(for: now)
        let weekStart = cal.date(byAdding: .day, value: -7, to: startOfToday) ?? startOfToday

        return notifications.filter { note in
            switch self {
            case .today:
                return cal.isDateInToday(note.createdAt)
            case .thisWeek:
                return !cal.isDateInToday(note.createdAt) && note.createdAt >= weekStart
            case .earlier:
                return note.createdAt < weekStart
            }
        }
    }
}

// MARK: - Notification Row

private struct NotificationRow: View {
    let notification: AppNotification
    /// Opens the actor's profile. Separate from the row's own tap, which
    /// opens the car for likes and comments.
    let onActorTap: () -> Void

    @EnvironmentObject var followStore: FollowStore
    @EnvironmentObject var authService: AuthService
    @State private var showingUnfollowAlert = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // A button inside the NavigationLink label takes its own tap
            // (like FollowButton below), so the row still opens the car.
            Button(action: onActorTap) { avatar }
                .buttonStyle(.borderless)
                .accessibilityHidden(true)  // the name button below covers it

            VStack(alignment: .leading, spacing: 3) {
                // Display name, then the @username, always shown so a display
                // name can't pass as someone else.
                Button(action: onActorTap) { actorName }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("\(notification.actorDisplayName) @\(notification.actorUsername)")
                    .accessibilityHint("Opens their profile")

                Text(bodyText)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)

                Text(relativeLabel(for: notification.createdAt))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 8)

            trailingContent
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .alert("Unfollow @\(notification.actorUsername)?", isPresented: $showingUnfollowAlert) {
            Button("Unfollow", role: .destructive) {
                Task { await followStore.unfollow(uid: notification.actorUID) }
            }
            Button("Cancel", role: .cancel) { }
        }
    }

    // For follow notifications, the trailing slot shows a Follow/Following button.
    // For everything else, it shows the unread dot.
    // Buttons inside a NavigationLink label consume the tap, so tapping Follow
    // never accidentally pushes the profile — only tapping the row body does.
    @ViewBuilder
    private var trailingContent: some View {
        if notification.type == .follow {
            let alreadyFollowing = followStore.isFollowing(notification.actorUID)
            FollowButton(isFollowing: alreadyFollowing, notFollowingLabel: "Follow Back") {
                if alreadyFollowing {
                    showingUnfollowAlert = true
                } else {
                    Task {
                        await followStore.follow(
                            uid: notification.actorUID,
                            actorDisplayName: authService.currentUser?.displayName ?? "",
                            actorUsername: authService.currentUser?.username ?? "",
                            actorAvatarURL: authService.currentUser?.avatarURL
                        )
                    }
                }
            }
        } else if !notification.isRead {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 8, height: 8)
        }
    }

    private var actorName: some View {
        let displayName = notification.actorDisplayName.trimmingCharacters(in: .whitespaces)
        return HStack(spacing: 4) {
            if !displayName.isEmpty {
                Text(displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Text("@\(notification.actorUsername)")
                .font(displayName.isEmpty ? .subheadline.weight(.semibold) : .subheadline)
                .foregroundColor(displayName.isEmpty ? .primary : .secondary)
                .lineLimit(1)
                .layoutPriority(1)
        }
    }

    // Like: "liked your 2015 BMW M3" (caption is the car's name).
    // Comment: "commented: “Clean build!”" (caption is a comment preview).
    private var bodyText: String {
        let caption = notification.caption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch notification.type {
        case .like:
            return caption.isEmpty ? "liked your car." : "liked your \(caption)"
        case .comment:
            return caption.isEmpty ? "commented on your car." : "commented: \u{201C}\(caption)\u{201D}"
        case .follow, .mention:
            return notification.body
        }
    }

    private var avatar: some View {
        ZStack(alignment: .bottomTrailing) {
            OwnerAvatar(
                avatarURL: notification.actorAvatarURL,
                username: notification.actorUsername,
                size: 48
            )
            typeIcon.offset(x: 2, y: 2)
        }
    }

    private var typeIcon: some View {
        let (icon, color) = iconInfo
        return ZStack {
            Circle()
                .fill(color)
                .frame(width: 22, height: 22)
            Circle()
                .stroke(Color(.systemBackground), lineWidth: 2)
                .frame(width: 22, height: 22)
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
        }
    }

    private func relativeLabel(for date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        switch seconds {
        case ..<60:     return "\(max(seconds, 1))s"
        case ..<3600:   return "\(seconds / 60)m"
        case ..<86400:  return "\(seconds / 3600)h"
        case ..<604800: return "\(seconds / 86400)d"
        default:
            let f = DateFormatter()
            f.dateStyle = .medium
            f.timeStyle = .none
            return f.string(from: date)
        }
    }

    private var iconInfo: (String, Color) {
        switch notification.type {
        case .like:    return ("heart.fill", .red)
        case .comment: return ("bubble.right.fill", .accentColor)
        case .follow:  return ("person.fill", .green)
        case .mention: return ("at", .orange)
        }
    }
}
