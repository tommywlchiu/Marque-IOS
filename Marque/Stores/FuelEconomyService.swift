import Foundation

/// EPA figures from fueleconomy.gov's public web service (no key): range on a
/// full charge for electric cars and plug-in hybrids (a PHEV's `range` is its
/// total, gas included), and combined MPG for everything else. The site has no
/// tank sizes, so a hybrid's or diesel's range is the owner's tank size × MPG.
///
/// fueleconomy.gov splits a model by trim, drive and engine ("Model 3 Long
/// Range AWD", "Silverado 2WD"), so a lookup reads every variant of the model
/// for that year and keeps the one closest to the car's trim, drive and engine,
/// with the car's powertrain. Returns nil rather than guess when nothing fits.
enum FuelEconomyService {
    struct Figures: Equatable {
        /// Miles on a full charge (EV) or total (PHEV); nil for others.
        var range: Int?
        /// Combined MPG (gas/diesel/hybrid); nil for EVs.
        var combinedMPG: Int?
    }

    struct Query {
        var year: String
        var make: String
        var model: String
        var trim: String
        var engine: String
        var driveType: String
        var fuelType: String
    }

    private static let base = "https://www.fueleconomy.gov/ws/rest/vehicle"

    static func lookup(_ q: Query) async throws -> Figures? {
        guard let powertrain = Powertrain(fuelType: q.fuelType),
              let year = Int(q.year.trimmingCharacters(in: .whitespaces)), year >= 1984,
              !q.make.isEmpty, !q.model.isEmpty else { return nil }

        let makes = try await menu("menu/make", ["year": "\(year)"])
        guard let make = makes.first(where: { squash($0) == squash(q.make) })
                ?? makes.first(where: { squash($0).hasPrefix(squash(q.make)) || squash(q.make).hasPrefix(squash($0)) })
        else { return nil }

        // Variants of this model: "Model 3" → "Model 3 Long Range AWD", … —
        // leading whole words that spell the model, ignoring spaces and
        // hyphens ("F150" = "F-150"), so "Model 3" never picks up "Model 3X".
        let wanted = squash(q.model)
        let models = try await menu("menu/model", ["year": "\(year)", "make": make]).filter { name in
            var spelled = ""
            for w in words(name) {
                spelled += w
                if spelled == wanted { return true }
                if !wanted.hasPrefix(spelled) { return false }
            }
            return false
        }
        guard !models.isEmpty else { return nil }

        let hints = Set(words(q.trim) + words(q.driveType).map(driveAlias) + words(q.engine))
        let ranked = models.sorted { score($0, hints, powertrain) > score($1, hints, powertrain) }

        // Read the vehicles behind the best few model names (each has one per
        // engine/transmission option), then pick the best fit.
        var best: (score: Int, figures: Figures)?
        for model in ranked.prefix(4) {
            let options = try await menuItems("menu/options", ["year": "\(year)", "make": make, "model": model])
            for option in options.prefix(8) {
                guard let v = try await vehicle(option.value), powertrain.matches(v.atvType, v.fuelType) else { continue }
                let figures: Figures
                switch powertrain {
                case .electric, .plugIn:
                    guard let r = Int(v.range), r > 0 else { continue }
                    figures = Figures(range: r, combinedMPG: nil)
                case .hybrid, .diesel:
                    guard let mpg = Int(v.comb08), mpg > 0 else { continue }
                    figures = Figures(range: nil, combinedMPG: mpg)
                }
                let s = score(model, hints, powertrain) * 10 + engineScore(option.text, q.engine)
                if best == nil || s > best!.score { best = (s, figures) }
            }
            if best != nil { break }  // the best-named model had a fit
        }
        return best?.figures
    }

    // MARK: Powertrain

    enum Powertrain {
        case electric, plugIn, hybrid, diesel

