import UIKit

/// Studio renders of real cars, imagin.studio-style: real 3D models (CC BY,
/// from Sketchfab) rendered in Blender by `scripts/car-render/` — every car ×
/// 12 palette colors × 36 turntable angles — and served as static WebP files
/// from Firebase Hosting. `catalog.json` (fetched, cached on disk) says which
/// make/model/years exist, so cars can be added without an app update. A car
/// with no entry of its own gets the catalog's generic, unbadged render of its
/// body style; only with no catalog at all (first launch offline) does it fall
/// back to the code-built `CarModelRenderer` model.
enum CarRenderLibrary {
    static let baseURL: URL = {
        #if DEBUG
        // e.g. `-car_renders_base_url http://127.0.0.1:5050/carRenders/v1` to test
        // against a local copy of public/ before it's deployed. Compiled out of Release.
        if let override = UserDefaults.standard.string(forKey: "car_renders_base_url"),
           let url = URL(string: override) { return url }
        #endif
        return URL(string: "https://marque-173c3.web.app/carRenders/v1")!
    }()

    struct Catalog: Codable {
        let version: Int
        let frames: Int
        let colors: [String]
        let cars: [Entry]
        /// Unbadged stand-ins, one per body style. Optional so a catalog
        /// written before they existed still decodes.
        let generics: [Generic]?
        /// The wheels add-on's styles (optional: older catalogs).
        let wheelStyles: [WheelStyle]?

        /// Every model credited, once each (one pack can supply several
        /// generics) — for Settings › Acknowledgements.
        var credits: [Credit] {
            var seen = Set<String>()
            return (cars.map(\.credit) + (generics ?? []).map(\.credit) + (wheelStyles ?? []).map(\.credit))
                .filter { seen.insert($0.url).inserted }
        }
    }

    struct WheelStyle: Codable, Identifiable, Equatable {
        let id: String
        let title: String
        let credit: Credit
    }

    struct Generic: Codable {
        let key: String
        /// Normalized body styles it stands in for (`CarModelRenderer.normalizedStyle`).
        let styles: [String]
        let credit: Credit
        let plates: Bool?
        let tint: Bool?
        let wheels: [String]?
        let meter: Double?
        let extras: [String: [Double]]?
        /// Seat-color options rendered for this car (`<key>/seats/<option>/NN.webp`,
        /// options in `CarCustomization.SeatColor`); optional (older catalogs,
        /// or a car whose model has no separable seat material).
        let seats: [String]?
        /// Whether `<key>/night2/<color>/NN.webp` (the night-lighting pass,
        /// same crop as day) exists for every palette color.
        let night: Bool?
        /// Whether `<key>/blackOptic/NN.webp` (the blacked-out chrome trim
        /// add-on, `CarCustomization.blackOptic`) exists for every frame.
        let blackOptic: Bool?
    }

    struct Entry: Codable, Identifiable {
        let key: String
        let make: String
        let models: [String]
        let years: [Int]
        let credit: Credit
        /// Whether `<key>/plates.json` exists (optional: older catalogs).
        let plates: Bool?
        /// Whether `<key>/tint/NN.webp` window masks exist.
        let tint: Bool?
        /// Wheel styles rendered for this car (`<key>/wheels/<style>/NN.webp`);
        /// "stock" is the car's own wheels alone, for the stance add-on.
        let wheels: [String]?
        /// One meter of height as a fraction of the frame's height.
        let meter: Double?
        /// Roof/body extras rendered for this car (`<key>/extras/<id>/NN.webp`,
        /// ids in `CarCustomization.Extra`), each with where its layer sits:
        /// x, y, width, height as fractions of the frame (y < 0 = above it —
        /// a roof box stands higher than the car's own crop).
        let extras: [String: [Double]]?
        /// Seat-color options rendered for this car, same shape as `Generic.seats`.
        let seats: [String]?
        /// Same meaning as `Generic.night`.
        let night: Bool?
        /// Same meaning as `Generic.blackOptic`.
        let blackOptic: Bool?
        var id: String { key }
    }

