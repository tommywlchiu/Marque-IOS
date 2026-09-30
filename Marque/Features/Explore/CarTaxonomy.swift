import Foundation

/// Single source of truth for car categorization (the Explore category
/// chips) and model-aware search text handling (`SearchResultsView`).
/// Pure and stateless -- no store, no view, no Firestore -- so it can be
/// exercised by the `#if DEBUG` self-check at the bottom without any
/// environment setup.
enum CarTaxonomy {

    // MARK: - Normalization

    /// Lowercases and splits on any run of non-alphanumeric characters
    /// (spaces, hyphens, punctuation), producing word tokens.
    static func tokens(_ s: String) -> [String] {
        s.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }

    /// Fully squashed, punctuation-free, lowercase form used for
    /// whole-string equality/contains checks. An adjacent "gt","r" token
    /// pair is merged into a single "gtr" token before joining, so
    /// "GT-R", "GT R" and "GTR" all squash to the same "gtr" regardless
    /// of whether the original had a hyphen, a space, or nothing.
    /// "911 Turbo S" squashes to "911turbos".
    static func squash(_ s: String) -> String {
        mergeGTR(tokens(s)).joined()
    }

    private static func mergeGTR(_ toks: [String]) -> [String] {
        var merged: [String] = []
        var i = 0
        while i < toks.count {
            if i + 1 < toks.count, toks[i] == "gt", toks[i + 1] == "r" {
                merged.append("gtr")
                i += 2
            } else {
                merged.append(toks[i])
                i += 1
            }
        }
        return merged
    }

    // MARK: - Make lists
    //
    // Moved here from `ExploreCategory` so every make-based categorization
    // rule lives in one place. Values are pre-squashed so a make stored
    // with different spacing/punctuation ("Rolls-Royce" vs "Rolls Royce",
    // "Alfa Romeo") still matches -- squashing the car's own make at the
    // call site (`isJDM`, etc.) keeps that symmetric.

    static let jdmMakes: Set<String> = [
        "toyota", "honda", "nissan", "mazda", "subaru", "mitsubishi",
        "lexus", "acura", "infiniti", "suzuki", "isuzu", "daihatsu",
    ]

    static let europeanMakes: Set<String> = [
        "bmw", "mercedes", "mercedesbenz", "audi", "volkswagen", "porsche",
        "ferrari", "lamborghini", "maserati", "fiat", "alfaromeo", "volvo",
        "peugeot", "renault", "citroen", "mini", "bentley", "rollsroyce",
        "bugatti",
    ]

    static let americanMakes: Set<String> = [
        "ford", "chevrolet", "chevy", "dodge", "jeep", "cadillac", "gmc",
        "lincoln", "chrysler", "ram", "buick", "tesla",
    ]

    static let classicYearCutoff = 1990

    static func isJDM(make: String) -> Bool { jdmMakes.contains(squash(make)) }
    static func isEuropean(make: String) -> Bool { europeanMakes.contains(squash(make)) }
    static func isAmerican(make: String) -> Bool { americanMakes.contains(squash(make)) }
    static func isClassic(year: String) -> Bool { (Int(year) ?? 2000) < classicYearCutoff }

    // MARK: - Supercars

    /// Whole-brand exotic makes: everything the manufacturer sells is
    /// supercar/hypercar tier, so no model-level check is needed.
    ///
    /// Rolls-Royce is included: extremely low volume, fully coachbuilt,
    /// $300k+ even at the "entry" Ghost -- "exotic" fits by rarity and
    /// price even though the lineup (Cullinan SUV, Phantom sedan) isn't
    /// performance-focused. Bentley is deliberately excluded: higher
    /// volume, a lower starting price (Continental GT ~$200k) than
    /// Rolls-Royce's cheapest model, and it reads to most buyers as
    /// "luxury GT", not "exotic".
    static let exoticWholeBrandMakes: Set<String> = [
        "ferrari", "lamborghini", "mclaren", "bugatti", "pagani",
        "koenigsegg", "astonmartin", "rollsroyce", "rimac", "czinger",
        "hennessey", "ssc", "noble", "spyker", "detomaso", "gordonmurray",
        "gordonmurrayautomotive",
    ]