        init?(fuelType: String) {
            let s = fuelType.lowercased()
            if s.contains("plug") { self = .plugIn }
            else if s.contains("hybrid") { self = .hybrid }
            else if s.contains("diesel") { self = .diesel }
            else if s.contains("electric") { self = .electric }
            else { return nil }
        }

        func matches(_ atvType: String, _ fuelType: String) -> Bool {
            switch self {
            case .electric: return atvType == "EV"
            case .plugIn: return atvType == "Plug-in Hybrid"
            case .hybrid: return atvType == "Hybrid"
            case .diesel: return atvType == "Diesel" || fuelType == "Diesel"
            }
        }
    }

    // MARK: Matching

    private static func score(_ model: String, _ hints: Set<String>, _ p: Powertrain) -> Int {
        let w = Set(words(model).map(driveAlias))
        var s = w.intersection(hints).count * 2
        // The model name often says "Hybrid"; a gas variant of the same model
        // would then fail the powertrain check anyway, but prefer the right one.
        if p == .hybrid, w.contains("hybrid") { s += 3 }
        if p == .plugIn, w.contains("plug") || w.contains("prime") { s += 3 }
        // Fewer extra words = a plainer variant when the car names no trim.
        return s * 4 - max(0, w.count - hints.count)
    }

    /// "Auto 10-spd, 6 cyl, 3.0 L, Diesel, Turbo" vs the car's "3.0L V6".
    private static func engineScore(_ option: String, _ engine: String) -> Int {
        guard let displ = engine.range(of: #"\d+\.\d"#, options: .regularExpression) else { return 0 }
        return option.contains("\(engine[displ]) L") ? 5 : 0
    }

    private static func driveAlias(_ word: String) -> String {
        switch word {
        case "4x4", "4wd": return "4wd"
        case "awd", "allwheel": return "awd"
        case "fwd", "rwd", "2wd": return "2wd"
        default: return word
        }
    }

    private static func words(_ s: String) -> [String] {
        s.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    private static func squash(_ s: String) -> String { words(s).joined() }

    // MARK: Network

    private struct MenuItem: Decodable { let text: String; let value: String }

    /// The service returns one item as an object and several as an array.
    private struct Menu: Decodable {
        let items: [MenuItem]
        enum CodingKeys: String, CodingKey { case menuItem }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            if let many = try? c.decode([MenuItem].self, forKey: .menuItem) { items = many }
            else if let one = try? c.decode(MenuItem.self, forKey: .menuItem) { items = [one] }
            else { items = [] }
        }
    }

    private struct Vehicle: Decodable {
        let range: String
        let comb08: String
        let atvType: String
        let fuelType: String
        enum CodingKeys: String, CodingKey { case range, comb08, atvType, fuelType }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            func str(_ k: CodingKeys) -> String {
                (try? c.decode(String.self, forKey: k))
                    ?? (try? c.decode(Int.self, forKey: k)).map(String.init) ?? ""
            }
            range = str(.range); comb08 = str(.comb08); atvType = str(.atvType); fuelType = str(.fuelType)
        }
    }

    private static func get(_ path: String, _ params: [String: String] = [:]) async throws -> Data? {
        var url = URLComponents(string: "\(base)/\(path)")!
        if !params.isEmpty { url.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) } }
        var request = URLRequest(url: url.url!, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        // An empty menu comes back as the literal `null`.
        return data.count > 4 ? data : nil
    }

    private static func menuItems(_ path: String, _ params: [String: String]) async throws -> [MenuItem] {
        guard let data = try await get(path, params) else { return [] }
        return (try? JSONDecoder().decode(Menu.self, from: data))?.items ?? []
    }

    private static func menu(_ path: String, _ params: [String: String]) async throws -> [String] {
        try await menuItems(path, params).map(\.value)
    }

    private static func vehicle(_ id: String) async throws -> Vehicle? {
        guard let data = try await get(id) else { return nil }
        return try? JSONDecoder().decode(Vehicle.self, from: data)
    }
}
