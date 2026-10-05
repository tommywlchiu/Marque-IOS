import SwiftUI
import Vision
import CoreImage
import CoreMotion

/// What the hero shows.
enum GarageHeroImage {
    /// The car lifted out of its cover photo on-device.
    case cutout(UIImage)
    /// A code-built model of the car's body style in its color — used when
    /// there's no photo, or the photo isn't a clean, whole shot of a car.
    case model(UIImage)

    var image: UIImage {
        switch self {
        case .cutout(let image), .model(let image): return image
        }
    }
}

/// Background removal for the Garage hero, via Vision's
/// `VNGenerateForegroundInstanceMaskRequest` (iOS 17+). Runs off the main
/// thread; results are cached on disk in Caches/GarageHeroCutouts-v2 keyed by
/// the photo's filename (a replaced photo always gets a new UUID filename, so
/// a stale entry can't be served), so each cover is processed once.
///
/// A cut-out is only used when it looks like a render would: Vision must
/// classify the photo as a vehicle, and the largest foreground subject (the
/// only one kept, so a person beside the car is dropped) must be reasonably
/// big and not cut off by the photo's left, right or bottom edge.
enum CarCutoutRenderer {
    /// Longest side, in pixels, of the image handed to Vision and cached.
    private static let workingPixelSize: CGFloat = 1600
    /// `VNClassifyImageRequest` labels that count as "a car".
    private static let vehicleLabels: Set<String> = [
        "car", "automobile", "sportscar", "suv", "truck", "van", "jeep", "convertible",
        "limousine", "police_car", "vehicle", "engine_vehicle", "formula_one_car",
    ]