    /// Where the license plates land in each turntable frame, as fractions
    /// of the frame (scripts/car-render/plates.py → publish.py).
    struct PlateTrack: Codable, Equatable {
        struct Plate: Codable, Equatable { let aspect: Double }
        struct Placement: Codable, Equatable {
            /// Top-left, top-right, bottom-right, bottom-left.
            let quad: [[Double]]
            /// How squarely the plate faces the camera, 0...1.
            let facing: Double
        }
        let plates: [String: Plate]
        let frames: [[String: Placement]]
    }

    struct Credit: Codable, Identifiable, Equatable {
        let title: String
        let author: String
        let authorURL: String
        let license: String
        let licenseURL: String
        let url: String
        var id: String { url }
    }

    /// One car's renders in one color: the frame URLs and local cache paths.
    struct Match: Equatable {
        let carKey: String
        let colorKey: String
        let frameCount: Int
        var hasPlates = false
        var hasTint = false
        var hasNight = false
        var hasBlackOptic = false
        var wheelStyles: [String] = []
        var meter: Double?
        /// Each rendered extra's layer rect, in fractions of the frame.
        var extras: [String: CGRect] = [:]
        /// Seat-color option ids rendered for this car (`CarCustomization.SeatColor`).
        var seats: [String] = []
        var canChangeStance: Bool { wheelStyles.contains("stock") && meter != nil }

        // "night2", not "night": the first night pass shipped with a lighting
        // bug (the whole body read as near-black, not just dimmed — see the
        // render_car.py night_dim fix) and was already live on Hosting, which
        // serves *.webp with a 1-year immutable cache. A fixed render at the
        // same path would stay invisible to any client (or CDN edge) that had
        // already cached the broken one; a new path is the only way to bust it.
        fileprivate func remoteURL(_ frame: Int, night: Bool = false) -> URL {
            let path = night ? "\(carKey)/night2/\(colorKey)/\(String(format: "%02d", frame)).webp"
                              : "\(carKey)/\(colorKey)/\(String(format: "%02d", frame)).webp"
            return CarRenderLibrary.baseURL.appendingPathComponent(path)
        }

        fileprivate func localURL(_ frame: Int, night: Bool = false) -> URL {
            let path = night ? "\(carKey)/night2/\(colorKey)/\(String(format: "%02d", frame)).webp"
                              : "\(carKey)/\(colorKey)/\(String(format: "%02d", frame)).webp"
            return CarRenderLibrary.cacheDirectory.appendingPathComponent(path)
        }
    }

