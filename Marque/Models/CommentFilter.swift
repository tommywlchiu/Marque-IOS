import Foundation

/// Client-side mirror of the server's comment filter
/// (`functions/src/commentFilter.ts`), App Store guideline 1.2.
///
/// `CommentStore.post` runs this before writing, so a normal user gets an
/// immediate "not allowed" instead of a comment that silently vanishes when
/// `onCarCommentWritten` deletes it server-side. **The server is
/// authoritative**; this copy only improves the UX. The lists and the
/// algorithm must stay identical to the TypeScript module. Change both in the
/// same commit.
///
/// A token filter, not a substring filter: "class", "Scunthorpe" and
/// "cockpit" pass. "retard" (ignition timing), "tranny" (transmission) and
/// "chink" (paint damage) are deliberately absent: they're everyday car
/// vocabulary.
enum CommentFilter {
    static let blockedTerms: Set<String> = [
        // profanity
        "cunt", "cunts", "twat", "twats", "wanker", "wankers", "pussy", "pussies",
        "cock", "cocks", "dickhead", "dickheads", "bastard", "bastards",
        "fuk", "fuks", "phuck", "phuk",
        "fag", "fags", "dyke", "dykes",
        // slurs
        "nigga", "niggas", "kike", "kikes", "spic", "spics", "wetback", "wetbacks",
        "gook", "gooks", "coon", "coons",
        // violence / self-harm
        "rape", "raped", "rapist", "rapists", "kys",
    ]

    static let blockedStems: [String] = [
        "fuck", "shit", "bitch", "asshole", "cocksuck", "whore", "slut",
        "nigger", "faggot",
    ]

    static let blockedPhrases: [String] = [
        "kill yourself", "kill urself",
    ]

    /// Look-alike letters from other scripts, folded to the Latin letter they
    /// imitate. Applied after lowercasing. Same table as HOMOGLYPHS in TS.
    static let homoglyphs: [Character: Character] = [
        // Cyrillic
        "а": "a", "е": "e", "о": "o", "р": "p", "с": "c", "у": "y", "х": "x",
        "к": "k", "м": "m", "т": "t", "і": "i", "ј": "j", "ѕ": "s", "ԁ": "d", "ц": "u",
        // Greek
        "α": "a", "ε": "e", "ι": "i", "κ": "k", "ν": "v", "ο": "o", "ρ": "p",
        "τ": "t", "υ": "u", "χ": "x",
        // Latin
        "ƒ": "f",
    ]

    private static let leet: [Character: Character] = [
        "0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t",
        "@": "a", "$": "s", "!": "i",
    ]

    /// True if `text` contains a blocked word, stem or phrase.
    static func containsBlockedTerm(_ text: String) -> Bool {
        let tokens = splitTokens(text)
        if tokens.contains(where: tokenIsBlocked) || joinedRuns(tokens).contains(where: tokenIsBlocked) {
            return true
        }
        let sentence = " " + phraseTokens(tokens).joined(separator: " ") + " "
        return blockedPhrases.contains { sentence.contains(" \($0) ") }
    }

    /// Convenience inverse of `containsBlockedTerm`.
    static func isAllowed(_ text: String) -> Bool { !containsBlockedTerm(text) }

    /// Mirrors splitTokens(): lowercase, NFKD, drop combining marks and format
    /// characters (zero-width, bidi controls, BOM), fold homoglyphs, leetspeak
    /// on runs that touch a letter (a run with "!" needs letters on both
    /// sides), split into [a-z]+ tokens.
    static func splitTokens(_ text: String) -> [String] {
        let decomposed = text.lowercased().decomposedStringWithCompatibilityMapping
        var scalars = String.UnicodeScalarView()
        for scalar in decomposed.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .nonspacingMark, .spacingMark, .enclosingMark, .format:
                continue
            default:
                scalars.append(scalar)
            }
        }
        let chars = String(scalars).map { homoglyphs[$0] ?? $0 }

        func isLetter(_ i: Int) -> Bool {
            guard i >= 0, i < chars.count else { return false }
            let c = chars[i]
            return c >= "a" && c <= "z"
        }

        var mapped = ""
        var i = 0
        while i < chars.count {
            if leet[chars[i]] != nil {
                var j = i
                while j < chars.count, leet[chars[j]] != nil { j += 1 }
                let before = isLetter(i - 1)
                let after = isLetter(j)
                let hasBang = chars[i..<j].contains("!")
                let touchesLetter = hasBang ? (before && after) : (before || after)
                for k in i..<j { mapped.append(touchesLetter ? leet[chars[k]]! : " ") }
                i = j
            } else {
                mapped.append(isLetter(i) ? chars[i] : " ")
                i += 1
            }
        }
        return mapped.split(separator: " ").map(String.init)
    }

    /// Every run of 3+ single-letter tokens, joined ("f u c k" -> "fuck").
    private static func joinedRuns(_ tokens: [String]) -> [String] {
        var out: [String] = []
        var run: [String] = []
        func flush() {
            if run.count >= 3 { out.append(run.joined()) }
            run = []
        }
        for t in tokens {
            if t.count == 1 { run.append(t) } else { flush() }
        }
        flush()
        return out
    }

    /// Tokens in order, runs of 3+ single letters joined in place.
    private static func phraseTokens(_ tokens: [String]) -> [String] {
        var out: [String] = []
        var run: [String] = []
        func flush() {
            if run.count >= 3 { out.append(run.joined()) } else { out.append(contentsOf: run) }
            run = []
        }
        for t in tokens {
            if t.count == 1 { run.append(t) } else { flush(); out.append(t) }
        }
        flush()
        return out
    }

    private static func collapseRepeats(_ s: String) -> String {
        var out = ""
        for c in s where out.last != c { out.append(c) }
        return out
    }

    private static func hasTripleRun(_ s: String) -> Bool {
        let a = Array(s)
        guard a.count >= 3 else { return false }
        for i in 2..<a.count where a[i] == a[i - 1] && a[i] == a[i - 2] { return true }
        return false
    }

    private static let collapsedTerms = Set(blockedTerms.map(collapseRepeats))
    private static let collapsedStems = blockedStems.map(collapseRepeats)

    private static func tokenIsBlocked(_ token: String) -> Bool {
        if blockedTerms.contains(token) { return true }
        if blockedStems.contains(where: { token.contains($0) }) { return true }
        if hasTripleRun(token) {
            let collapsed = collapseRepeats(token)
            if collapsedTerms.contains(collapsed) { return true }
            if collapsedStems.contains(where: { collapsed.contains($0) }) { return true }
        }
        return false
    }

    // MARK: - Invisible characters (mirrors the comment rule in firestore.rules)

    /// Scalars the comment rule rejects outright: zero-width space/non-joiner,
    /// LRM/RLM, bidi embeddings/overrides, word joiner and invisible operators,
    /// BOM. U+200D (zero-width joiner) is NOT here: emoji sequences need it.
    static func isRejectedInvisible(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x200B, 0x200C, 0x200E, 0x200F, 0x202A...0x202E, 0x2060...0x2064, 0xFEFF:
            return true
        default:
            return false
        }
    }

    /// `text` with every rule-rejected invisible scalar removed. CommentStore
    /// applies this before posting, so pasted text carrying them isn't denied.
    static func removingRejectedInvisibles(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for s in text.unicodeScalars where !isRejectedInvisible(s) { scalars.append(s) }
        return String(scalars)
    }
}
