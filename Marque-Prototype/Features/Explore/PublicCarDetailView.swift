import SwiftUI

// Read-only car detail for another user's car, reached from ExploreView.
struct PublicCarDetailView: View {
    let post: Post

    @EnvironmentObject var socialStore: SocialStore

    @State private var showingOwnerProfile = false
    @State private var showingComments = false

    private var car: Car { post.car }
    private var owner: AppUser { post.user }

    // Convenience init for call sites that have a Car + AppUser but no Post
    // (e.g. SearchResultsView). Creates a synthetic post that is not tracked in SocialStore.
    init(car: Car, owner: AppUser) {
        self.post = Post(
            id: "search-\(car.id.uuidString)",
            user: owner,
            car: car,
            caption: "",
            likeCount: 0,
            commentCount: 0,
            isLiked: false,
            createdAt: Date()
        )
    }

    init(post: Post) {
        self.post = post
    }

    // Live like state comes from SocialStore so taps from Explore and this view stay in sync.
    private var livePost: Post {
        socialStore.posts.first(where: { $0.id == post.id }) ?? post
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                photoHeader
                ownerRow
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                Divider()
                specsSection
                maintenanceTeaser
            }
        }
        .navigationTitle(car.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 16) {
                    Button {
                        showingComments = true
                    } label: {
                        Label("\(livePost.commentCount)", systemImage: "bubble.right")
                            .foregroundColor(.primary)
                    }

                    Button {
                        socialStore.toggleLike(postID: post.id)
                    } label: {
                        Label("\(livePost.likeCount)", systemImage: livePost.isLiked ? "heart.fill" : "heart")
                            .foregroundColor(livePost.isLiked ? .red : .primary)
                    }
                }
            }
        }
        .sheet(isPresented: $showingOwnerProfile) {
            NavigationStack { PublicProfileView(user: owner) }
        }
        .sheet(isPresented: $showingComments) {
            CommentsView(post: livePost)
                .environmentObject(socialStore)
        }
    }

    // MARK: - Photo Header

    private var photoHeader: some View {
        ZStack {
            Color.accentColor.opacity(0.08)
            if let fileName = car.primaryPhotoFileName,
               let uiImage = ImageManager.loadImage(fileName: fileName) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "car.fill")
                    .font(.system(size: 72))
                    .foregroundColor(.accentColor.opacity(0.3))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 260)
        .clipped()
    }

    // MARK: - Owner Row

    private var ownerRow: some View {
        Button { showingOwnerProfile = true } label: {
            HStack(spacing: 10) {
                UserAvatar(user: owner, size: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text(owner.displayName)
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundColor(.primary)
                    Text("@\(owner.username)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.5))
            }
        }
    }

    // MARK: - Specs

    private var specsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Specs")
                .font(.headline).fontWeight(.semibold)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 10)

            let specs = specRows
            ForEach(specs.indices, id: \.self) { i in
                let spec = specs[i]
                if !spec.value.isEmpty {
                    HStack {
                        Text(spec.label)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(spec.value)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    if i < specs.count - 1 {
                        Divider().padding(.horizontal, 16)
                    }
                }
            }
        }
    }

    private var specRows: [(label: String, value: String)] {
        [
            ("Make", car.make),
            ("Model", car.model),
            ("Year", car.year),
            ("Trim", car.trim),
            ("Color", car.color),
            ("Body Style", car.bodyStyle),
            ("Drive Type", car.driveType),
            ("Engine", car.engine),
            ("Fuel Type", car.fuelType),
            ("Transmission", car.transmission),
            ("Mileage", car.mileage),
        ]
    }

    // MARK: - Maintenance Teaser

    private var maintenanceTeaser: some View {
        Group {
            if !car.maintenanceRecords.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Divider()
                    HStack {
                        Text("Service History")
                            .font(.headline).fontWeight(.semibold)
                        Spacer()
                        Text("\(car.maintenanceRecords.count) records")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                    ForEach(car.sortedMaintenanceRecords.prefix(3)) { record in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.serviceType)
                                    .font(.subheadline).fontWeight(.medium)
                                Text(record.date, style: .date)
                                    .font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            if let cost = Double(record.cost), cost > 0 {
                                Text("$\(String(format: "%.0f", cost))")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                    }
                }
                .padding(.bottom, 24)
            }
        }
    }
}

#Preview {
    let store = SocialStore()
    return NavigationStack {
        PublicCarDetailView(post: store.posts[0])
    }
    .environmentObject(store)
}