    /// Maserati and Lotus are deliberately NOT in `exoticWholeBrandMakes`:
    /// Maserati's current lineup is mostly luxury sedans/SUVs (Ghibli,
    /// Levante, Quattroporte, Grecale), and Lotus still sells lightweight
    /// but attainable sports cars in the Elise/Exige lineage. Only their
    /// genuine halo models count as Supercars. Emira is Lotus's current
    /// "affordable" sports car rather than a hypercar, but the task names
    /// it explicitly alongside Evija, so it's included; Evija (Lotus's
    /// ~$2M electric hypercar) is the much clearer case of the two.
    private static func isExoticHaloModel(make: String, model: String, trim: String) -> Bool {
        let combined = squash(model) + squash(trim)
        switch squash(make) {
        case "maserati":
            return combined.contains("mc20")
        case "lotus":
            return combined.contains("evija") || combined.contains("emira")
        default:
            return false
        }
    }

    /// Halo/flagship models from otherwise mainstream manufacturers.
    /// Matched on *tokens* of the model + trim fields, never on a single
    /// squashed blob -- squashing away word boundaries would, for
    /// example, make a `.contains("carreragt")` check on "911 Carrera
    /// GTS" (squashed: "911carreragts") true, since "carreragts" starts
    /// with the same 9 characters as "carreragt". Token equality avoids
    /// that: "gts" and "gt" are different tokens.
    private static func isMainstreamHaloModel(make: String, model: String, trim: String) -> Bool {
        let toks = mergeGTR(tokens(model) + tokens(trim))
        func has(_ t: String) -> Bool { toks.contains(t) }
        func hasAdjacent(_ a: String, _ b: String) -> Bool {
            zip(toks, toks.dropFirst()).contains { $0 == a && $1 == b }
        }

        switch squash(make) {
        case "porsche":
            // 911 GT2 / GT3 / Turbo / Turbo S -- bare "turbo" also covers
            // the "S" variant, since the extra "s" token doesn't change
            // whether "turbo" itself is present. "Carrera GT" is a
            // standalone flagship model (2004-06), matched as an exact
            // adjacent token pair so it can't be confused with "911
            // Carrera GTS" (token "gts" != token "gt"). 918 is the 918
            // Spyder hypercar. Plain "911 Carrera"/"Carrera S"/"GTS" all
            // correctly fall through to `false`.
            let is911Flagship = has("911") && (has("gt2") || has("gt3") || has("turbo"))
            return is911Flagship || hasAdjacent("carrera", "gt") || has("918")
        case "mercedes", "mercedesbenz", "mercedesamg":
            // "AMG GT" / "GT Black Series" need both tokens present; bare
            // "AMG" (as on a C63 AMG or E63 AMG -- fast sedans, not halo
            // cars) must NOT match on its own.
            let isAMGGT = has("amg") && has("gt")
            return isAMGGT || has("sls") || has("slr") || (has("amg") && has("one"))
        case "ford":
            // The "Ford GT" supercar's *model* field is exactly "GT". A
            // token-containment check on model+trim would also catch
            // "Mustang GT" (model "Mustang", trim "GT"), a mainstream V8
            // pony car, not a halo car -- so this requires the model
            // alone (no trim, no other words) to squash to exactly "gt".
            return squash(model) == "gt"
        case "chevrolet", "chevy":
            return has("corvette") && (has("z06") || has("zr1") || (squash(model) + squash(trim)).contains("eray"))
        case "dodge":
            return has("viper")
        case "acura", "honda":
            return has("nsx")
        case "lexus":
            // LFA outright, or the LC coupe's top "F" trim -- guarded to
            // an *exact* trim squash of "f" so the common "F Sport"
            // appearance package (ES, IS, RX, etc. -- not a halo car)
            // doesn't also match via a loose token/contains check.
            return has("lfa") || (has("lc") && squash(trim) == "f")
        case "nissan":
            // Covers both the modern R35 and the older (R32-R34) GT-R --
            // this only checks the model text; the specific generation
            // nicknames (R35/R34/Godzilla) are handled by the search
            // alias table below, not by classification.
            return (squash(model) + squash(trim)).contains("gtr")
        case "audi":
            return has("r8")
        case "bmw":
            // M1 (the original '70s-'80s mid-engine halo car) and i8
            // only -- NOT M2/M3/M4/M5, which are mainstream M-performance
            // cars, not supercars.
            return has("m1") || has("i8")
        default:
            // Toyota GR Supra is deliberately absent: a genuine sports
            // car, not a supercar (it's still searchable/aliasable, see
            // `searchAliases`, just not tagged Supercars).
            return false
        }
    }

