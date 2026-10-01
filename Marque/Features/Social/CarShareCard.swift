import SwiftUI

/// The two export sizes for the "Share my car" card, matching Instagram's
/// feed post (4:5) and Story/Reel (9:16) canvases.
enum ShareCardFormat: String, CaseIterable, Identifiable, Equatable {
    case post
    case story

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .post: return "Post"
        case .story: return "Story"
        }
    }

    /// Exact output pixel size. `CarShareCard`'s own frame is set to this
    /// size in points, and `ShareCardSheet` renders it via `ImageRenderer`
    /// with `scale = 1`, so points map 1:1 to pixels at export time — see
    /// the CLAUDE.md pitfall on points vs. pixels before changing either.
    var pixelSize: CGSize {
        switch self {
        case .post: return CGSize(width: 1080, height: 1350)
        case .story: return CGSize(width: 1080, height: 1920)
        }
    }
}

/// A pure, fixed-size poster card for the "Share my car" feature (growth —
/// this is the image people post to Instagram/iMessage). Built ONLY from
/// `PublicCar` (the FR-06.3 public projection: no VIN, plate, insurance,
/// exact value, per-record costs or private mod notes) plus a pre-loaded
/// cover photo, so the privacy boundary is structural rather than a rule a
/// caller has to remember — see `ShareCardSheet` for how both the owner's
/// own car and someone else's public car are turned into this input.
///
/// `ImageRenderer` can't await async images, so `coverImage` must already be
/// loaded (`ShareCardSheet` does this before rendering); a nil image falls
/// back to a scaled-up version of Explore's no-photo placeholder style
/// rather than blocking the share.
struct CarShareCard: View {
    let car: PublicCar
    let coverImage: UIImage?
    let format: ShareCardFormat

    private let margin: CGFloat = 72

    private var subtitle: String {
        [car.trim, car.engine].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var visibleMods: [PublicCarMod] { Array(car.mods.prefix(4)) }
    private var remainingModCount: Int { max(0, car.mods.count - visibleMods.count) }

    var body: some View {
        ZStack(alignment: .top) {
            photoLayer
            scrimLayer
            VStack(alignment: .leading, spacing: 0) {
                topRow
                Spacer(minLength: 0)
                bottomContent
            }
            .padding(.horizontal, margin)
            .padding(.top, 64)
            .padding(.bottom, format == .story ? 120 : 64)
        }
        .frame(width: format.pixelSize.width, height: format.pixelSize.height)
        .clipped()
    }

    // MARK: - Photo / placeholder

    @ViewBuilder
    private var photoLayer: some View {
        if let coverImage {
            Image(uiImage: coverImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: format.pixelSize.width, height: format.pixelSize.height)
                .clipped()
        } else {
            placeholderBackground
        }
    }

    /// Photo-less car: the same brand-gradient language as Explore's
    /// `ExploreNoPhotoPlaceholder`, over a near-black base so it still reads
    /// as a designed poster rather than an empty state.
    private var placeholderBackground: some View {
        ZStack {
            Color.black
            LinearGradient(
                colors: [Color.accentColor.opacity(0.28), Color.black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            ExploreNoPhotoPlaceholder(make: car.make, model: car.model, iconSize: 220, showsLabel: false)
        }
        .frame(width: format.pixelSize.width, height: format.pixelSize.height)
    }

    private var scrimLayer: some View {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0.0), location: 0.0),
                .init(color: .black.opacity(0.0), location: 0.38),
                .init(color: .black.opacity(0.55), location: 0.62),
                .init(color: .black.opacity(0.92), location: 1.0),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(width: format.pixelSize.width, height: format.pixelSize.height)
    }

    // MARK: - Top row (corner value badge)

    @ViewBuilder
    private var topRow: some View {
        if let range = car.valueRange, !range.isEmpty {
            HStack {
                Spacer()
                valueBadge(range)
            }
        }
    }

    private func valueBadge(_ text: String) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("EST. VALUE")
                .font(.system(size: 18, weight: .bold))
                .kerning(1.4)
                .foregroundColor(.white.opacity(0.65))
            Text(text)
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.35)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.25), lineWidth: 1.5))
    }

    // MARK: - Bottom content block

    private var bottomContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            if car.isModified {
                modifiedBadge
            }

            Text(car.displayName)
                .font(.system(size: 80, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .minimumScaleFactor(0.5)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .shadow(color: .black.opacity(0.4), radius: 12, y: 4)

            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 34, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !visibleMods.isEmpty {
                modsSection
            }

            if !car.ownerUsername.isEmpty {
                ownerRow
            }

            Rectangle()
                .fill(Color.white.opacity(0.18))
                .frame(height: 1)
                .padding(.top, 4)

            footer
        }
    }

    private var modifiedBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.system(size: 20, weight: .bold))
            Text("MODIFIED")
                .font(.system(size: 22, weight: .heavy))
                .kerning(1.0)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 16).padding(.vertical, 9)
        .background(Capsule().fill(Color.accentColor))
    }

    // MARK: - Mod chips

    private enum ChipItem: Identifiable {
        case mod(PublicCarMod)
        case more(Int)

        var id: String {
            switch self {
            case .mod(let m): return m.id
            case .more: return "more"
            }
        }
    }

    private var chipItems: [ChipItem] {
        var items = visibleMods.map(ChipItem.mod)
        if remainingModCount > 0 { items.append(.more(remainingModCount)) }
        return items
    }

    /// Two chips per row — simple and predictable at a fixed poster width,
    /// rather than a general flow layout for at most 5 items.
    private var chipRows: [[ChipItem]] {
        stride(from: 0, to: chipItems.count, by: 2).map {
            Array(chipItems[$0..<min($0 + 2, chipItems.count)])
        }
    }

    private var modsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(chipRows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 14) {
                    ForEach(row) { chipView($0) }
                }
            }
        }
    }

    @ViewBuilder
    private func chipView(_ item: ChipItem) -> some View {
        switch item {
        case .mod(let mod):
            HStack(spacing: 10) {
                Image(systemName: ModIcon.symbolName(for: mod.category))
                    .font(.system(size: 24, weight: .semibold))
                Text(mod.name)
                    .font(.system(size: 27, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 18).padding(.vertical, 12)
            .frame(maxWidth: 440, alignment: .leading)
            .background(Capsule().fill(Color.white.opacity(0.14)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.22), lineWidth: 1.5))
        case .more(let n):
            Text("+\(n) more")
                .font(.system(size: 26, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))
                .padding(.horizontal, 18).padding(.vertical, 12)
                .background(Capsule().fill(Color.white.opacity(0.08)))
        }
    }

    // MARK: - Owner row / footer

    private var ownerRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 26))
            Text("@\(car.ownerUsername)")
                .font(.system(size: 30, weight: .semibold))
        }
        .foregroundColor(.white.opacity(0.92))
    }

    private var footer: some View {
        // The wordmark is what a viewer remembers; the URL is secondary.
        HStack(spacing: 14) {
            Image("LogoMark")
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 40)
                .foregroundStyle(.white)
            Text("MARQUE")
                .font(.system(size: 34, weight: .heavy))
                .kerning(6)
                .foregroundColor(.white)
            Spacer(minLength: 16)
            Text(AppLinks.website.host ?? "marque-173c3.web.app")
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
                .lineLimit(1)
        }
        .padding(.top, 20)
    }
}
