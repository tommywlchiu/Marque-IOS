import SwiftUI
import ImageIO

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

/// `style` distinguishes Apple (white background, black content, per Apple's
/// HIG) from Google and other providers (dark glass, hairline stroke) — the
/// two providers' buttons are visually different by design, not just tinted
/// variants of one look. Defaults to `.google` so any call site that doesn't
/// care keeps compiling unchanged.
enum SocialSignInStyle {
    case apple
    case google
}

struct SocialSignInButton: View {
    let icon: String
    let label: String
    var style: SocialSignInStyle = .google
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .medium))
                Text(label)
                    .font(.system(size: 16, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 54)
        }
        .buttonStyle(SocialSignInButtonStyle(style: style))
    }
}

private struct SocialSignInButtonStyle: ButtonStyle {
    let style: SocialSignInStyle
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(style == .apple ? Color.black : Color.white)
            .background(background)
            .overlay(strokeOverlay)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(isEnabled ? 1 : 0.5)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }

    @ViewBuilder
    private var background: some View {
        switch style {
        case .apple:
            Color.white
        case .google:
            Color.white.opacity(0.06)
        }
    }

    @ViewBuilder
    private var strokeOverlay: some View {
        if style == .google {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        }
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
    var notFollowingLabel: String = "Follow"
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
        Text(isFollowing ? "Following" : notFollowingLabel)
            .font(.subheadline).fontWeight(.semibold)
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
    }
}

// MARK: - Cached Remote Image

/// Drop-in replacement for AsyncImage that caches via NSCache.
/// Shows a neutral grey background while loading — never the caller's placeholder —
/// so callers only show their placeholder when url is genuinely nil.
struct CachedRemoteImage: View {
    let url: URL?

    @StateObject private var loader = RemoteImageLoader()

    var body: some View {
        Group {
            if let img = loader.image {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                Color(.systemGray5)
            }
        }
        .task(id: url?.absoluteString) {
            guard let url else { return }
            loader.load(from: url)
        }
    }
}

// MARK: - Image Cache

/// Shared in-memory cache for decoded images -- both remote downloads and
/// downsampled local photo decodes (see `LocalPhotoLoader` below). Bypasses
/// Firebase Storage's `Cache-Control: private, max-age=0` headers that prevent
/// URLCache from working.
///
/// Bounded two ways: `countLimit` caps the number of entries, and `totalCostLimit`
/// caps estimated decoded-bitmap bytes, so a screen full of full-size hero photos
/// can't balloon memory the way holding many undownsampled UIImages would. NSCache
/// evicts under either pressure or system memory warnings, so this is a soft cap,
/// not a hard ceiling.
final class MarqueImageCache {
    static let shared = MarqueImageCache()
    private let cache = NSCache<NSString, UIImage>()

    init() {
        cache.countLimit = 200
        cache.totalCostLimit = 80 * 1024 * 1024 // ~80MB of decoded pixel data
    }

    func get(_ url: URL) -> UIImage? {
        get(key: url.absoluteString)
    }

    func set(_ image: UIImage, for url: URL) {
        set(image, key: url.absoluteString)
    }

    func get(key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func set(_ image: UIImage, key: String) {
        cache.setObject(image, forKey: key as NSString, cost: estimatedCost(of: image))
    }

    private func estimatedCost(of image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return 0 }
        return cgImage.bytesPerRow * cgImage.height
    }
}

// MARK: - Local Photo Loader

