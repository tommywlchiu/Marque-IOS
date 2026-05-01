import SwiftUI

// MARK: - Primary Button

struct MarquePrimaryButton: View {
    let title: String
    let isLoading: Bool
    let action: () -> Void

    init(_ title: String, isLoading: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.isLoading = isLoading
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                if isLoading {
                    ProgressView().tint(.white)
                } else {
                    Text(title).fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
        }
        .buttonStyle(.borderedProminent)
        .disabled(isLoading)
    }
}

// MARK: - Social Sign-In Button

struct SocialSignInButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.body)
                Text(label)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
        }
        .buttonStyle(.bordered)
        .tint(.primary)
    }
}

// MARK: - Empty State

struct MarqueEmptyState: View {
    let icon: String
    let title: String
    let subtitle: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(.systemGray6))
                    .frame(width: 100, height: 100)
                Image(systemName: icon)
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary.opacity(0.6))
            }

            VStack(spacing: 8) {
                Text(title)
                    .font(.title3).fontWeight(.bold)
                Text(subtitle)
                    .font(.subheadline).foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, 40)
    }
}

// MARK: - Error Banner

struct MarqueErrorBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(.red)
            Text(message)
                .font(.footnote)
                .foregroundColor(.red)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Section Header with Action

struct MarqueSectionHeader: View {
    let title: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack {
            Text(title)
                .font(.headline).fontWeight(.semibold)
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline)
            }
        }
    }
}

// MARK: - Stat Chip (for profile stats)

struct StatChip: View {
    let value: String
    let label: String
    var action: (() -> Void)? = nil

    var body: some View {
        Button {
            action?()
        } label: {
            VStack(spacing: 2) {
                Text(value)
                    .font(.headline).fontWeight(.bold)
                    .foregroundColor(.primary)
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(minWidth: 64)
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
    }
}

// MARK: - Avatar

struct UserAvatar: View {
    let user: AppUser
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.15))
                .frame(width: size, height: size)

            avatarContent
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    @ViewBuilder
    private var avatarContent: some View {
        if let avatarURL = user.avatarURL, !avatarURL.isEmpty {
            if let localImage = ImageManager.loadImage(fileName: avatarURL) {
                Image(uiImage: localImage)
                    .resizable()
                    .scaledToFill()
            } else if let url = URL(string: avatarURL) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        initialsView
                    }
                }
            } else {
                initialsView
            }
        } else {
            initialsView
        }
    }

    private var initialsView: some View {
        Text(user.displayName.prefix(1).uppercased())
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundColor(.accentColor)
    }
}

// MARK: - Divider with label

struct LabeledDivider: View {
    let label: String

    var body: some View {
        HStack(spacing: 12) {
            Rectangle().fill(Color(.systemGray4)).frame(height: 1)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize()
            Rectangle().fill(Color(.systemGray4)).frame(height: 1)
        }
    }
}

// MARK: - Pro Badge

struct ProBadge: View {
    var body: some View {
        Text("PRO")
            .font(.caption2).fontWeight(.bold)
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.accentColor)
            .clipShape(Capsule())
    }
}

// MARK: - Follow Button

struct FollowButton: View {
    let isFollowing: Bool
    let action: () -> Void

    var body: some View {
        if isFollowing {
            Button(action: action) { label }
                .buttonStyle(.bordered)
                .tint(.secondary)
        } else {
            Button(action: action) { label }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
        }
    }

    private var label: some View {
        Text(isFollowing ? "Following" : "Follow")
            .font(.subheadline).fontWeight(.semibold)
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
    }
}