    private static var cacheDirectory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = caches.appendingPathComponent("GarageHeroCutouts-v2", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func cutoutURL(for fileName: String) -> URL {
        cacheDirectory.appendingPathComponent("\(fileName).png")
    }

    /// Marker for "Vision ran and this photo isn't usable", so it isn't
    /// re-processed on every launch. Not written when Vision throws (e.g. the
    /// Simulator lacks the model) — that may be transient.
    private static func unusableURL(for fileName: String) -> URL {
        cacheDirectory.appendingPathComponent("\(fileName).unusable")
    }

    /// Synchronous disk probe, for painting a cached cut-out on the first frame.
    static func cachedCutout(fileName: String) -> UIImage? {
        UIImage(contentsOfFile: cutoutURL(for: fileName).path)
    }

    static func isKnownUnusable(fileName: String) -> Bool {
        FileManager.default.fileExists(atPath: unusableURL(for: fileName).path)
    }

    /// The cut-out, or nil when the photo isn't usable (or can't be loaded).
    static func cutout(fileName: String, storageURL: URL?) async -> UIImage? {
        if let cached = cachedCutout(fileName: fileName) { return cached }
        if isKnownUnusable(fileName: fileName) { return nil }
        guard let source = await loadSource(fileName: fileName, storageURL: storageURL) else { return nil }

        let cutoutURL = cutoutURL(for: fileName)
        let unusableURL = unusableURL(for: fileName)
        return await Task.detached(priority: .userInitiated) { () -> UIImage? in
            switch extractCar(from: source) {
            case .success(let cutout?):
                if let data = cutout.pngData() { try? data.write(to: cutoutURL, options: .atomic) }
                return cutout
            case .success(nil):
                FileManager.default.createFile(atPath: unusableURL.path, contents: Data())
                return nil
            case .failure:
                return nil
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

    /// `.success(nil)` = Vision ran and the photo isn't a usable car shot.
    private static func extractCar(from image: UIImage) -> Result<UIImage?, Error> {
        guard let cgImage = image.cgImage else { return .success(nil) }
        let maskRequest = VNGenerateForegroundInstanceMaskRequest()
        let classifyRequest = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
        do {
            try handler.perform([maskRequest, classifyRequest])
            let isVehicle = (classifyRequest.results ?? []).contains {
                $0.confidence >= 0.2 && vehicleLabels.contains($0.identifier)
            }
            guard isVehicle,
                  let observation = maskRequest.results?.first,
                  let subject = largestInstance(in: observation.instanceMask),
                  subject.isWholeAndLargeEnough else {
                return .success(nil)
            }
            let buffer = try observation.generateMaskedImage(
                ofInstances: IndexSet(integer: subject.label),
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

    private struct Subject {
        let label: Int
        /// Bounding box in the mask's pixels, plus the mask's size.
        let minX: Int, maxX: Int, maxY: Int, width: Int, height: Int

        /// Not cut off on the left, right or bottom (a cropped car looks
        /// broken floating on charcoal), and at least a third of the frame wide.
        var isWholeAndLargeEnough: Bool {
            let margin = max(1, width / 100)
            let touchesEdge = minX < margin || maxX >= width - margin || maxY >= height - margin
            return !touchesEdge && (maxX - minX) * 3 >= width
        }
    }

    /// The foreground instance with the most pixels, from Vision's label mask
    /// (one UInt8 instance label per pixel, 0 = background).
    private static func largestInstance(in mask: CVPixelBuffer) -> Subject? {
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(mask) else { return nil }
        let width = CVPixelBufferGetWidth(mask), height = CVPixelBufferGetHeight(mask)
        let rowBytes = CVPixelBufferGetBytesPerRow(mask)
        var counts = [Int](repeating: 0, count: 256)
        var minX = [Int](repeating: Int.max, count: 256), maxX = [Int](repeating: -1, count: 256)
        var maxY = [Int](repeating: -1, count: 256)
        for y in 0..<height {
            let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: UInt8.self)
            for x in 0..<width {
                let label = Int(row[x])
                guard label != 0 else { continue }
                counts[label] += 1
                if x < minX[label] { minX[label] = x }
                if x > maxX[label] { maxX[label] = x }
                maxY[label] = y
            }
        }
        guard let best = counts.indices.dropFirst().max(by: { counts[$0] < counts[$1] }), counts[best] > 0 else { return nil }
        return Subject(label: best, minX: minX[best], maxX: maxX[best], maxY: maxY[best], width: width, height: height)
    }
}

/// The big floating car, staged like a studio render: a soft spotlight
/// behind it, a contact shadow and a faint floor reflection beneath it, and a
/// slight tilt that follows the phone (off with Reduce Motion). Shows the
/// car's own cut-out when its cover photo is usable, otherwise a model of its
/// body style in its color.
struct GarageHeroView: View {
    let car: Car
    let height: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var tilt = HeroMotionTilt()
    @State private var loaded: (key: String, image: GarageHeroImage)?

    /// Changes whenever what the hero should show changes.
    private var key: String {
        [car.primaryPhotoFileName ?? "-", car.make, car.model, car.bodyStyle, car.color].joined(separator: "|")
    }

    var body: some View {
        ZStack {
            spotlight
            if let loaded, loaded.key == key {
                staged(loaded.image.image)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .animation(.easeOut(duration: 0.35), value: loaded?.key)
        .task(id: key) { await load() }
        .onAppear { if !reduceMotion { tilt.start() } }
        .onDisappear { tilt.stop() }
        .onChange(of: reduceMotion) { _, reduce in reduce ? tilt.stop() : tilt.start() }
        .accessibilityElement()
        .accessibilityLabel(car.displayName.isEmpty ? "Car" : car.displayName)
        .accessibilityAddTraits(.isImage)
    }

    private func load() async {
        let key = key
        if let fileName = car.primaryPhotoFileName {
            if let cached = CarCutoutRenderer.cachedCutout(fileName: fileName) {
                loaded = (key, .cutout(cached))
                return
            }
            if let cutout = await CarCutoutRenderer.cutout(fileName: fileName, storageURL: car.primaryPhotoStorageURL) {
                guard !Task.isCancelled else { return }
                loaded = (key, .cutout(cutout))
                return
            }
        }
        if let cached = CarModelRenderer.cachedImage(for: car) {
            loaded = (key, .model(cached))
            return
        }
        if let model = await CarModelRenderer.image(for: car), !Task.isCancelled {
            loaded = (key, .model(model))
        }
    }

    private func staged(_ image: UIImage) -> some View {
        let angle = reduceMotion ? 0 : tilt.roll * 5
        let pitch = reduceMotion ? 0 : tilt.pitch * 3
        return VStack(spacing: 0) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .background(alignment: .bottom) { groundShadow.offset(y: 10) }
            // Floor reflection: the car mirrored, fading out quickly.
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(x: 1, y: -1)
                .opacity(0.22)
                .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .init(x: 0.5, y: 0.45)))
                .frame(maxHeight: height * 0.3, alignment: .top)
                .clipped()
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 28)
        .padding(.top, 12)
        .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
        .rotation3DEffect(.degrees(pitch), axis: (x: 1, y: 0, z: 0), perspective: 0.4)
    }

    /// A soft pool of light behind the car, like a studio backdrop.
    private var spotlight: some View {
        RadialGradient(
            colors: [Color.white.opacity(0.09), .clear],
            center: .init(x: 0.5, y: 0.5),
            startRadius: 0,
            endRadius: height * 0.5
        )
        .scaleEffect(x: 2.2, y: 1)  // a wide oval that fades out inside the frame
        .accessibilityHidden(true)
    }

    private var groundShadow: some View {
        Ellipse()
            .fill(Color.black.opacity(0.6))
            .frame(height: 26)
            .padding(.horizontal, 30)
            .blur(radius: 12)
    }
}

/// Device tilt for the hero's parallax, smoothed and clamped to [-1, 1].
/// Device motion needs no permission prompt (only activity/pedometer data does).
@MainActor
final class HeroMotionTilt: ObservableObject {
    @Published private(set) var roll: Double = 0
    @Published private(set) var pitch: Double = 0
    private let manager = CMMotionManager()
    private var reference: CMAttitude?

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30
        reference = nil
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            // Relative to how the phone was held when the screen appeared.
            if self.reference == nil { self.reference = motion.attitude.copy() as? CMAttitude }
            let attitude = motion.attitude
            if let reference = self.reference { attitude.multiply(byInverseOf: reference) }
            let clamp = { (v: Double) in min(max(v / 0.35, -1), 1) }
            self.roll += (clamp(attitude.roll) - self.roll) * 0.15
            self.pitch += (clamp(attitude.pitch) - self.pitch) * 0.15
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        roll = 0
        pitch = 0
    }
}
