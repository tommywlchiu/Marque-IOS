import SwiftUI

struct ExploreView: View {
    @EnvironmentObject var socialStore: SocialStore

    @State private var selectedCategory: ExploreCategory = .all
    @State private var commentPost: Post?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    searchBar
                    categoryPicker
                    featuredSection
                    postsSection
                }
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .navigationTitle("Explore")
            .navigationBarTitleDisplayMode(.large)
            .sheet(item: $commentPost) { post in
                CommentsView(post: post)
                    .environmentObject(socialStore)
            }
        }
    }

    // MARK: - Subviews

    private var searchBar: some View {
        NavigationLink(destination: SearchResultsView()) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                Text("Search cars, makes, or people…")
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(height: 42)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
    }

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(ExploreCategory.allCases, id: \.self) { cat in
                    CategoryChip(category: cat, isSelected: selectedCategory == cat) {
                        withAnimation(.spring(duration: 0.25)) {
                            selectedCategory = cat
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var featuredSection: some View {
        VStack(spacing: 12) {
            MarqueSectionHeader(title: "Trending This Week", actionTitle: "See All") { }
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(socialStore.posts) { post in
                        NavigationLink(destination: PublicCarDetailView(post: post)) {
                            FeaturedPostCard(post: post)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private var postsSection: some View {
        VStack(spacing: 12) {
            MarqueSectionHeader(title: "Recent Posts")
                .padding(.horizontal, 16)

            LazyVStack(spacing: 14) {
                ForEach(socialStore.posts.reversed()) { post in
                    // Buttons inside a NavigationLink label receive their own taps first;
                    // only taps on non-interactive areas trigger navigation.
                    NavigationLink {
                        PublicCarDetailView(post: post)
                            .environmentObject(socialStore)
                    } label: {
                        ExplorePostCard(
                            post: post,
                            onLike: { socialStore.toggleLike(postID: post.id) },
                            onComment: { commentPost = post }
                        )
                        .padding(.horizontal, 16)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Category

private enum ExploreCategory: String, CaseIterable {
    case all = "All"
    case jdm = "JDM"
    case european = "European"
    case american = "American"
    case electric = "Electric"
    case classic = "Classic"
    case modified = "Modified"
}

private struct CategoryChip: View {
    let category: ExploreCategory
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(category.rawValue)
                .font(.subheadline).fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? Color.accentColor : Color(.systemGray6))
                .foregroundColor(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
    }
}

// MARK: - Featured Post Card

private struct FeaturedPostCard: View {
    let post: Post

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 220, height: 160)

                Image(systemName: "car.fill")
                    .font(.system(size: 52))
                    .foregroundColor(.accentColor.opacity(0.3))
                    .frame(width: 220, height: 160)

                LinearGradient(
                    colors: [.clear, .black.opacity(0.5)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))

                VStack(alignment: .leading, spacing: 2) {
                    Text(post.car.displayName)
                        .font(.caption).fontWeight(.semibold)
                        .foregroundColor(.white)
                    Text("@\(post.user.username)")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(10)
            }

            HStack(spacing: 12) {
                Label("\(post.likeCount)", systemImage: "heart")
                Label("\(post.commentCount)", systemImage: "bubble.right")
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.horizontal, 4)
        }
        .frame(width: 220)
    }
}

// MARK: - Post Feed Card

struct ExplorePostCard: View {
    let post: Post
    let onLike: () -> Void
    let onComment: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Author row
            HStack(spacing: 10) {
                UserAvatar(user: post.user, size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(post.user.displayName)
                        .font(.subheadline).fontWeight(.semibold)
                    Text("@\(post.user.username)")
                        .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Text(post.createdAt, style: .relative)
                    .font(.caption2).foregroundColor(.secondary)
            }

            // Car photo placeholder
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.accentColor.opacity(0.08))
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                Image(systemName: "car.fill")
                    .font(.system(size: 52))
                    .foregroundColor(.accentColor.opacity(0.3))
            }

            // Caption
            if !post.caption.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(post.car.displayName)
                        .font(.subheadline).fontWeight(.semibold)
                    Text(post.caption)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }

            // Action bar
            HStack(spacing: 20) {
                Button(action: onLike) {
                    Label("\(post.likeCount)", systemImage: post.isLiked ? "heart.fill" : "heart")
                        .foregroundColor(post.isLiked ? .red : .secondary)
                }

                Button(action: onComment) {
                    Label("\(post.commentCount)", systemImage: "bubble.right")
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button { } label: {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundColor(.secondary)
                }
            }
            .font(.subheadline)
        }
        .padding(14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
    }
}

#Preview {
    ExploreView()
        .environmentObject(AuthService())
        .environmentObject(SocialStore())
}
