import SwiftUI

struct ExploreView: View {
    @State private var searchText = ""
    @State private var showingSearch = false
    @State private var selectedCategory: ExploreCategory = .all

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
                    ForEach(ExplorePost.preview) { post in
                        NavigationLink(destination: PublicCarDetailView(car: post.car, owner: post.user)) {
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
                ForEach(ExplorePost.preview.reversed()) { post in
                    NavigationLink(destination: PublicCarDetailView(car: post.car, owner: post.user)) {
                        ExplorePostCard(post: post)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
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
    let post: ExplorePost

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

private struct ExplorePostCard: View {
    let post: ExplorePost

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

            // Actions
            HStack(spacing: 20) {
                Label("\(post.likeCount)", systemImage: post.isLiked ? "heart.fill" : "heart")
                    .foregroundColor(post.isLiked ? .red : .secondary)
                Label("\(post.commentCount)", systemImage: "bubble.right")
                    .foregroundColor(.secondary)
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

// MARK: - Mock Data

struct ExplorePost: Identifiable {
    let id: String
    let user: AppUser
    let car: Car
    let caption: String
    let likeCount: Int
    let commentCount: Int
    let isLiked: Bool
    let createdAt: Date

    static let preview: [ExplorePost] = {
        let cars = CarStore.previewCars
        let users = AppUser.previewFollowers
        return [
            ExplorePost(id: "p1", user: users[0], car: cars[0], caption: "Just got the tires rotated. Running smooth!", likeCount: 48, commentCount: 6, isLiked: false, createdAt: Calendar.current.date(byAdding: .hour, value: -2, to: Date()) ?? Date()),
            ExplorePost(id: "p2", user: users[1], car: cars[1], caption: "Track day prep complete 🔧", likeCount: 122, commentCount: 18, isLiked: true, createdAt: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()),
            ExplorePost(id: "p3", user: users[2], car: cars[2], caption: "Weekend wash day vibes.", likeCount: 77, commentCount: 9, isLiked: false, createdAt: Calendar.current.date(byAdding: .day, value: -2, to: Date()) ?? Date()),
        ]
    }()
}

#Preview {
    ExploreView()
        .environmentObject(AuthService())
}