    static func isSupercar(make: String, model: String, trim: String) -> Bool {
        if exoticWholeBrandMakes.contains(squash(make)) { return true }
        if isExoticHaloModel(make: make, model: model, trim: trim) { return true }
        if isMainstreamHaloModel(make: make, model: model, trim: trim) { return true }
        return false
    }

    // MARK: - Search aliases

    struct AliasHint {
        /// Squashed make, when the alias implies one.
        let make: String?
        /// Squashed model (or model+trim family), when the alias implies
        /// a specific model rather than just a brand.
        let model: String?
    }

    /// Common nicknames -> a (make, model) hint, both already squashed.
    /// Looked up by `squash(query)`, so lookup is a dictionary hit, not a
    /// fuzzy match. "m3" intentionally does NOT collide with "model 3":
    /// `squash("model 3")` is "model3", a different string than the "m3"
    /// key, so Tesla's Model 3 falls through to the plain model-text
    /// match in `matchTier` instead of ever consulting this table -- no
    /// special-casing needed.
    static let searchAliases: [String: AliasHint] = [
        "r35": AliasHint(make: "nissan", model: "gtr"),
        "r34": AliasHint(make: "nissan", model: "gtr"),
        "godzilla": AliasHint(make: "nissan", model: "gtr"),
        "supra": AliasHint(make: "toyota", model: "supra"),
        "mk4": AliasHint(make: "toyota", model: "supra"),
        "a80": AliasHint(make: "toyota", model: "supra"),
        "a90": AliasHint(make: "toyota", model: "supra"),
        "typer": AliasHint(make: "honda", model: "civictyper"),
        "ctr": AliasHint(make: "honda", model: "civictyper"),
        "vette": AliasHint(make: "chevrolet", model: "corvette"),
        "lambo": AliasHint(make: "lamborghini", model: nil),
        "benz": AliasHint(make: "mercedes", model: nil),
        "merc": AliasHint(make: "mercedes", model: nil),
        "beemer": AliasHint(make: "bmw", model: nil),
        "bimmer": AliasHint(make: "bmw", model: nil),
        "stang": AliasHint(make: "ford", model: "mustang"),
        "m3": AliasHint(make: "bmw", model: "m3"),
    ]

    static func aliasHint(for query: String) -> AliasHint? {
        searchAliases[squash(query)]
    }

    /// Squashed forms of the "supercars"/"supercar" search term --
    /// typing either into search returns the Supercars set (see
    /// `SearchResultsView.filteredCars`).
    static let supercarsSearchTerms: Set<String> = ["supercars", "supercar"]

    /// Squashed forms of the "modified"/"mods" search term -- typing either
    /// into search returns every car with at least one mod (see
    /// `SearchResultsView.filteredCars`), same shape as `supercarsSearchTerms`.
    static let modifiedSearchTerms: Set<String> = ["modified", "mods"]

    // MARK: - Search ranking

