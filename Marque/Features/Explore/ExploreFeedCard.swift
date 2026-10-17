import SwiftUI

/// Explore's main feed card: one full-width, Instagram-style card per public
/// car. The caller wraps this in a `NavigationLink` to the car's detail page
/// (matching the old grid cell's pattern) — everything here that isn't its
/// own `Button` (the owner header, the like button) falls through to that
/// outer tap target, which is how the photo, name, and comment count all
/// "open the car page" without extra plumbing.
struct ExploreFeedCard: View {
    let car: PublicCar
    /// Shows the PRO badge by the owner's name (`ExploreStore.isPro`).
    var ownerIsPro = false
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
                if ownerIsPro { ProBadge() }
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
            HStack(spacing: 6) {
                Text(car.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                if car.isModified {
                    modifiedTag
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(car.displayName) by @\(car.ownerUsername), \(likesAccessibilityText)\(car.isModified ? ", modified" : "")")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens car details")
    }

    private var likesAccessibilityText: String {
        car.likeCount == 1 ? "1 like" : "\(car.likeCount) likes"
    }

    /// Subtle "🔧 N mods" tag next to the name — deliberately not a loud
    /// badge like `ExploreNewBadge`, since being modified is common rather
    /// than a rare highlight. Hidden from VoiceOver: folded into
    /// `photoAndName`'s own combined accessibility label above.
    private var modifiedTag: some View {
        Text("🔧 \(car.mods.count) mod\(car.mods.count == 1 ? "" : "s")")
            .font(.caption2.weight(.semibold))
            .foregroundColor(.secondary)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(Color(.systemGray6)))
            .lineLimit(1)
            .layoutPriority(1)
            .accessibilityHidden(true)
    }

    /// Fixed 4:5 frame for every photo card so they line up. A car with no
    /// photo gets a shorter 4:3 studio-render panel instead: a screen-tall
    /// placeholder buried the real photos around it.
    private var photoSection: some View {
        Color.clear
            .aspectRatio(car.galleryURLs.isEmpty ? 4.0 / 3.0 : 4.0 / 5.0, contentMode: .fit)
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
            ExploreNoPhotoPlaceholder(make: car.make, model: car.model, car: car)
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

/// Cover for a public car with no photos: its studio render in the owner's
/// paint color on the Garage's charcoal, so a photo-less card looks like the
/// rest of the app. Falls back to the accent-tinted car glyph while the
/// render loads, or when the catalog has nothing for the car. Pass `car`
/// to get the render; without it (the share-card image, which renders
/// synchronously) you get the glyph. Also used (smaller) by `TopCarsSection`.
struct ExploreNoPhotoPlaceholder: View {
    let make: String
    let model: String
    var car: PublicCar?
    var iconSize: CGFloat = 52
    var showsLabel: Bool = true

    @State private var render: UIImage?

    private var label: String {
        [make, model].filter { !$0.isEmpty }.joined(separator: " ")
    }

    var body: some View {
        Group {
            if let render {
                studio(render)
            } else {
                glyph
            }
        }
        .task(id: renderKey) {
            guard let car else { return }
            if let cached = CarRenderLibrary.cachedStill(for: car) {
                render = cached
            } else {
                render = await CarRenderLibrary.still(for: car)
            }
        }
        .accessibilityHidden(true)
    }

    private var renderKey: String {
        guard let car else { return "" }
        return [car.make, car.model, car.year, car.color, car.bodyStyle].joined(separator: "|")
    }

    private func studio(_ image: UIImage) -> some View {
        ZStack {
            GarageTheme.background
            RadialGradient(
                colors: [Color.white.opacity(0.10), .clear],
                center: .center, startRadius: 0, endRadius: 220
            )
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .padding(showsLabel ? 18 : 6)
        }
    }

    private var glyph: some View {
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
    }
}
