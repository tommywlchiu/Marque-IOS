import SwiftUI

struct NotificationsInboxView: View {
    @EnvironmentObject var notificationStore: NotificationStore

    var body: some View {
        Group {
            if notificationStore.notifications.isEmpty {
                emptyState
            } else {
                notificationList
            }
        }
        .onAppear { notificationStore.clearBadge() }
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

    private func row(for note: AppNotification) -> some View {
        NavigationLink {
            PublicProfileView(
                ownerUID: note.actorUID,
                ownerUsername: note.actorUsername
            )
            // Marking read here is cleaner than a simultaneous gesture on the
            // NavigationLink — a competing TapGesture on the link suppresses the
            // link's own push recogniser, causing the avatar (and row body) to
            // appear unresponsive to navigation.
            .onAppear { notificationStore.markRead(note) }
        } label: {
            NotificationRow(notification: note)
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

    @EnvironmentObject var followStore: FollowStore
    @EnvironmentObject var authService: AuthService
    @State private var showingUnfollowAlert = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            avatar

            VStack(alignment: .leading, spacing: 3) {
                Group {
                    Text(notification.actorDisplayName).fontWeight(.semibold) +
                    Text(" ") +
                    Text(notification.body)
                }
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
