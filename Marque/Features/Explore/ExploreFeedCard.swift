import SwiftUI

/// Explore's main feed card: one full-width, Instagram-style card per public
/// car. The caller wraps this in a `NavigationLink` to the car's detail page
/// (matching the old grid cell's pattern) — everything here that isn't its
/// own `Button` (the owner header, the like button) falls through to that
/// outer tap target, which is how the photo, name, and comment count all
/// "open the car page" without extra plumbing.
struct ExploreFeedCard: View {
    let car: PublicCar
    /// Opens the owner's `PublicProfileView`.
    var onOwnerTap: () -> Void
    /// Called after a successful like (not unlike) so the host can offer the
    /// push-permission pre-prompt.
    var onLiked: () -> Void

    @State private var pageIndex = 0

    private static let cornerRadius: CGFloat = 18

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ownerHeader
            photoAndName
            actionRow
        }
    }

    // MARK: - Owner header

    private var ownerHeader: some View {
        Button(action: onOwnerTap) {
            HStack(spacing: 10) {
                OwnerAvatar(avatarURL: car.ownerAvatarURL, username: car.ownerUsername, size: 34)
                Text("@\(car.ownerUsername)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("View @\(car.ownerUsername)'s profile")
    }

    // MARK: - Photo + name
    //
    // One combined VoiceOver element ("2026 Porsche 911 by @kdn, 3 likes"),
    // deliberately excluding the like button below so it reads as a
    // separate action (per the redesign spec).

    private var photoAndName: some View {
        VStack(alignment: .leading, spacing: 8) {
            photoSection
            Text(car.displayName)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.primary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(car.displayName) by @\(car.ownerUsername), \(likesAccessibilityText)")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens car details")
    }

    private var likesAccessibilityText: String {
        car.likeCount == 1 ? "1 like" : "\(car.likeCount) likes"
    }

    /// Fixed 4:5 frame for every photo card so they line up. A car with no
    /// photo gets a shorter 16:9 banner instead: a screen-tall placeholder
    /// buried the real photos around it.
    private var photoSection: some View {
        Color.clear
            .aspectRatio(car.galleryURLs.isEmpty ? 16.0 / 9.0 : 4.0 / 5.0, contentMode: .fit)
            .overlay { photoContent }
            .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
            .overlay(alignment: .topLeading) {
                if car.isNew {
                    ExploreNewBadge().padding(10)
                }
            }
    }

    @ViewBuilder
    private var photoContent: some View {
        let urls = car.galleryURLs
        if urls.isEmpty {
            ExploreNoPhotoPlaceholder(make: car.make, model: car.model)
        } else if urls.count == 1 {
            singlePhoto(urls[0])
        } else {
            ZStack(alignment: .bottom) {
                TabView(selection: $pageIndex) {
                    ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
                        // A paged TabView builds every page, so only load the
                        // photo on screen and its neighbours; the rest stay a
                        // cheap placeholder until swiped near.
                        Group {
                            if abs(index - pageIndex) <= 1 {
                                singlePhoto(url)
                            } else {
                                Color(.systemGray6)
                            }
                        }
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                pageIndicator(count: urls.count)
            }
        }
    }

    /// Center-cropped. `photoOffsetY` is a point offset tuned in the editor's
    /// 180pt-tall banner; in this much taller 4:5 frame the same points shift
    /// the image by a different amount (and a landscape photo has no vertical
    /// overflow at all, so an offset would expose a blank strip).
    private func singlePhoto(_ url: URL) -> some View {
        CachedRemoteImage(url: url)
    }

    private func pageIndicator(count: Int) -> some View {
        HStack(spacing: 5) {
            ForEach(0..<count, id: \.self) { i in
                Circle()
                    .fill(Color.white.opacity(i == pageIndex ? 0.95 : 0.4))
                    .frame(width: 5.5, height: 5.5)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(Capsule().fill(Color.black.opacity(0.28)))
        .padding(.bottom, 10)
        .accessibilityHidden(true)
    }

    // MARK: - Action row

    private var actionRow: some View {
        HStack(spacing: 16) {
            LikeButton(car: car, style: .compact, onLiked: onLiked)

            HStack(spacing: 5) {
                Image(systemName: "bubble.left")
                    .font(.callout)
                    .foregroundColor(.secondary)
                Text(car.commentCount.formatted())
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(car.commentCount == 1 ? "1 comment" : "\(car.commentCount) comments")
            .accessibilityHint("Opens car details")

            Spacer(minLength: 0)

            if let range = car.valueRange, !range.isEmpty {
                Text(range)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.accentColor)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                    .accessibilityLabel("Estimated value \(range)")
            }
        }
        .padding(.horizontal, 2)
    }
}

/// Small accent-colored "NEW" capsule for a car made public in the last 7
/// days (`PublicCar.isNew`). Shared by `ExploreFeedCard` and
/// `CarOfTheWeekHero`, pinned to the photo's top-leading corner in both.
struct ExploreNewBadge: View {
    var body: some View {
        Text("NEW")
            .font(.caption2.weight(.heavy))
            .kerning(0.4)
            .foregroundColor(.white)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(Color.accentColor))
            .accessibilityHidden(true)
    }
}

/// Placeholder for a public car with no photos: a subtle accent-tinted
/// gradient, a car glyph, and the make/model, so a photo-less card still
/// looks finished. Also used (smaller) by `TopCarsSection`'s ranked cards.
struct ExploreNoPhotoPlaceholder: View {
    let make: String
    let model: String
    var iconSize: CGFloat = 52
    var showsLabel: Bool = true

    private var label: String {
        [make, model].filter { !$0.isEmpty }.joined(separator: " ")
    }

    var body: some View {
        LinearGradient(
            colors: [Color.accentColor.opacity(0.24), Color.accentColor.opacity(0.06)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            VStack(spacing: 8) {
                Image(systemName: "car.side.fill")
                    .font(.system(size: iconSize))
                    .foregroundColor(.accentColor.opacity(0.55))
                if showsLabel && !label.isEmpty {
                    Text(label)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.accentColor.opacity(0.75))
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                }
            }
        }
        .accessibilityHidden(true)
    }
}