    private static var cacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CarRenders-v1", isDirectory: true)
    }

    private static var catalogURL: URL { cacheDirectory.appendingPathComponent("catalog.json") }

    // MARK: - Catalog

    /// Last catalog on disk, for painting a cached render on the first frame.
    static func cachedCatalog() -> Catalog? {
        guard let data = try? Data(contentsOf: catalogURL) else { return nil }
        return try? JSONDecoder().decode(Catalog.self, from: data)
    }

    /// The catalog, refreshed from Hosting at most once per launch; falls back
    /// to the disk copy when offline.
    static func catalog() async -> Catalog? {
        if let fresh = await CatalogLoader.shared.load() { return fresh }
        return cachedCatalog()
    }

    private actor CatalogLoader {
        static let shared = CatalogLoader()
        private var loaded: Catalog?
        private var attempted = false

        func load() async -> Catalog? {
            if attempted { return loaded }
            attempted = true
            guard let (data, response) = try? await URLSession.shared.data(from: CarRenderLibrary.baseURL.appendingPathComponent("catalog.json")),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let catalog = try? JSONDecoder().decode(Catalog.self, from: data) else { return nil }
            try? FileManager.default.createDirectory(at: CarRenderLibrary.cacheDirectory, withIntermediateDirectories: true)
            try? data.write(to: CarRenderLibrary.catalogURL, options: .atomic)
            loaded = catalog
            return catalog
        }
    }

    // MARK: - Matching

    /// Lowercased letters and digits only, so "Model 3" == "model3".
    private static func normalized(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// The catalog entry for this car: same make, a model that equals one of
    /// the entry's names (or starts with it as a separate word — "Model 3 Long
    /// Range"), and a year inside its range when the year is known. The most
    /// specific name wins — an exact match, else the longest prefix — so a
    /// "Silverado EV" gets the EV, not the gas Silverado whose name it starts
    /// with. No entry of its own → the generic render of its body style.
    static func match(_ car: Car, in catalog: Catalog?) -> Match? {
        guard let catalog else { return nil }
        let make = normalized(car.make)
        let model = normalized(car.model)
        let modelWords = car.model.lowercased()
        let year = Int(car.year.trimmingCharacters(in: .whitespaces))
        func score(_ entry: Entry) -> Int? {
            guard normalized(entry.make) == make else { return nil }
            if let year, entry.years.count == 2, !(entry.years[0]...entry.years[1]).contains(year) { return nil }
            return entry.models.compactMap { name -> Int? in
                if model == normalized(name) { return Int.max }
                return modelWords.hasPrefix(name.lowercased() + " ") ? name.count : nil
            }.max()
        }
        let entry = catalog.cars
            .compactMap { entry in score(entry).map { (entry, $0) } }
            .max { $0.1 < $1.1 }?.0
        let style = CarModelRenderer.normalizedStyle(car.bodyStyle)
        let generic = entry == nil ? catalog.generics?.first(where: { $0.styles.contains(style) }) : nil
        guard let key = entry?.key ?? generic?.key else { return nil }
        let color = CarPaint.paletteKey(for: car.color)
        guard catalog.colors.contains(color) else { return nil }
        return Match(carKey: key, colorKey: color, frameCount: catalog.frames,
                     hasPlates: (entry?.plates ?? generic?.plates) == true,
                     hasTint: (entry?.tint ?? generic?.tint) == true,
                     hasNight: (entry?.night ?? generic?.night) == true,
                     hasBlackOptic: (entry?.blackOptic ?? generic?.blackOptic) == true,
                     wheelStyles: entry?.wheels ?? generic?.wheels ?? [],
                     meter: entry?.meter ?? generic?.meter,
                     extras: (entry?.extras ?? generic?.extras ?? [:]).compactMapValues { r in
                         r.count == 4 ? CGRect(x: r[0], y: r[1], width: r[2], height: r[3]) : nil
                     },
                     seats: entry?.seats ?? generic?.seats ?? [])
    }

    // MARK: - Frames

    /// Synchronous disk probe for frame 0 (the hero's resting 3/4 view).
    static func cachedStill(for match: Match, night: Bool = false) -> UIImage? {
        UIImage(contentsOfFile: match.localURL(0, night: night).path)
    }

    static func frame(_ index: Int, of match: Match, night: Bool = false) async -> UIImage? {
        let local = match.localURL(index, night: night)
        if let image = UIImage(contentsOfFile: local.path) { return image }
        guard let (data, response) = try? await URLSession.shared.data(from: match.remoteURL(index, night: night)),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let image = UIImage(data: data) else { return nil }
        try? FileManager.default.createDirectory(at: local.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: local, options: .atomic)
        return image
    }

    /// One wheel style's layer frames for this car (the new wheels over a
    /// transparent background), or nil if it has none or any is missing.
    static func wheelLayers(of match: Match, style: String) async -> [UIImage]? {
        guard match.wheelStyles.contains(style) else { return nil }
        return await layers(of: match, folder: "wheels/\(style)")
    }

    /// One roof/body extra's layer frames for this car (the extra alone, the
    /// car's own body cut out of it), or nil if it has none or any is missing.
    static func extraLayers(of match: Match, extra: String) async -> [UIImage]? {
        guard match.extras[extra] != nil else { return nil }
        return await layers(of: match, folder: "extras/\(extra)")
    }

    /// One seat-color option's layer, over the car the same way its own
    /// frame is (not positioned by a rect like an extra — it sits exactly
    /// where the body does), or nil if this car has no seats add-on or
    /// doesn't render this option.
    static func seatLayers(of match: Match, option: String) async -> [UIImage]? {
        guard match.seats.contains(option) else { return nil }
        return await layers(of: match, folder: "seats/\(option)")
    }

    /// The car's window masks for the tint add-on, one per frame (white =
    /// glass), or nil if it has none or any is missing.
    static func tintMasks(of match: Match) async -> [UIImage]? {
        guard match.hasTint else { return nil }
        return await layers(of: match, folder: "tint")
    }

    /// The Black Optic trim layer (blacked-out grille, rings, mirrors,
    /// window trim), over the car the same way a seat-color layer is — one
    /// fixed set of frames, no per-color variants — or nil if this car has
    /// no Black Optic add-on or any frame is missing.
    static func blackOpticLayers(of match: Match) async -> [UIImage]? {
        guard match.hasBlackOptic else { return nil }
        return await layers(of: match, folder: "blackOptic")
    }

    /// A per-frame layer folder under the car (`tint`, `wheels/<style>`, `extras/<id>`),
    /// disk-cached like the frames; nil if any frame is missing.
    private static func layers(of match: Match, folder: String) async -> [UIImage]? {
        await withTaskGroup(of: (Int, UIImage?).self) { group in
            for i in 0..<match.frameCount {
                group.addTask {
                    let path = "\(match.carKey)/\(folder)/\(String(format: "%02d", i)).webp"
                    let local = cacheDirectory.appendingPathComponent(path)
                    if let image = UIImage(contentsOfFile: local.path) { return (i, image) }
                    guard let (data, response) = try? await URLSession.shared.data(from: baseURL.appendingPathComponent(path)),
                          (response as? HTTPURLResponse)?.statusCode == 200,
                          let image = UIImage(data: data) else { return (i, nil) }
                    try? FileManager.default.createDirectory(at: local.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try? data.write(to: local, options: .atomic)
                    return (i, image)
                }
            }
            var masks = [UIImage?](repeating: nil, count: match.frameCount)
            for await (i, image) in group { masks[i] = image }
            let loaded = masks.compactMap { $0 }
            return loaded.count == match.frameCount ? loaded : nil
        }
    }

    /// The car's plate positions, if it has them (disk-cached like frames).
    static func plates(of match: Match) async -> PlateTrack? {
        guard match.hasPlates else { return nil }
        let local = cacheDirectory.appendingPathComponent("\(match.carKey)/plates.json")
        if let data = try? Data(contentsOf: local), let track = try? JSONDecoder().decode(PlateTrack.self, from: data) {
            return track
        }
        guard let (data, response) = try? await URLSession.shared.data(from: baseURL.appendingPathComponent("\(match.carKey)/plates.json")),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let track = try? JSONDecoder().decode(PlateTrack.self, from: data) else { return nil }
        try? FileManager.default.createDirectory(at: local.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: local, options: .atomic)
        return track
    }

    /// All frames in order, fetched in parallel; nil if any is missing, so a
    /// spin never shows a gap. `night` swaps in the night-lighting pass
    /// (ignored, same as day, if `match.hasNight` is false).
    static func allFrames(of match: Match, night: Bool = false) async -> [UIImage]? {
        await withTaskGroup(of: (Int, UIImage?).self) { group in
            for i in 0..<match.frameCount {
                group.addTask { (i, await frame(i, of: match, night: night)) }
            }
            var frames = [UIImage?](repeating: nil, count: match.frameCount)
            for await (i, image) in group { frames[i] = image }
            let loaded = frames.compactMap { $0 }
            return loaded.count == match.frameCount ? loaded : nil
        }
    }

    /// The resting still for a car, if it has renders — for contexts that
    /// show one image (the Home Screen widget).
    static func still(for car: Car) async -> UIImage? {
        guard let found = match(car, in: await catalog()) else { return nil }
        return await frame(0, of: found)
    }

    static func cachedStill(for car: Car) -> UIImage? {
        guard let found = match(car, in: cachedCatalog()) else { return nil }
        return cachedStill(for: found)
    }
}
