import SwiftUI
import Vision
import CoreImage
import CoreMotion

/// What the hero shows.
enum GarageHeroImage {
    /// The car lifted out of its cover photo on-device.
    case cutout(UIImage)
    /// A studio render of the real make/model in the car's (palette) color
    /// — `CarRenderLibrary` — when there's no usable photo and the catalog
    /// covers the car. The image is the resting still; frames load after.
    case rendered(UIImage, CarRenderLibrary.Match)
    /// A code-built model of the car's body style in its color — the last
    /// resort, when there's no usable photo and no studio render.
    case model(UIImage)

    var image: UIImage {
        switch self {
        case .cutout(let image), .rendered(let image, _), .model(let image): return image
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
    /// Flips the car's day/night lighting; nil hides the quick toggle. Shown
    /// only once a studio render with a night pass has actually loaded, so
    /// there's never a toggle with nothing for it to change.
    var onToggleLighting: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var tilt = HeroMotionTilt()
    @State private var loaded: (key: String, image: GarageHeroImage)?
    /// The turntable frames for a `.rendered` hero, keyed like `loaded`.
    @State private var renderFrames: (key: String, frames: [UIImage])?
    /// Where the license plates sit in each of those frames, keyed the same.
    @State private var renderPlates: (key: String, track: CarRenderLibrary.PlateTrack)?
    /// Window masks for the tint add-on, keyed the same.
    @State private var renderTintMasks: (key: String, masks: [UIImage])?
    /// The chosen wheel style's layer frames, keyed by car + style.
    @State private var renderWheels: (key: String, layers: [UIImage])?
    /// The car's own wheels alone (for the stance add-on), keyed by car.
    @State private var renderStock: (key: String, layers: [UIImage])?
    /// The chosen roof/body extras' layers, keyed by car + extras.
    @State private var renderExtras: (key: String, layers: [RenderedCarSpinView.ExtraLayer])?
    /// The chosen seat-color layer frames, keyed by car + seat color.
    @State private var renderSeats: (key: String, layers: [UIImage])?
    /// The Black Optic trim layer frames, keyed by car + on/off.
    @State private var renderBlackOptic: (key: String, layers: [UIImage])?
    /// The match behind the rendered hero, for loading add-on layers later.
    @State private var renderMatch: CarRenderLibrary.Match?
    /// Bumped every time `renderMatch` is (re)assigned, including the silent
    /// disk-cache-then-network upgrade hop in `load()` that can replace it
    /// in place without `carKey` changing. The add-on keys below fold this
    /// in so a flag that only the fresh match has (e.g. a just-shipped
    /// `hasBlackOptic`) doesn't get stuck on a stale "no such add-on" result
    /// from the first, disk-cached match — `.task(id:)` only reruns when the
    /// id actually changes, and `carKey` alone doesn't catch that case.
    @State private var matchVersion = 0

    /// Changes whenever what the hero should show changes.
    private var key: String {
        [car.primaryPhotoFileName ?? "-", car.make, car.model, car.year, car.bodyStyle, car.color,
         car.customization.lightingMode.rawValue].joined(separator: "|")
    }

    /// Only meaningful for the `.rendered` studio hero — a cutout is the
    /// owner's own photo and has no night version.
    private var night: Bool { car.customization.lightingMode == .night }

    /// A one-tap sun/moon toggle over the hero itself — the only control for
    /// day/night lighting (no second picker elsewhere, see the "one entry
    /// point per feature" convention). Only appears once the loaded hero is
    /// a studio render whose match actually has a night pass.
    @ViewBuilder
    private var lightingToggleButton: some View {
        if let onToggleLighting, let loaded, loaded.key == key,
           case .rendered(_, let match) = loaded.image, match.hasNight {
            Button(action: onToggleLighting) {
                Image(systemName: night ? "moon.stars.fill" : "sun.max.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(night ? .indigo : .yellow)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.black.opacity(0.35)))
            }
            .buttonStyle(GaragePressStyle())
            .padding(12)
            .accessibilityLabel(night ? "Switch to day lighting" : "Switch to night lighting")
        }
    }

    var body: some View {
        ZStack {
            spotlight
            if let loaded, loaded.key == key {
                Group {
                    switch loaded.image {
                    case .cutout(let image):
                        staged(image)
                    case .rendered(let still, _):
                        stagedRendered(still)
                    case .model:
                        // Live and interactive (drag to spin), not the baked
                        // PNG `loaded.image` itself holds — that bake still
                        // exists for cachedImage's first-frame probe and for
                        // the widget, which can't host a live SCNView.
                        stagedSpinnable
                    }
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .overlay(alignment: .topTrailing) { lightingToggleButton }
        .animation(.easeOut(duration: 0.35), value: loaded?.key)
        .task(id: key) { await load() }
        .task(id: wheelsKey) { await loadWheels() }
        .task(id: extrasKey) { await loadExtras() }
        .task(id: seatsKey) { await loadSeats() }
        .task(id: blackOpticKey) { await loadBlackOptic() }
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
        let night = night
        if let match = CarRenderLibrary.match(car, in: CarRenderLibrary.cachedCatalog()),
           let still = CarRenderLibrary.cachedStill(for: match, night: night && match.hasNight) {
            loaded = (key, .rendered(still, match))
            // The disk catalog is last launch's. Re-check against this
            // launch's: it can match the car differently (a new model in
            // place of its generic) or add plate positions.
            if let fresh = CarRenderLibrary.match(car, in: await CarRenderLibrary.catalog()), fresh != match,
               let freshStill = await CarRenderLibrary.frame(0, of: fresh, night: night && fresh.hasNight), !Task.isCancelled {
                loaded = (key, .rendered(freshStill, fresh))
                await loadFrames(fresh, key: key)
                return
            }
            await loadFrames(match, key: key)
            return
        }
        if let match = CarRenderLibrary.match(car, in: await CarRenderLibrary.catalog()),
           let still = await CarRenderLibrary.frame(0, of: match, night: night && match.hasNight) {
            guard !Task.isCancelled else { return }
            loaded = (key, .rendered(still, match))
            await loadFrames(match, key: key)
            return
        }
        if let cached = CarModelRenderer.cachedImage(for: car) {
            loaded = (key, .model(cached))
            return
        }
        if let model = await CarModelRenderer.image(for: car), !Task.isCancelled {
            loaded = (key, .model(model))
        }
    }

    /// Car + chosen wheel style: changes when either does.
    private var wheelsKey: String {
        [key, car.customization.wheels ?? "-", car.customization.stance.rawValue, renderMatch?.carKey ?? "", String(matchVersion)].joined(separator: "|")
    }

    /// The stance as a fraction of the frame's height (0 without the data).
    private var stanceLift: CGFloat {
        guard let meter = renderMatch?.meter, renderStock?.key == key else { return 0 }
        return CGFloat(car.customization.stance.lift * meter)
    }

    private func loadWheels() async {
        if car.customization.stance != .stock, renderStock?.key != key, let match = renderMatch, match.canChangeStance,
           let layers = await CarRenderLibrary.wheelLayers(of: match, style: "stock"), !Task.isCancelled {
            renderStock = (key, layers)
        }
        let wheelsKey = wheelsKey
        guard let style = car.customization.wheels, let match = renderMatch,
              renderWheels?.key != wheelsKey,
              let layers = await CarRenderLibrary.wheelLayers(of: match, style: style), !Task.isCancelled else { return }
        renderWheels = (wheelsKey, layers)
    }

    /// Car + chosen extras (+ the spoiler's finish, which picks a different
    /// rendered layer for the same extra): changes when any of those does.
    private var extrasKey: String {
        ([key, renderMatch?.carKey ?? "", String(matchVersion), car.customization.spoilerFinish.rawValue] + car.customization.extras.map(\.rawValue))
            .joined(separator: "|")
    }

    private func loadExtras() async {
        let extrasKey = extrasKey
        guard let match = renderMatch, renderExtras?.key != extrasKey else { return }
        var layers: [RenderedCarSpinView.ExtraLayer] = []
        for extra in car.customization.extras {
            // Carbon fiber is a finish on the spoiler, not a second extra —
            // same position, a different rendered layer — and only when the
            // car actually has that layer (every car with a spoiler fit
            // does, but an older cached catalog might not).
            let wantsCarbon = extra == .spoiler && car.customization.spoilerFinish == .carbon
                && match.extras["spoiler-carbon"] != nil
            let layerID = wantsCarbon ? "spoiler-carbon" : extra.rawValue
            guard let rect = match.extras[layerID],
                  let frames = await CarRenderLibrary.extraLayers(of: match, extra: layerID) else { continue }
            layers.append(.init(rect: rect, frames: frames))
        }
        guard !Task.isCancelled else { return }
        renderExtras = (extrasKey, layers)
    }

    /// Car + chosen seat color: changes when either does.
    private var seatsKey: String {
        [key, renderMatch?.carKey ?? "", String(matchVersion), car.customization.seatColor.rawValue].joined(separator: "|")
    }

    private func loadSeats() async {
        let seatsKey = seatsKey
        guard car.customization.seatColor != .standard, let match = renderMatch, renderSeats?.key != seatsKey,
              let layers = await CarRenderLibrary.seatLayers(of: match, option: car.customization.seatColor.rawValue),
              !Task.isCancelled else { return }
        renderSeats = (seatsKey, layers)
    }

    /// Car + Black Optic on/off: changes when either does.
    private var blackOpticKey: String {
        [key, renderMatch?.carKey ?? "", String(matchVersion), car.customization.blackOptic ? "on" : "off"].joined(separator: "|")
    }

    private func loadBlackOptic() async {
        let blackOpticKey = blackOpticKey
        guard car.customization.blackOptic, let match = renderMatch, renderBlackOptic?.key != blackOpticKey,
              let layers = await CarRenderLibrary.blackOpticLayers(of: match),
              !Task.isCancelled else { return }
        renderBlackOptic = (blackOpticKey, layers)
    }

    private func loadFrames(_ match: CarRenderLibrary.Match, key: String) async {
        if renderPlates?.key != key, let track = await CarRenderLibrary.plates(of: match), !Task.isCancelled {
            renderPlates = (key, track)
        }
        renderMatch = match
        matchVersion += 1
        if renderTintMasks?.key != key, let masks = await CarRenderLibrary.tintMasks(of: match), !Task.isCancelled {
            renderTintMasks = (key, masks)
        }
        guard renderFrames?.key != key else { return }
        if let frames = await CarRenderLibrary.allFrames(of: match, night: night && match.hasNight), !Task.isCancelled {
            renderFrames = (key, frames)
        }
    }

    /// Studio-render turntable on a glossy floor (its reflection and contact
    /// shadow are drawn by `RenderedCarSpinView`): the still right away,
    /// spinnable once every frame is in.
    private func stagedRendered(_ still: UIImage) -> some View {
        VStack(spacing: 0) {
            RenderedCarSpinView(
                still: still,
                frames: renderFrames?.key == key ? renderFrames?.frames : nil,
                plates: renderPlates?.key == key ? renderPlates?.track : nil,
                plateText: car.licensePlate,
                tintMasks: renderTintMasks?.key == key ? renderTintMasks?.masks : nil,
                tint: car.customization.tint,
                wheelLayers: renderWheels?.key == wheelsKey ? renderWheels?.layers : nil,
                stockWheels: renderStock?.key == key ? renderStock?.layers : nil,
                stanceLift: stanceLift,
                extras: renderExtras?.key == extrasKey ? renderExtras?.layers ?? [] : [],
                seatLayer: renderSeats?.key == seatsKey ? renderSeats?.layers : nil,
                blackOpticLayer: renderBlackOptic?.key == blackOpticKey ? renderBlackOptic?.layers : nil
            )
            // A new car/color must get a fresh view: the coordinator holds the
            // previous car's frames, and SwiftUI would otherwise reuse it.
            .id(key)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    /// Live, interactive turntable for the model-fallback case (its floor
    /// reflection is drawn by `SpinnableCarModelView`). No device-tilt parallax
    /// here — the user's own drag is the more meaningful motion.
    private var stagedSpinnable: some View {
        VStack(spacing: 0) {
            SpinnableCarModelView(profile: modelProfile, paint: modelPaint)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(alignment: .bottom) { groundShadow.offset(y: 10) }
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 28)
        .padding(.top, 12)
    }

    private var modelProfile: CarBodyProfile {
        CarBodyProfile.forCar(make: car.make, model: car.model, bodyStyle: car.bodyStyle)
    }

    private var modelPaint: UIColor {
        CarPaint.color(for: car.color)
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
