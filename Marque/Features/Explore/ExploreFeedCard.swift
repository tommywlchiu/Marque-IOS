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

    private static let cornerRadius: CGFloat = 20

    var body: some View {
        // One card (photo or studio render on top, then name, owner and
        // stats) in the same rounded container the hero uses, so the feed
        // reads as a stack of finished objects rather than loose rows.
        VStack(alignment: .leading, spacing: 0) {
            photoAndName
            VStack(alignment: .leading, spacing: 12) {
                ownerHeader
                actionRow
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 14)
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: Self.cornerRadius).strokeBorder(Color.primary.opacity(0.06)))
    }

    // MARK: - Owner header

    private var ownerHeader: some View {
        Button(action: onOwnerTap) {
            HStack(spacing: 10) {
                OwnerAvatar(avatarURL: car.ownerAvatarURL, username: car.ownerUsername, size: 26)
                Text("@\(car.ownerUsername)")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.secondary)
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
        VStack(alignment: .leading, spacing: 0) {
            photoSection
            HStack(spacing: 6) {
                Text(car.displayName)
                    .font(.title3.weight(.bold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if car.isModified {
                    modifiedTag
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
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
            .clipped()
            .overlay(alignment: .topLeading) {
                if car.isNew {
                    ExploreNewBadge().padding(10)
                }
            }
    }

    /// Whether the catalog has a studio render for this car: the last page of
    /// a photo card, so a swipe goes from the owner's photo to the render.
    /// Looked up off the render path (the catalog is a sizeable JSON).
    @State private var hasRender = false

    @ViewBuilder
    private var photoContent: some View {
        let urls = car.galleryURLs
        let pageCount = urls.count + (hasRender ? 1 : 0)
        if urls.isEmpty {
            ExploreNoPhotoPlaceholder(make: car.make, model: car.model, car: car)
        } else if pageCount == 1 {
            singlePhoto(urls[0])
                .task(id: renderKey) { await checkRender() }
        } else {
            ZStack(alignment: .bottom) {
                TabView(selection: $pageIndex) {
                    ForEach(0..<pageCount, id: \.self) { index in
                        // A paged TabView builds every page, so only load the
                        // photo on screen and its neighbours; the rest stay a
                        // cheap placeholder until swiped near.
                        Group {
                            if abs(index - pageIndex) > 1 {
                                Color(.systemGray6)
                            } else if index < urls.count {
                                singlePhoto(urls[index])
                            } else {
                                ExploreNoPhotoPlaceholder(make: car.make, model: car.model, car: car)
                            }
                        }
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                pageIndicator(count: pageCount)
            }
            .task(id: renderKey) { await checkRender() }
        }
    }

    private var renderKey: String {
        [car.make, car.model, car.year, car.color, car.bodyStyle].joined(separator: "|")
    }

    private func checkRender() async {
        let found = CarRenderLibrary.match(make: car.make, model: car.model, year: car.year,
                                           color: car.color, bodyStyle: car.bodyStyle,
                                           in: await CarRenderLibrary.catalog()) != nil
        if found != hasRender { hasRender = found }
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

/// The cover for a public car with no photos, on its detail page: the studio
/// render on the Garage's charcoal, spinnable by dragging once its 36 frames
/// are in (the same turntable as the Garage hero), dressed the way the owner
/// built it (`PublicCar.customization`: wheels, stance, tint, extras, seats,
/// black optic). Shows the still straight away; with no render for the car
/// (or no catalog yet) it falls back to `ExploreNoPhotoPlaceholder`'s glyph.
struct PublicCarSpinCover: View {
    let car: PublicCar

    @State private var still: UIImage?
    @State private var frames: [UIImage]?
    @State private var plates: CarRenderLibrary.PlateTrack?
    @State private var tintMasks: [UIImage]?
    @State private var wheelLayers: [UIImage]?
    @State private var stockWheels: [UIImage]?
    @State private var extras: [RenderedCarSpinView.ExtraLayer] = []
    @State private var seatLayer: [UIImage]?
    @State private var blackOptic: [UIImage]?
    @State private var meter: Double?

    private var build: CarCustomization { car.customization ?? CarCustomization() }

    private var key: String {
        [car.make, car.model, car.year, car.color, car.bodyStyle].joined(separator: "|")
    }

    private var stanceLift: CGFloat {
        guard let meter, stockWheels != nil else { return 0 }
        return CGFloat(build.stance.lift * meter)
    }

    var body: some View {
        Group {
            if let still {
                ZStack {
                    GarageTheme.background
                    RadialGradient(colors: [Color.white.opacity(0.10), .clear],
                                   center: .center, startRadius: 0, endRadius: 240)
                    RenderedCarSpinView(still: still, frames: frames, plates: plates,
                                        tintMasks: tintMasks, tint: build.tint,
                                        wheelLayers: wheelLayers, stockWheels: stockWheels,
                                        stanceLift: stanceLift, extras: extras,
                                        seatLayer: seatLayer, blackOpticLayer: blackOptic)
                        .padding(.horizontal, 8)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Studio render of the \(car.displayName)")
                .accessibilityHint(frames == nil ? "" : "Drag sideways to spin")
            } else {
                ExploreNoPhotoPlaceholder(make: car.make, model: car.model, car: car, iconSize: 40, showsLabel: false)
            }
        }
        .task(id: key + "|" + String(describing: build)) { await load() }
    }

    /// Loads the still first, then each layer the owner's build asks for.
    /// Every layer is optional: one that fails to load just isn't drawn.
    private func load() async {
        guard let match = CarRenderLibrary.match(make: car.make, model: car.model, year: car.year,
                                                 color: car.color, bodyStyle: car.bodyStyle,
                                                 in: await CarRenderLibrary.catalog()) else { return }
        if let cached = CarRenderLibrary.cachedStill(for: match) {
            still = cached
        } else {
            still = await CarRenderLibrary.frame(0, of: match)
        }
        meter = match.meter
        plates = await CarRenderLibrary.plates(of: match)
        if build.tint != .none, match.hasTint {
            tintMasks = await CarRenderLibrary.tintMasks(of: match)
        }
        if let style = build.wheels, match.wheelStyles.contains(style) {
            wheelLayers = await CarRenderLibrary.wheelLayers(of: match, style: style)
        }
        if build.stance != .stock, match.canChangeStance {
            stockWheels = await CarRenderLibrary.wheelLayers(of: match, style: "stock")
        }
        var layers: [RenderedCarSpinView.ExtraLayer] = []
        for extra in build.extras {
            let wantsCarbon = extra == .spoiler && build.spoilerFinish == .carbon && match.extras["spoiler-carbon"] != nil
            let id = wantsCarbon ? "spoiler-carbon" : extra.rawValue
            guard let rect = match.extras[id], let frames = await CarRenderLibrary.extraLayers(of: match, extra: id) else { continue }
            layers.append(.init(rect: rect, frames: frames))
        }
        extras = layers
        if build.seatColor == .standard, match.seats.contains(CarRenderLibrary.blackSeatsLayer) {
            seatLayer = await CarRenderLibrary.seatLayers(of: match, option: CarRenderLibrary.blackSeatsLayer)
        }
        if build.blackOptic, match.hasBlackOptic {
            blackOptic = await CarRenderLibrary.blackOpticLayers(of: match)
        }
        frames = await CarRenderLibrary.allFrames(of: match)
    }
}
