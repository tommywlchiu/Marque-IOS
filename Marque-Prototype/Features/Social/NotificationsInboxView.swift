import SwiftUI

struct NotificationsInboxView: View {
    @EnvironmentObject var socialStore: SocialStore

    private var todayNotifications: [AppNotification] {
        let cal = Calendar.current
        return socialStore.notifications.filter { cal.isDateInToday($0.createdAt) }
    }

    private var earlierNotifications: [AppNotification] {
        let cal = Calendar.current
        return socialStore.notifications.filter { !cal.isDateInToday($0.createdAt) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if socialStore.notifications.isEmpty {
                    emptyState
                } else {
                    notificationList
                }
            }
            .navigationTitle("Notifications")
            .toolbar {
                if socialStore.unreadCount > 0 {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Mark All Read") {
                            withAnimation { socialStore.markAllRead() }
                        }
                        .font(.subheadline)
                    }
                }
            }
        }
    }

    // MARK: - List

    private var notificationList: some View {
        List {
            if !todayNotifications.isEmpty {
                Section("Today") {
                    ForEach(todayNotifications) { note in
                        NotificationRow(notification: note)
                            .listRowBackground(note.isRead ? Color.clear : Color.accentColor.opacity(0.06))
                            .onTapGesture { socialStore.markRead(note) }
                    }
                }
            }

            if !earlierNotifications.isEmpty {
                Section("Earlier") {
                    ForEach(earlierNotifications) { note in
                        NotificationRow(notification: note)
                            .listRowBackground(note.isRead ? Color.clear : Color.accentColor.opacity(0.06))
                            .onTapGesture { socialStore.markRead(note) }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        MarqueEmptyState(
            icon: "bell.slash",
            title: "No Notifications",
            subtitle: "When someone likes, comments, or follows you, it will appear here."
        )
    }
}

// MARK: - Notification Row

private struct NotificationRow: View {
    let notification: AppNotification

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                UserAvatar(user: notification.actor, size: 44)
                typeIcon
                    .offset(x: 2, y: 2)
            }

            VStack(alignment: .leading, spacing: 3) {
                Group {
                    Text(notification.actor.displayName).fontWeight(.semibold) +
                    Text(" ") +
                    Text(notification.body)
                }
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)

                Text(notification.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 0)

            if !notification.isRead {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var typeIcon: some View {
        let (icon, color) = iconInfo
        ZStack {
            Circle()
                .fill(color)
                .frame(width: 20, height: 20)
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
        }
    }

    private var iconInfo: (String, Color) {
        switch notification.type {
        case .like:    return ("heart.fill", .red)
        case .comment: return ("bubble.right.fill", .accentColor)
        case .follow:  return ("person.fill.badge.plus", .green)
        case .mention: return ("at", .orange)
        }
    }
}

#Preview {
    NotificationsInboxView()
        .environmentObject(SocialStore())
}