    enum SearchMatchTier: Int, Comparable {
        case model = 0
        case make = 1
        case other = 2

        static func < (lhs: SearchMatchTier, rhs: SearchMatchTier) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// Model-aware match tier for one car against a query, or `nil` if the
    /// car doesn't match the query at all. All comparisons are on
    /// `squash`ed text, so punctuation/case/spacing never matters -- "gtr",
    /// "GT-R" and "gt r" all find a Nissan GT-R; "911" finds a Porsche 911.
    /// `mods`: this car's mod (name, brand) pairs, lowest-priority text match
    /// -- a query matching only a mod name/brand (e.g. "akrapovic", "HKS")
    /// ranks below a trim/year/username match on the same car, but the car
    /// still surfaces. Defaults to empty so existing callers/self-checks
    /// that don't pass mods keep compiling unchanged.
    static func matchTier(
        query: String,
        make: String,
        model: String,
        trim: String,
        year: String,
        ownerUsername: String,
        mods: [(name: String, brand: String?)] = []
    ) -> SearchMatchTier? {
        let q = squash(query)
        guard !q.isEmpty else { return .other }

        let sMake = squash(make)
        let sModel = squash(model)
        let sTrim = squash(trim)
        let sModelTrim = sModel + sTrim
        let hint = aliasHint(for: query)

        // Loose (non-equality) `contains` checks are gated to queries of
        // 2+ characters so a one-letter query doesn't promote every car
        // in the feed into the "model" tier.
        let allowLooseContains = q.count >= 2

        // Tier: model match. Either the query textually is the model
        // (checked both directions, so a short query like "911" matches
        // the model field "911", and a longer typo-tolerant query still
        // matches a shorter model field), or an alias resolves to this
        // car's exact model family.
        let directModelMatch = !sModel.isEmpty && (
            sModel == q || sModelTrim == q ||
            (allowLooseContains && (sModel.contains(q) || q.contains(sModel)))
        )
        let aliasModelMatch: Bool = {
            guard let hint, let hintModel = hint.model else { return false }
            guard hint.make == nil || hint.make == sMake else { return false }
            return sModelTrim.contains(hintModel) || hintModel.contains(sModel)
        }()
        if directModelMatch || aliasModelMatch {
            return .model
        }

        // Tier: make match. Either the query textually is the make, or an
        // alias resolves to just a make with no specific model (e.g.
        // "lambo", "beemer").
        let directMakeMatch = !sMake.isEmpty && (
            sMake == q || (allowLooseContains && (sMake.contains(q) || q.contains(sMake)))
        )
        let aliasMakeMatch = hint?.make == sMake && hint?.model == nil && sMake != ""
        if directMakeMatch || aliasMakeMatch {
            return .make
        }

        // Tier: anything else that textually matches somewhere (trim,
        // year, owner username, or a mod's name/brand).
        let sMods = mods.map { (squash($0.name), $0.brand.map(squash)) }
        if allowLooseContains {
            if sTrim.contains(q) || squash(year).contains(q) || squash(ownerUsername).contains(q) {
                return .other
            }
            if sMods.contains(where: { name, brand in name.contains(q) || (brand?.contains(q) ?? false) }) {
                return .other
            }
        } else {
            if sTrim == q || squash(year) == q || squash(ownerUsername) == q {
                return .other
            }
            if sMods.contains(where: { name, brand in name == q || brand == q }) {
                return .other
            }
        }
        return nil
    }

    // MARK: - Popular models

    struct PopularModelGroup: Identifiable, Equatable {
        /// Squashed "<make><model>" key -- the grouping key and the
        /// filter key used by `ExploreView`.
        let id: String
        /// Representative (original-cased) make/model text for display,
        /// taken from the first car encountered in the group.
        let make: String
        let model: String
        let count: Int
    }

