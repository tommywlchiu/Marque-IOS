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

        /// Every model credited, once each (one pack can supply several
        /// generics) — for Settings › Acknowledgements.
        var credits: [Credit] {
            var seen = Set<String>()
            return (cars.map(\.credit) + (generics ?? []).map(\.credit)).filter { seen.insert($0.url).inserted }
        }
    }

    struct Generic: Codable {
        let key: String
        /// Normalized body styles it stands in for (`CarModelRenderer.normalizedStyle`).
        let styles: [String]
        let credit: Credit
    }

    struct Entry: Codable, Identifiable {
        let key: String
        let make: String
        let models: [String]
        let years: [Int]
        let credit: Credit
        var id: String { key }
    }

    struct Credit: Codable, Identifiable {
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

        fileprivate func remoteURL(_ frame: Int) -> URL {
            CarRenderLibrary.baseURL.appendingPathComponent("\(carKey)/\(colorKey)/\(String(format: "%02d", frame)).webp")
        }

        fileprivate func localURL(_ frame: Int) -> URL {
            CarRenderLibrary.cacheDirectory.appendingPathComponent("\(carKey)/\(colorKey)/\(String(format: "%02d", frame)).webp")
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
        guard let key = entry?.key ?? catalog.generics?.first(where: { $0.styles.contains(style) })?.key else { return nil }
        let color = CarPaint.paletteKey(for: car.color)
        guard catalog.colors.contains(color) else { return nil }
        return Match(carKey: key, colorKey: color, frameCount: catalog.frames)
    }

    // MARK: - Frames

    /// Synchronous disk probe for frame 0 (the hero's resting 3/4 view).
    static func cachedStill(for match: Match) -> UIImage? {
        UIImage(contentsOfFile: match.localURL(0).path)
    }

    static func frame(_ index: Int, of match: Match) async -> UIImage? {
        let local = match.localURL(index)
        if let image = UIImage(contentsOfFile: local.path) { return image }
        guard let (data, response) = try? await URLSession.shared.data(from: match.remoteURL(index)),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let image = UIImage(data: data) else { return nil }
        try? FileManager.default.createDirectory(at: local.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: local, options: .atomic)
        return image
    }

    /// All frames in order, fetched in parallel; nil if any is missing, so a
    /// spin never shows a gap.
    static func allFrames(of match: Match) async -> [UIImage]? {
        await withTaskGroup(of: (Int, UIImage?).self) { group in
            for i in 0..<match.frameCount {
                group.addTask { (i, await frame(i, of: match)) }
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