/// Off-main-thread decode + downsample for locally-stored car/avatar photos
/// (`Documents/CarPhotos/`, managed by `ImageManager`). A full-resolution camera
/// photo (often 4032x3024) is never fully decoded just to paint a 56pt thumbnail --
/// ImageIO's thumbnail generator decodes directly at the target pixel size.
///
/// Results are cached in `MarqueImageCache`, keyed by fileName + target pixel size,
/// so re-showing the same photo at the same size (e.g. scrolling a list row back
/// into view) hits the cache instead of re-decoding, and a replaced photo (which
/// always gets a new UUID filename -- see `ImageManager.generateFileName()`) can
/// never collide with a stale cache entry for the old filename.
enum LocalPhotoLoader {
    /// Mirrors `ImageManager`'s private `photosDirectory`. ImageManager exposes no
    /// file-URL accessor today, so the path is duplicated here deliberately, only
    /// to read off the main thread -- never to write. (Flagged for a follow-up:
    /// ImageManager could expose a `fileURL(for:)` helper to remove this duplication.)
    private static var photosDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("CarPhotos", isDirectory: true)
    }

    private static func cacheKey(fileName: String, pixelSize: CGFloat, fillAspect: CGFloat?) -> String {
        let fill = fillAspect.map { "f\(Int(($0 * 100).rounded()))" } ?? "fit"
        return "\(fileName)@\(Int(pixelSize.rounded()))\(fill)"
    }

    /// Synchronous cache probe. Checking this before kicking off `load` lets a
    /// cache hit paint on the very first frame instead of flashing a placeholder.
    static func cachedImage(fileName: String, pixelSize: CGFloat, fillAspect: CGFloat? = nil) -> UIImage? {
        guard !fileName.isEmpty else { return nil }
        return MarqueImageCache.shared.get(key: cacheKey(fileName: fileName, pixelSize: pixelSize, fillAspect: fillAspect))
    }

    /// Decodes + downsamples off the main actor. Returns nil if the file doesn't
    /// exist locally or isn't valid image data (e.g. not yet downloaded on this device).
    /// `fillAspect` (width / height of the frame) is for aspect-fill display: the
    /// photo's *shorter* fitted side must still cover the frame, so a portrait photo
    /// in a wide banner needs a larger longest side than `pixelSize` alone.
    static func load(fileName: String, pixelSize: CGFloat, fillAspect: CGFloat? = nil) async -> UIImage? {
        guard !fileName.isEmpty, pixelSize > 0 else { return nil }
        if let cached = cachedImage(fileName: fileName, pixelSize: pixelSize, fillAspect: fillAspect) {
            return cached
        }
        let url = photosDirectory.appendingPathComponent(fileName)
        let key = cacheKey(fileName: fileName, pixelSize: pixelSize, fillAspect: fillAspect)
        let decoded = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize(source: source, fitting: pixelSize, fillAspect: fillAspect),
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true
            ]
            guard let cgThumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return nil
            }
            // A file saved before downscale-on-save is still full camera size.
            // This loader bypasses ImageManager.loadImage (whose load path does the
            // one-time shrink), so trigger that shrink here, in the background.
            if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
               let w = props[kCGImagePropertyPixelWidth] as? CGFloat,
               let h = props[kCGImagePropertyPixelHeight] as? CGFloat,
               max(w, h) > ImageManager.maxDimension {
                Task.detached(priority: .utility) { _ = ImageManager.loadImage(fileName: fileName) }
            }
            return UIImage(cgImage: cgThumbnail)
        }.value
        if let decoded {
            MarqueImageCache.shared.set(decoded, key: key)
        }
        return decoded
    }

    /// Longest-side pixel size to decode at. For aspect-fit it's just the frame's
    /// longest side; for aspect-fill, the image is scaled until it covers the frame,
    /// so compute the covering size and take its longest side.
    private static func maxPixelSize(source: CGImageSource, fitting pixelSize: CGFloat, fillAspect: CGFloat?) -> CGFloat {
        guard let fillAspect, fillAspect > 0,
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? CGFloat,
              let h = props[kCGImagePropertyPixelHeight] as? CGFloat,
              w > 0, h > 0
        else { return pixelSize }
        // EXIF orientations 5-8 are rotated 90°, so the displayed aspect is h/w.
        let orientation = props[kCGImagePropertyOrientation] as? Int ?? 1
        let imageAspect = orientation >= 5 ? h / w : w / h
        // Frame in pixels, from its longest side and aspect.
        let frameW = fillAspect >= 1 ? pixelSize : pixelSize * fillAspect
        let frameH = fillAspect >= 1 ? pixelSize / fillAspect : pixelSize
        // Aspect-fill: an image narrower than the frame matches its width and
        // overflows vertically; a wider one matches its height.
        let covering = imageAspect < fillAspect
            ? CGSize(width: frameW, height: frameW / imageAspect)
            : CGSize(width: frameH * imageAspect, height: frameH)
        return min(max(covering.width, covering.height), max(w, h))
    }
}

@MainActor
private final class RemoteImageLoader: ObservableObject {
    @Published var image: UIImage?

    func load(from url: URL) {
        if let cached = MarqueImageCache.shared.get(url) {
            image = cached
            return
        }
        Task {
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let loaded = UIImage(data: data) else { return }
            MarqueImageCache.shared.set(loaded, for: url)
            image = loaded
        }
    }
}

// MARK: - Owner Avatar

/// Lightweight avatar used wherever only a URL + username are available.
/// Uses NSCache so the image is returned instantly on subsequent renders,
/// preventing the flicker that AsyncImage causes on every view rebuild.
struct OwnerAvatar: View {
    let avatarURL: String?
    let username: String
    let size: CGFloat

    @StateObject private var loader = RemoteImageLoader()

    var body: some View {
        Group {
            if let img = loader.image {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                initialsView
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: avatarURL) {
            guard let urlString = avatarURL,
                  !urlString.isEmpty,
                  let url = URL(string: urlString) else { return }
            loader.load(from: url)
        }
    }

    private var initialsView: some View {
        Circle()
            .fill(Color.accentColor.opacity(0.15))
            .overlay(
                Text(username.prefix(1).uppercased())
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundColor(.accentColor)
            )
    }
}
