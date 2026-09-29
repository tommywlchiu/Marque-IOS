// ============================================================================
// Public value range (owner decision: AI estimate only, enforced server-side).
// ============================================================================
//
// publicCars/{carId}.valueRange is SERVER-ONLY (firestore.rules excludes it
// from the owner-writable fields). It's derived from the car's last AI
// valuation (users/{uid}/usage/valuation_{carId}, written only by
// estimateCarValue), never from a value the owner typed.
//
// publicValueLabel is a port of CarValueRange.publicLabel
// (Marque/Models/CarValue.swift); the two must return identical strings (there's
// a parity check). valuationStillApplies mirrors CarValuation.applies(to:) in
// Swift, which the app uses to preview whether the range will show.

/** Bucket width scales with price: $1k < $20k, $5k < $100k, $10k < $250k, else $25k. */
export function bucketSize(value: number): number {
  if (value < 20_000) return 1_000;
  if (value < 100_000) return 5_000;
  if (value < 250_000) return 10_000;
  return 25_000;
}

/** "$30k", "$975k", "$1M", "$1.025M". */
export function formatAmount(amount: number): string {
  if (amount >= 1_000_000) {
    let s = (amount / 1_000_000).toFixed(3);
    while (s.endsWith("0")) s = s.slice(0, -1);
    if (s.endsWith(".")) s = s.slice(0, -1);
    return `$${s}M`;
  }
  return `$${Math.round(amount / 1_000)}k`;
}

/** The rounded public range for `value` ("$30k–$35k", "Under $1k"), or null. */
export function publicValueLabel(value: unknown): string | null {
  if (typeof value !== "number" || !Number.isFinite(value) || value <= 0) return null;
  const step = bucketSize(value);
  const low = Math.floor(value / step) * step;
  if (low === 0) return "Under $1k";
  return `${formatAmount(low)}–${formatAmount(low + step)}`;
}

// ---------------------------------------------------------------------------
// When does a valuation still describe the car?
// ---------------------------------------------------------------------------

/** A valuation this old no longer shows publicly (prices move). */
export const VALUATION_MAX_AGE_MS = 365 * 24 * 60 * 60 * 1000;
/** Miles driven since the valuation after which it no longer shows publicly. */
export const VALUATION_MAX_MILEAGE_DRIFT = 20_000;

export interface CarSnapshot {
  year: string;
  make: string;
  model: string;
  trim: string;
  mileage: string;
}

/** Case/whitespace-insensitive form used to compare identity fields. */
export function normalizeIdentity(v: unknown): string {
  return typeof v === "string" ? v.trim().replace(/\s+/g, " ").toLowerCase() : "";
}

/** "42,850" -> 42850; anything unparseable -> null. */
export function parseMileage(v: unknown): number | null {
  if (typeof v === "number" && Number.isFinite(v)) return v;
  if (typeof v !== "string") return null;
  const digits = v.replace(/[,\s]/g, "");
  return /^\d{1,9}$/.test(digits) ? Number(digits) : null;
}

/** The identity + mileage fields of a car doc, as stored in a valuation. */
export function snapshotOf(car: Record<string, unknown>): CarSnapshot {
  const s = (v: unknown) => (typeof v === "string" ? v.trim().slice(0, 64) : "");
  return { year: s(car.year), make: s(car.make), model: s(car.model), trim: s(car.trim), mileage: s(car.mileage) };
}

/**
 * True if a valuation taken of `snapshot` at `createdAtMs` still describes
 * `car` now: same year/make/model/trim (normalized), mileage not more than
 * VALUATION_MAX_MILEAGE_DRIFT above the snapshot (a lower reading, e.g. a
 * typo fix, is fine), and not older than VALUATION_MAX_AGE_MS.
 */
export function valuationStillApplies(
  snapshot: Partial<CarSnapshot> | undefined,
  createdAtMs: number | null,
  car: Record<string, unknown>,
  nowMs: number = Date.now()
): boolean {
  if (!snapshot) return false;
  for (const k of ["year", "make", "model", "trim"] as const) {
    if (normalizeIdentity(snapshot[k]) !== normalizeIdentity(car[k])) return false;
  }
  const then = parseMileage(snapshot.mileage);
  const now = parseMileage(car.mileage);
  if (then !== null && now !== null && now - then > VALUATION_MAX_MILEAGE_DRIFT) return false;
  if (createdAtMs === null || nowMs - createdAtMs > VALUATION_MAX_AGE_MS) return false;
  return true;
}