    /// Groups cars by normalized make+model (trim is intentionally not
    /// part of the key), keeping only groups with at least `minCount`
    /// cars, sorted by count descending -- ties keep the input order
    /// (`sorted` is stable as of Swift 5), which is `cars`' existing
    /// newest-first order -- and capped at `limit`.
    static func popularModelGroups(
        from cars: [PublicCar],
        minCount: Int = 2,
        limit: Int = 6
    ) -> [PopularModelGroup] {
        var order: [String] = []
        var representative: [String: (make: String, model: String)] = [:]
        var counts: [String: Int] = [:]

        for car in cars {
            guard !car.model.isEmpty else { continue }
            let key = squash(car.make) + squash(car.model)
            guard !key.isEmpty else { continue }
            if counts[key] == nil {
                order.append(key)
                representative[key] = (car.make, car.model)
            }
            counts[key, default: 0] += 1
        }

        return order
            .compactMap { key -> PopularModelGroup? in
                guard let count = counts[key], count >= minCount, let rep = representative[key] else { return nil }
                return PopularModelGroup(id: key, make: rep.make, model: rep.model, count: count)
            }
            .sorted { $0.count > $1.count }
            .prefix(limit)
            .map { $0 }
    }
}

// MARK: - Self-check

#if DEBUG
extension CarTaxonomy {
    /// No XCTest target exists in this project (see CLAUDE.md); this is
    /// the documented substitute for the representative cases called out
    /// in the task. Call manually from a debug entry point if needed --
    /// nothing in the app invokes this automatically.
    static func _selfCheck() {
        // Normalization / squash equivalence.
        assert(squash("GT-R") == squash("GTR"))
        assert(squash("GTR") == squash("gt r"))
        assert(squash("GT-R") == "gtr")

        // Supercar classification.
        assert(isSupercar(make: "Nissan", model: "GT-R", trim: "Premium"))
        assert(isSupercar(make: "Nissan", model: "GTR", trim: ""))
        assert(!isSupercar(make: "Toyota", model: "GR Supra", trim: ""))
        assert(!isSupercar(make: "Porsche", model: "911", trim: "Carrera"))
        assert(isSupercar(make: "Porsche", model: "911", trim: "Turbo S"))
        assert(isSupercar(make: "Porsche", model: "911", trim: "GT3"))
        assert(!isSupercar(make: "Porsche", model: "911", trim: "Carrera GTS"))
        assert(isSupercar(make: "Porsche", model: "Carrera GT", trim: ""))
        assert(isSupercar(make: "Ferrari", model: "Roma", trim: "")) // whole-brand exotic
        assert(!isSupercar(make: "Maserati", model: "Ghibli", trim: ""))
        assert(isSupercar(make: "Maserati", model: "MC20", trim: ""))
        assert(!isSupercar(make: "Lotus", model: "Elise", trim: ""))
        assert(isSupercar(make: "Lotus", model: "Evija", trim: ""))
        assert(!isSupercar(make: "Ford", model: "Mustang", trim: "GT"))
        assert(isSupercar(make: "Ford", model: "GT", trim: ""))
        assert(!isSupercar(make: "Mercedes-Benz", model: "C63", trim: "AMG"))
        assert(isSupercar(make: "Mercedes-Benz", model: "AMG GT", trim: "Black Series"))
        assert(!isSupercar(make: "BMW", model: "M3", trim: "Competition"))
        assert(isSupercar(make: "BMW", model: "M1", trim: ""))
        assert(!isSupercar(make: "Lexus", model: "RX", trim: "F Sport"))
        assert(isSupercar(make: "Lexus", model: "LC", trim: "F"))
        assert(!isSupercar(make: "Bentley", model: "Continental GT", trim: ""))
        assert(isSupercar(make: "Rolls-Royce", model: "Ghost", trim: ""))

        // Search: model-text matching.
        assert(matchTier(query: "gtr", make: "Nissan", model: "GT-R", trim: "", year: "2020", ownerUsername: "x") == .model)
        assert(matchTier(query: "GT-R", make: "Nissan", model: "GTR", trim: "", year: "2020", ownerUsername: "x") == .model)
        assert(matchTier(query: "911", make: "Porsche", model: "911", trim: "Carrera", year: "2018", ownerUsername: "x") == .model)

        // Search: alias table.
        assert(matchTier(query: "r35", make: "Nissan", model: "GT-R", trim: "", year: "2020", ownerUsername: "x") == .model)
        assert(matchTier(query: "godzilla", make: "Nissan", model: "GT-R", trim: "", year: "2020", ownerUsername: "x") == .model)
        assert(matchTier(query: "vette", make: "Chevrolet", model: "Corvette", trim: "Z06", year: "2023", ownerUsername: "x") == .model)
        assert(matchTier(query: "lambo", make: "Lamborghini", model: "Huracan", trim: "", year: "2021", ownerUsername: "x") == .make)

        // Search: "m3" vs "model 3" must not collide.
        assert(aliasHint(for: "m3")?.make == "bmw")
        assert(aliasHint(for: "model 3") == nil)
        assert(matchTier(query: "m3", make: "BMW", model: "M3", trim: "Competition", year: "2021", ownerUsername: "x") == .model)
        assert(matchTier(query: "model 3", make: "Tesla", model: "Model 3", trim: "", year: "2022", ownerUsername: "x") == .model)
        assert(matchTier(query: "m3", make: "Tesla", model: "Model 3", trim: "", year: "2022", ownerUsername: "x") == nil)

        // Search: "supercars" as a literal search term is handled by the
        // caller (`SearchResultsView`) via `supercarsSearchTerms`, not by
        // `matchTier` -- documented here since it's part of the same
        // search-matching contract.
        assert(supercarsSearchTerms.contains(squash("Supercars")))
        assert(modifiedSearchTerms.contains(squash("Modified")))

        // Search: a mod name/brand match is the lowest tier, but still matches.
        let akrapovicMod = [(name: "Akrapovič Evolution Exhaust", brand: Optional("Akrapovič"))]
        assert(matchTier(query: "akrapovic", make: "Porsche", model: "911", trim: "", year: "2020", ownerUsername: "x", mods: akrapovicMod) == .other)
        let hksMod = [(name: "Turbo Kit", brand: Optional("HKS"))]
        assert(matchTier(query: "hks", make: "Toyota", model: "Corolla", trim: "", year: "2020", ownerUsername: "x", mods: hksMod) == .other)
        assert(matchTier(query: "hks", make: "Toyota", model: "Corolla", trim: "", year: "2020", ownerUsername: "x", mods: []) == nil)

        // Popular models: grouping ignores trim, keeps only 2+, sorted by count.
        let cars = [
            PublicCar.previewStub(make: "Nissan", model: "GT-R"),
            PublicCar.previewStub(make: "Nissan", model: "GT-R"),
            PublicCar.previewStub(make: "Toyota", model: "Supra"),
        ]
        let groups = popularModelGroups(from: cars, minCount: 2)
        assert(groups.count == 1 && groups.first?.count == 2 && groups.first?.model == "GT-R")
    }
}

private extension PublicCar {
    /// Minimal stand-in for the self-check above -- only the fields
    /// `popularModelGroups` reads are set.
    static func previewStub(make: String, model: String) -> PublicCar {
        let json: [String: Any] = [
            "carId": UUID().uuidString,
            "ownerUID": "u", "ownerUsername": "u",
            "make": make, "model": model, "year": "2020",
            "color": "", "mileage": "", "trim": "", "bodyStyle": "",
            "driveType": "", "engine": "", "fuelType": "", "transmission": "",
            "notes": "", "photoOffsetY": 0.0, "serviceHistory": [],
            "photoURLs": [], "likeCount": 0, "weeklyLikeCount": 0, "commentCount": 0,
        ]
        let data = try! JSONSerialization.data(withJSONObject: json)
        return try! JSONDecoder().decode(PublicCar.self, from: data)
    }
}
#endif
