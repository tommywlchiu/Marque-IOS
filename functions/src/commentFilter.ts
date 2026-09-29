// ============================================================================
// Comment filter — App Store guideline 1.2 (user-generated content: filtering).
// ============================================================================
//
// Used by onCarCommentWritten: a comment that matches is deleted server-side
// right after it's created, before it's counted or anyone is notified.
//
// The iOS client mirrors this exact algorithm and word list in
// Marque/Models/CommentFilter.swift so CommentStore.post can reject a comment
// before it's written. THE SERVER IS AUTHORITATIVE: a modified client can skip
// the local check, this one it can't. When you change a list or the algorithm
// here, change the Swift copy in the same commit.
//
// Deliberately a word/token filter, not a substring filter, so ordinary words
// that happen to contain a bad one ("class", "Scunthorpe", "cockpit") pass.
// Only BLOCKED_STEMS match inside a longer token, and each of those was
// checked for innocent English words that contain it.
//
// Car-specific exclusions — these look like obvious list entries but are
// everyday automotive vocabulary, so they are NOT on the list:
//   "retard"  — ignition timing ("retard the timing a few degrees")
//   "tranny"  — transmission ("tranny fluid")
//   "chink"   — "a chink in the paint"

/** Exact-token matches (after normalization). */
export const BLOCKED_TERMS: readonly string[] = [
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
];

/** Matched anywhere inside a normalized token. */
export const BLOCKED_STEMS: readonly string[] = [
  "fuck", "shit", "bitch", "asshole", "cocksuck", "whore", "slut",
  "nigger", "faggot",
];

/** Matched against the normalized token sequence joined with single spaces. */
export const BLOCKED_PHRASES: readonly string[] = [
  "kill yourself", "kill urself",
];

// Leetspeak substitutions. Applied only to a run of these characters that
// touches a letter ("sh1t", "a$$", "$hit"), never to a free-standing number —
// otherwise "0 to 60 in 4.5 s" would read as letters. A run containing "!"
// must have a letter on BOTH sides ("sh!t"), so ordinary end-of-sentence
// punctuation ("Nice car!") stays punctuation.
const LEET: Record<string, string> = {
  "0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t",
  "@": "a", "$": "s", "!": "i",
};

// Look-alike letters from other scripts, folded to the Latin letter they
// imitate ("fцck", "fuсk" with a Cyrillic с). Applied after lowercasing.
// Only letters that are visually near-identical in common fonts.
export const HOMOGLYPHS: Readonly<Record<string, string>> = {
  // Cyrillic
  "а": "a", "е": "e", "о": "o", "р": "p", "с": "c", "у": "y", "х": "x",
  "к": "k", "м": "m", "т": "t", "і": "i", "ј": "j", "ѕ": "s", "ԁ": "d", "ц": "u",
  // Greek
  "α": "a", "ε": "e", "ι": "i", "κ": "k", "ν": "v", "ο": "o", "ρ": "p",
  "τ": "t", "υ": "u", "χ": "x",
  // Latin
  "ƒ": "f",
};

const isLetter = (c: string | undefined): boolean => c !== undefined && c >= "a" && c <= "z";

/**
 * Lowercases, NFKD-decomposes (fullwidth "ｆ" -> "f"), strips combining marks
 * (diacritics) and format characters (\p{Cf}: zero-width spaces/joiners, bidi
 * overrides, BOM, which otherwise split a word invisibly: "f<ZWSP>uck"), folds
 * homoglyphs, applies leetspeak, and splits into [a-z]+ tokens, in order.
 */
export function splitTokens(text: string): string[] {
  const folded = text
    .toLowerCase()
    .normalize("NFKD")
    .replace(/[\p{M}\p{Cf}]+/gu, "");
  const chars = Array.from(folded).map((c) => HOMOGLYPHS[c] ?? c);

  let mapped = "";
  let i = 0;
  while (i < chars.length) {
    if (chars[i] in LEET) {
      let j = i;
      while (j < chars.length && chars[j] in LEET) j++;
      const before = isLetter(chars[i - 1]);
      const after = isLetter(chars[j]);
      const hasBang = chars.slice(i, j).includes("!");
      const touchesLetter = hasBang ? before && after : before || after;
      for (let k = i; k < j; k++) mapped += touchesLetter ? LEET[chars[k]] : " ";
      i = j;
    } else {
      mapped += isLetter(chars[i]) ? chars[i] : " ";
      i++;
    }
  }
  return mapped.split(" ").filter((t) => t.length > 0);
}

// Every run of 3+ consecutive single-letter tokens, joined ("f u c k" -> "fuck").
function joinedRuns(tokens: string[]): string[] {
  const out: string[] = [];
  let run: string[] = [];
  const flush = () => {
    if (run.length >= 3) out.push(run.join(""));
    run = [];
  };
  for (const t of tokens) {
    if (t.length === 1) run.push(t);
    else flush();
  }
  flush();
  return out;
}

// Tokens in order, with each run of 3+ single letters joined IN PLACE
// ("k i l l yourself" -> ["kill", "yourself"]), for phrase matching.
function phraseTokens(tokens: string[]): string[] {
  const out: string[] = [];
  let run: string[] = [];
  const flush = () => {
    if (run.length >= 3) out.push(run.join(""));
    else out.push(...run);
    run = [];
  };
  for (const t of tokens) {
    if (t.length === 1) run.push(t);
    else { flush(); out.push(t); }
  }
  flush();
  return out;
}

/** splitTokens plus the joined single-letter runs appended (diagnostic/tests). */
export function normalizeForFilter(text: string): string[] {
  const tokens = splitTokens(text);
  return [...tokens, ...joinedRuns(tokens)];
}

// "fuuuuck" -> "fuck". Only used when the token had a run of 3+ of one
// letter, so "ass" (collapses to "as") can't match the real word "as".
function collapseRepeats(s: string): string {
  return s.replace(/(.)\1+/g, "$1");
}
function hasTripleRun(s: string): boolean {
  return /(.)\1\1/.test(s);
}

const TERM_SET = new Set(BLOCKED_TERMS);
const COLLAPSED_TERM_SET = new Set(BLOCKED_TERMS.map(collapseRepeats));
const COLLAPSED_STEMS = BLOCKED_STEMS.map(collapseRepeats);

function tokenIsBlocked(token: string): boolean {
  if (TERM_SET.has(token)) return true;
  if (BLOCKED_STEMS.some((stem) => token.includes(stem))) return true;
  if (hasTripleRun(token)) {
    const collapsed = collapseRepeats(token);
    if (COLLAPSED_TERM_SET.has(collapsed)) return true;
    if (COLLAPSED_STEMS.some((stem) => collapsed.includes(stem))) return true;
  }
  return false;
}

/** True if `text` contains a blocked word, stem or phrase. Pure; no I/O. */
export function containsBlockedTerm(text: string): boolean {
  const tokens = splitTokens(text);
  if (tokens.some(tokenIsBlocked) || joinedRuns(tokens).some(tokenIsBlocked)) return true;
  const sentence = ` ${phraseTokens(tokens).join(" ")} `;
  return BLOCKED_PHRASES.some((p) => sentence.includes(` ${p} `));
}
