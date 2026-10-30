import SwiftUI

/// "Popular now" row: up to 6 (make, model) groups drawn from the cars
/// currently loaded in the feed with 2+ public cars, shown under the
/// category chips. Hidden entirely when no group qualifies -- expected
/// with a small seed dataset (see `ExploreView`).
///
/// Tapping a chip narrows the feed in place to that model via a
/// temporary filter (`ExploreView.modelFilter`) rather than navigating
/// into Search: it's a single tap, keeps the user on the feed they're
/// already scrolling, and mirrors the interaction they just used on the
/// category chips directly above this row. `ActiveModelFilterChip` below
/// is what replaces this row once a model is selected, so clearing it is
/// just as cheap.
struct PopularModelsRow: View {
    let groups: [CarTaxonomy.PopularModelGroup]
    let onSelect: (CarTaxonomy.PopularModelGroup) -> Void

    var body: some View {
        if !groups.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(groups) { group in
                        Button {
                            onSelect(group)
                        } label: {
                            Text("🔥 \(group.model) · \(group.count)")
                                .font(.subheadline).fontWeight(.medium)
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(Color(.systemGray6))
                                .foregroundColor(.primary)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule().stroke(Color.primary.opacity(0.06), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

/// Single active model-filter chip ("✕ GT-R") shown in place of
/// `PopularModelsRow` once a model has been tapped. Tapping it clears the
/// filter, which brings the popular row back on the next body evaluation.
struct ActiveModelFilterChip: View {
    let group: CarTaxonomy.PopularModelGroup
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onClear) {
                HStack(spacing: 6) {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.semibold))
                    Text(group.model)
                        .font(.subheadline).fontWeight(.semibold)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Color.accentColor)
                .foregroundColor(.white)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Clear \(group.model) filter")

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - Suggested owners

/// "People to follow" for the empty Following tab: owners of public cars the
/// user doesn't follow yet (never themselves), most-liked first. Each row opens
/// the owner's profile; the button follows without leaving Explore.
struct SuggestedOwnersSection: View {
    let cars: [PublicCar]
    var onOpenOwner: (_ uid: String, _ username: String) -> Void

    @EnvironmentObject private var followStore: FollowStore
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var exploreStore: ExploreStore

    private struct Suggestion: Identifiable {
        let uid: String
        let username: String
        let avatarURL: String?
        let carCount: Int
        let likes: Int
        let topCar: String
        var id: String { uid }
    }

    private var myUID: String? { authService.currentUser?.id }

    private var suggestions: [Suggestion] {
        let byOwner = Dictionary(grouping: cars, by: \.ownerUID)
        return byOwner.compactMap { uid, owned -> Suggestion? in
            guard uid != myUID, !followStore.isFollowing(uid),
                  let top = owned.max(by: { $0.likeCount < $1.likeCount }) else { return nil }
            return Suggestion(uid: uid, username: top.ownerUsername, avatarURL: top.ownerAvatarURL,
                              carCount: owned.count, likes: owned.reduce(0) { $0 + $1.likeCount },
                              topCar: top.displayName)
        }
        .filter { !$0.username.isEmpty }
        .sorted { ($0.likes, $0.carCount, $1.username) > ($1.likes, $1.carCount, $0.username) }
        .prefix(5)
        .map { $0 }
    }

    var body: some View {
        let list = suggestions
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("People to follow").font(.title3.weight(.bold))
                ForEach(list) { s in
                    HStack(spacing: 12) {
                        Button { onOpenOwner(s.uid, s.username) } label: {
                            HStack(spacing: 12) {
                                OwnerAvatar(avatarURL: s.avatarURL, username: s.username, size: 44)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text("@\(s.username)").font(.subheadline.weight(.semibold)).foregroundColor(.primary)
                                        if exploreStore.isPro(s.uid) { ProBadge() }
                                    }
                                    Text(s.carCount == 1 ? s.topCar : "\(s.topCar) + \(s.carCount - 1) more")
                                        .font(.caption).foregroundColor(.secondary).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                        .buttonStyle(.plain)
                        FollowButton(isFollowing: false) {
                            Task {
                                await followStore.follow(
                                    uid: s.uid,
                                    actorDisplayName: authService.currentUser?.displayName ?? "",
                                    actorUsername: authService.currentUser?.username ?? "",
                                    actorAvatarURL: authService.currentUser?.avatarURL
                                )
                            }
                        }
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
                }
            }
            .padding(.horizontal, 16)
        }
    }
}
