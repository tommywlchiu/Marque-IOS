import SwiftUI
import Vision
import CoreImage

/// What the hero shows for a cover photo.
enum GarageHeroImage {
    /// Background removed on-device: the car floats on charcoal.
    case cutout(UIImage)
    /// No foreground instance found (or Vision failed): the full photo,
    /// faded into the background.
    case photo(UIImage)
}

/// Background removal for the Garage hero, via Vision's
/// `VNGenerateForegroundInstanceMaskRequest` (iOS 17+). Runs off the main
/// thread; results are cached on disk in Caches/GarageHeroCutouts keyed by
/// the photo's filename (a replaced photo always gets a new UUID filename, so
/// a stale entry can't be served), so each cover is processed once.
enum CarCutoutRenderer {
    /// Longest side, in pixels, of the image handed to Vision and cached.
    private static let workingPixelSize: CGFloat = 1600

    private static var cacheDirectory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = caches.appendingPathComponent("GarageHeroCutouts", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func cutoutURL(for fileName: String) -> URL {
        cacheDirectory.appendingPathComponent("\(fileName).png")
    }

    /// Marker for "Vision ran and found nothing", so a photo with no
    /// separable subject isn't re-processed on every launch. Not written when
    /// Vision throws (e.g. the Simulator lacks the model) — that may be transient.
    private static func noSubjectURL(for fileName: String) -> URL {
        cacheDirectory.appendingPathComponent("\(fileName).nosubject")
    }

    /// Synchronous disk probe, for painting a cached cut-out on the first frame.
    static func cachedCutout(fileName: String) -> UIImage? {
        UIImage(contentsOfFile: cutoutURL(for: fileName).path)
    }

    static func heroImage(fileName: String, storageURL: URL?) async -> GarageHeroImage? {
        if let cached = cachedCutout(fileName: fileName) { return .cutout(cached) }
        guard let source = await loadSource(fileName: fileName, storageURL: storageURL) else { return nil }

        let skipVision = FileManager.default.fileExists(atPath: noSubjectURL(for: fileName).path)
        if skipVision { return .photo(source) }

        let cutoutURL = cutoutURL(for: fileName)
        let noSubjectURL = noSubjectURL(for: fileName)
        return await Task.detached(priority: .userInitiated) { () -> GarageHeroImage in
            switch extractForeground(from: source) {
            case .success(let cutout?):
                if let data = cutout.pngData() { try? data.write(to: cutoutURL, options: .atomic) }
                return .cutout(cutout)
            case .success(nil):
                FileManager.default.createFile(atPath: noSubjectURL.path, contents: Data())
                return .photo(source)
            case .failure:
                return .photo(source)
            }
        }.value
    }

    /// The cover photo, upright and at most `workingPixelSize` px: local disk
    /// first (decoded off-main by `LocalPhotoLoader`), then the Storage copy.
    private static func loadSource(fileName: String, storageURL: URL?) async -> UIImage? {
        if let local = await LocalPhotoLoader.load(fileName: fileName, pixelSize: workingPixelSize) {
            return local
        }
        guard let storageURL else { return nil }
        let downloaded: UIImage
        if let cached = MarqueImageCache.shared.get(storageURL) {
            downloaded = cached
        } else {
            guard let (data, _) = try? await URLSession.shared.data(from: storageURL),
                  let image = UIImage(data: data) else { return nil }
            MarqueImageCache.shared.set(image, for: storageURL)
            downloaded = image
        }
        return await Task.detached(priority: .userInitiated) { normalized(downloaded) }.value
    }

    /// Redraws upright at <= `workingPixelSize` pixels. Measured in pixels
    /// (size * scale) and rendered at scale 1: `UIImage.size` is points and the
    /// renderer defaults to screen scale (see the image-size pitfall).
    private static func normalized(_ image: UIImage) -> UIImage {
        let pixelSize = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let maxSide = max(pixelSize.width, pixelSize.height)
        guard maxSide > 0 else { return image }
        let ratio = min(1, workingPixelSize / maxSide)
        let target = CGSize(width: (pixelSize.width * ratio).rounded(), height: (pixelSize.height * ratio).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    /// `.success(nil)` = Vision ran and found no foreground instance.
    private static func extractForeground(from image: UIImage) -> Result<UIImage?, Error> {
        guard let cgImage = image.cgImage else { return .success(nil) }
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
        do {
            try handler.perform([request])
            guard let observation = request.results?.first, !observation.allInstances.isEmpty else {
                return .success(nil)
            }
            let buffer = try observation.generateMaskedImage(
                ofInstances: observation.allInstances,
                from: handler,
                croppedToInstancesExtent: true
            )
            let ciImage = CIImage(cvPixelBuffer: buffer)
            guard let output = CIContext().createCGImage(ciImage, from: ciImage.extent) else { return .success(nil) }
            return .success(UIImage(cgImage: output))
        } catch {
            return .failure(error)
        }
    }
}

/// The big floating car. Cut-out on charcoal with a soft ground shadow when
/// Vision finds the car; otherwise the full photo fading into the background;
/// with no photo, a low-opacity car silhouette.
struct GarageHeroView: View {
    let car: Car
    let height: CGFloat

    @State private var loaded: (fileName: String, image: GarageHeroImage)?

    private var fileName: String? { car.primaryPhotoFileName }

    var body: some View {
        ZStack {
            if let fileName {
                if let loaded, loaded.fileName == fileName {
                    content(for: loaded.image)
                        .transition(.opacity)
                }
            } else {
                silhouette
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .animation(.easeOut(duration: 0.35), value: loaded?.fileName)
        .task(id: fileName) { await load() }
        .accessibilityElement()
        .accessibilityLabel(fileName == nil ? "No photo of \(car.displayName)" : "Photo of \(car.displayName)")
        .accessibilityAddTraits(.isImage)
    }

    private func load() async {
        guard let fileName else { loaded = nil; return }
        if let cached = CarCutoutRenderer.cachedCutout(fileName: fileName) {
            loaded = (fileName, .cutout(cached))
            return
        }
        if let image = await CarCutoutRenderer.heroImage(fileName: fileName, storageURL: car.primaryPhotoStorageURL),
           !Task.isCancelled {
            loaded = (fileName, image)
        }
    }

    @ViewBuilder
    private func content(for image: GarageHeroImage) -> some View {
        switch image {
        case .cutout(let cutout):
            ZStack(alignment: .bottom) {
                groundShadow
                Image(uiImage: cutout)
                    .resizable()
                    .scaledToFit()
                    .padding(.horizontal, 36)
                    .padding(.bottom, 18)
                    .shadow(color: .black.opacity(0.55), radius: 18, y: 14)
            }
        case .photo(let photo):
            Image(uiImage: photo)
                .resizable()
                .scaledToFill()
                .frame(height: height)
                .frame(maxWidth: .infinity)
                .clipped()
                .overlay(Color.black.opacity(0.18))
                .mask(Self.edgeFade)
        }
    }

    /// Fades a full photo into the charcoal on every edge (a vignette).
    private static var edgeFade: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.22),
                .init(color: .black, location: 0.7),
                .init(color: .clear, location: 1),
            ],
            startPoint: .top, endPoint: .bottom
        )
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.12),
                    .init(color: .black, location: 0.88),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .leading, endPoint: .trailing
            )
        )
    }

    private var groundShadow: some View {
        Ellipse()
            .fill(Color.black.opacity(0.55))
            .frame(height: 28)
            .padding(.horizontal, 56)
            .blur(radius: 14)
            .padding(.bottom, 10)
    }

    private var silhouette: some View {
        ZStack(alignment: .bottom) {
            groundShadow
            Image(systemName: "car.side.fill")
                .resizable()
                .scaledToFit()
                .fontWeight(.ultraLight)
                .foregroundStyle(
                    LinearGradient(colors: [.white.opacity(0.16), .white.opacity(0.07)], startPoint: .top, endPoint: .bottom)
                )
                .padding(.horizontal, 56)
                .padding(.bottom, 26)
                .frame(maxHeight: height * 0.8)
        }
    }
}
