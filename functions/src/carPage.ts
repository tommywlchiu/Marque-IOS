// Public web page for one shared car (GET /car/<carId>), the link target for the
// app's share sheet. Pure rendering lives here so it can be checked without
// Firebase; the HTTP handler (`carPage` in index.ts) only reads publicCars/{id}.
//
// Privacy boundary: this page deliberately shows LESS than Explore. Only the
// fields below are ever read from the doc: name, trim, color, mileage, cover
// photo, owner @username and a like count. Never notes, mods, service-record
// contents, the engine-sound URL, value range or the owner's uid/avatar. The
// doc itself is already the sharing-toggle-filtered projection (PublicCar), so
// a toggled-off field (e.g. mileage) is simply empty here too.

const APP_STORE_URL = "https://apps.apple.com/app/id6812103249";
const SITE_ORIGIN = "https://marque-173c3.web.app";

// carIds are client-chosen UUID strings; anything else is a 404 without a read.
const CAR_ID_RE = /^[A-Za-z0-9-]{8,64}$/;

export function parseCarId(path: string): string | null {
  const m = /^\/car\/([^/?#]+)\/?$/.exec(path);
  if (!m) return null;
  return CAR_ID_RE.test(m[1]) ? m[1] : null;
}

export function escapeHtml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

// Cover photos are Firebase Storage download URLs (firestore.rules pins them to
// the car's own Storage folder). Re-check the host here so a malformed doc can
// never put an arbitrary URL into <img src> / og:image.
export function safePhotoUrl(raw: unknown): string | null {
  if (typeof raw !== "string" || raw.length > 2048) return null;
  try {
    const u = new URL(raw);
    const ok = u.protocol === "https:" &&
      (u.hostname === "firebasestorage.googleapis.com" || u.hostname === "storage.googleapis.com");
    return ok ? u.toString() : null;
  } catch {
    return null;
  }
}

export interface CarPageData {
  carId: string;
  year: string;
  make: string;
  model: string;
  trim: string;
  color: string;
  mileage: string;
  ownerUsername: string;
  photoUrl: string | null;
  likeCount: number;
}

const str = (v: unknown, max = 80): string =>
  typeof v === "string" ? v.trim().slice(0, max) : "";

export function carPageData(carId: string, doc: Record<string, unknown>): CarPageData {
  const photos = Array.isArray(doc.photoURLs) ? doc.photoURLs : [];
  const likes = typeof doc.likeCount === "number" && Number.isFinite(doc.likeCount) ? doc.likeCount : 0;
  return {
    carId,
    year: str(doc.year, 8),
    make: str(doc.make),
    model: str(doc.model),
    trim: str(doc.trim),
    color: str(doc.color, 40),
    mileage: str(doc.mileage, 24),
    ownerUsername: str(doc.ownerUsername, 40),
    photoUrl: safePhotoUrl(doc.photoStorageURL) ?? safePhotoUrl(photos[0]),
    likeCount: Math.max(0, Math.floor(likes)),
  };
}

export function renderCarPage(d: CarPageData): string {
  const name = [d.year, d.make, d.model].filter(Boolean).join(" ") || "A car on Marque";
  const owner = d.ownerUsername ? `@${d.ownerUsername}` : "a Marque owner";
  const details = [d.trim, d.color, d.mileage ? `${d.mileage} mi` : ""].filter(Boolean).join(" · ");
  const title = `${name} on Marque`;
  const desc = `${name}, shared by ${owner}. Track your own cars' service history, documents and expiry dates with Marque.`;
  const url = `${SITE_ORIGIN}/car/${d.carId}`;
  const e = escapeHtml;
  const image = d.photoUrl
    ? `<img class="photo" src="${e(d.photoUrl)}" alt="${e(name)}" />`
    : `<div class="photo placeholder" aria-hidden="true"></div>`;
  const likes = d.likeCount > 0
    ? `<p class="meta">${d.likeCount} ${d.likeCount === 1 ? "like" : "likes"}</p>`
    : "";

  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8" />
<meta name="viewport" content="width=device-width, initial-scale=1.0" />
<title>${e(title)}</title>
<meta name="description" content="${e(desc)}" />
<meta name="robots" content="noindex" />
<link rel="canonical" href="${e(url)}" />
<meta property="og:type" content="website" />
<meta property="og:site_name" content="Marque" />
<meta property="og:title" content="${e(title)}" />
<meta property="og:description" content="${e(desc)}" />
<meta property="og:url" content="${e(url)}" />
${d.photoUrl ? `<meta property="og:image" content="${e(d.photoUrl)}" />\n<meta name="twitter:card" content="summary_large_image" />` : `<meta name="twitter:card" content="summary" />`}
<meta name="apple-itunes-app" content="app-id=6812103249" />
<style>
*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}
body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;background:#111;color:#f5f5f7;min-height:100vh;display:flex;flex-direction:column;align-items:center;padding:24px 16px}
.card{width:100%;max-width:520px;background:#1c1c1e;border-radius:20px;overflow:hidden}
.photo{display:block;width:100%;aspect-ratio:4/3;object-fit:cover;background:#2c2c2e}
.body{padding:20px}
h1{font-size:26px;font-weight:700;line-height:1.2}
.details{margin-top:6px;color:#a1a1a6;font-size:16px}
.meta{margin-top:10px;color:#a1a1a6;font-size:14px}
.cta{display:block;margin:20px 0 0;background:#fff;color:#111;text-align:center;padding:14px 20px;border-radius:14px;font-size:16px;font-weight:600;text-decoration:none}
.sub{margin-top:12px;color:#a1a1a6;font-size:13px;text-align:center}
footer{margin-top:28px;color:#6e6e73;font-size:13px}
footer a{color:#6e6e73;text-decoration:none;margin:0 8px}
</style>
</head>
<body>
<div class="card">
${image}
<div class="body">
<h1>${e(name)}</h1>
${details ? `<p class="details">${e(details)}</p>` : ""}
<p class="meta">Shared by ${e(owner)}</p>
${likes}
<a class="cta" href="${APP_STORE_URL}">Get Marque on the App Store</a>
<p class="sub">Your cars, organized: service history, documents and expiry reminders.</p>
</div>
</div>
<footer><a href="/">Marque</a><a href="/privacy">Privacy</a><a href="/terms">Terms</a></footer>
</body>
</html>
`;
}

export function renderNotFound(): string {
  return `<!DOCTYPE html>
<html lang="en"><head><meta charset="UTF-8" /><meta name="viewport" content="width=device-width, initial-scale=1.0" />
<title>Car not found · Marque</title><meta name="robots" content="noindex" />
<style>body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;background:#111;color:#f5f5f7;min-height:100vh;display:flex;flex-direction:column;align-items:center;justify-content:center;text-align:center;padding:24px}p{color:#a1a1a6;margin-top:10px}a{display:inline-block;margin-top:24px;background:#fff;color:#111;padding:14px 24px;border-radius:14px;font-weight:600;text-decoration:none}</style>
</head><body><h1>This car isn't shared</h1><p>The owner may have made it private or removed it.</p><a href="${APP_STORE_URL}">Get Marque on the App Store</a></body></html>
`;
}
