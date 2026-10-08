#!/usr/bin/env python3
"""check.py [car-key ...] — verifies what publish.py wrote to public/carRenders/v1.

Per car: every color × frame exists and shares one size; plates.json has a
quad per frame that lies on the car (opaque frame pixels under it); the tint
masks sit inside the car and cover a plausible share of it; each wheel layer
sits low on the car, over the stock wheels, and shows two separate wheels in
the side views; stance data (stock layer + meter) is present; the roof/body
extras are all there and sit on the upper part of the car. Prints one
line per problem and a summary; exits 1 if anything failed."""
import json, os, sys
from PIL import Image

here = os.path.dirname(os.path.abspath(__file__))
root = os.path.join(os.path.dirname(os.path.dirname(here)), "public", "carRenders", "v1")
catalog = json.load(open(os.path.join(root, "catalog.json")))
FRAMES, COLORS = catalog["frames"], catalog["colors"]
styles = [w["id"] for w in catalog.get("wheelStyles", [])]
entries = catalog["cars"] + catalog.get("generics", [])
only = sys.argv[1:]
problems, checked = [], 0


def alpha(path, size=None):
    a = Image.open(path).convert("RGBA").getchannel("A")
    return a.resize(size) if size and a.size != size else a


def runs(column_profile, threshold):
    """Separate horizontal runs where a layer is present (e.g. two wheels)."""
    count, inside = 0, False
    for v in column_profile:
        if v > threshold and not inside: count += 1; inside = True
        elif v <= threshold: inside = False
    return count


def wheel_spans(a):
    """A wheel layer's box and its tyres: the horizontal runs across the
    lower 40% of the box, tallest first, as (x0, x1, column height). The
    stock layer's two tallest are its near-side wheels; the rest are the
    far-side wheels showing under the body — a few pixels of tyre under a
    car's sill, much more under a truck (a deep-dish style's far wheel can
    stand taller there than the near rear one) — a mud-flap lip, or a liner
    piece split off its wheel by a pixel. A fender liner above a stock wheel
    stays out of the band."""
    solid = a.point(lambda v: 255 if v > 128 else 0)
    box = solid.getbbox()
    if not box: return None, []
    top = int(box[3] - (box[3] - box[1]) * 0.4)
    band = list(solid.crop((0, top, solid.width, box[3])).resize((solid.width, 1), Image.BOX).getdata())
    height = list(solid.resize((solid.width, 1), Image.BOX).getdata())  # column height, in 255ths of the frame
    spans, start = [], None
    for x, v in enumerate(band + [0]):
        if v and start is None: start = x
        elif not v and start is not None: spans.append((start, x, max(height[start:x]))); start = None
    return box, sorted(spans, key=lambda s: -s[2])


for e in entries:
    key = e["key"]
    if only and key not in only: continue
    checked += 1
    d = os.path.join(root, key)
    def bad(msg): problems.append(f"{key}: {msg}")

    # Frames
    sizes = set()
    for c in COLORS:
        for f in range(FRAMES):
            p = os.path.join(d, c, f"{f:02d}.webp")
            if not os.path.exists(p): bad(f"missing {c}/{f:02d}"); continue
            sizes.add(Image.open(p).size)
    if len(sizes) != 1: bad(f"frame sizes differ: {sizes}"); continue
    W, H = sizes.pop()
    car = [alpha(os.path.join(d, "silver", f"{f:02d}.webp")) for f in range(FRAMES)]

    # Plates
    if e.get("plates"):
        pl = json.load(open(os.path.join(d, "plates.json")))
        if len(pl["frames"]) != FRAMES: bad("plates: wrong frame count")
        shown = 0
        for f, fr in enumerate(pl["frames"]):
            for side, p in fr.items():
                q = p["quad"]
                if not all(-0.02 <= x <= 1.02 and -0.02 <= y <= 1.02 for x, y in q):
                    bad(f"plates: {side} quad off-frame at {f}"); continue
                cx = sum(x for x, _ in q) / 4 * W; cy = sum(y for _, y in q) / 4 * H
                if car[f].getpixel((min(int(cx), W - 1), min(int(cy), H - 1))) < 200:
                    bad(f"plates: {side} plate not on the car at frame {f}")
                shown += 1
        if shown < 8: bad(f"plates: visible in only {shown} frames")
    else:
        bad("no plates")

    # Tint masks
    if e.get("tint"):
        for f in (0, 9, 18, 27):
            m = alpha(os.path.join(d, "tint", f"{f:02d}.webp"), (W, H))
            mh, ch = m.histogram(), car[f].histogram()
            glass = sum(mh[128:]); body = sum(ch[128:])
            outside = sum(1 for mv, cv in zip(m.getdata(), car[f].getdata()) if mv > 128 and cv < 60)
            share = glass / max(body, 1)
            if not 0.015 <= share <= 0.35: bad(f"tint: glass is {share:.0%} of the car at frame {f}")
            # (See-through glass has a low frame alpha, so some "outside"
            # pixels are real glass — only a big spill is a fault.)
            if outside > glass * 0.3: bad(f"tint: mask spills off the car at frame {f}")
    else:
        bad("no tint masks")

    # Wheels
    # Frames 15 and 33 are the side views (yaw 185° / 5°).
    rendered = e.get("wheels") or []
    stock_box = {}
    if not rendered and key in ("generic-coupe",): pass  # wheels deliberately off (manifest noWheels)
    for s in (["stock"] + styles) if rendered or key not in ("generic-coupe",) else []:
        if s not in rendered: bad(f"wheels: {s} missing"); continue
        for f in (0, 6, 15, 18, 33):
            w = alpha(os.path.join(d, "wheels", s, f"{f:02d}.webp"), (W, H))
            box, tyres = wheel_spans(w)
            if not box:
                if f != 6: bad(f"wheels: {s} empty at frame {f}")  # head-on, a narrow wheel can hide entirely
                continue
            cbox = car[f].point(lambda a: 255 if a > 128 else 0).getbbox()
            ch = cbox[3] - cbox[1]
            if s == "stock":
                stock_box[f] = box, tyres[:2]
                if box[1] < cbox[1] + ch * 0.25: bad(f"wheels: stock layer reaches too high at frame {f}")
            elif f in stock_box:
                sb, near = stock_box[f]
                # The new wheels stand where the car's own do: each of the
                # stock near wheels has a new tyre over it, side to side.
                # (Head-on, frame 6, how much tire peeks past the bumper
                # depends on the wheel's offset — only its bottom must match.
                # The top only bounds a wheel standing taller than the car's
                # own: a stock layer can carry a fender liner above its tyre,
                # and a too-small wheel already fails on its sides.)
                # A deep-dish tyre can merge with the far wheel touching it
                # under a truck: it may run on past one side, but only into
                # where the stock layer shows wheel too.
                tol = W * 0.06
                def over(t, x0, x1):
                    return (t[0] <= x0 + tol and t[1] >= x1 - tol and t[0] >= sb[0] - tol and t[1] <= sb[2] + tol
                            and (abs(t[0] - x0) <= tol or abs(t[1] - x1) <= tol))
                missed = [] if f == 6 else [(x0, x1) for x0, x1, _ in near if not any(over(t, x0, x1) for t in tyres)]
                if (f != 6 and sb[1] - box[1] > ch * 0.1) or abs(box[3] - sb[3]) > ch * 0.06 or missed:
                    bad(f"wheels: {s} off the car's wheels at frame {f} (box {box} vs stock {sb}; no new tyre over {missed})")
            if f in (15, 33):  # side views: two wheels, apart
                prof = list(w.resize((W, 1), Image.BOX).getdata())
                if runs(prof, 6) < 2: bad(f"wheels: {s} shows {runs(prof, 6)} wheel(s) side-on at frame {f}")
    if "stock" in rendered and not e.get("meter"): bad("stance: no meter")

    # Roof/body extras: crossbars and a cargo box on every car, plus a rear
    # wing (trunk) or a light bar (everything else); each layer present in
    # every frame and standing on the upper half of the car.
    extras = e.get("extras") or {}
    for need in ("rack", "box"):
        if need not in extras: bad(f"extras: {need} missing")
    if ("spoiler" in extras) == ("lightbar" in extras): bad(f"extras: expected one of spoiler/lightbar, got {sorted(extras)}")
    for x, (rx, ry, rw, rh) in extras.items():
        if not (-0.15 <= rx and rx + rw <= 1.15 and -0.8 <= ry and ry + rh <= 1.0 and rw > 0.02 and rh > 0.01):
            bad(f"extras: {x} rect {[rx, ry, rw, rh]} off the car"); continue
        for f in (0, 15, 33):
            pth = os.path.join(d, "extras", x, f"{f:02d}.webp")
            if not os.path.exists(pth): bad(f"extras: {x} missing frame {f}"); continue
            a = alpha(pth)
            box = a.point(lambda v: 255 if v > 128 else 0).getbbox()
            if not box: bad(f"extras: {x} empty at frame {f}"); continue
            cbox = car[f].point(lambda v: 255 if v > 128 else 0).getbbox()
            # The layer's lowest point, in the car frame's pixels.
            bottom = (ry + rh * box[3] / a.size[1]) * H
            if bottom > cbox[1] + (cbox[3] - cbox[1]) * 0.6:
                bad(f"extras: {x} reaches too low at frame {f}")

# Every manifest car must be in the catalog (a partial publish once wrote a
# catalog with one car in it).
if not only:
    manifest = json.load(open(os.path.join(here, "manifest.json")))
    missing = sorted(set(manifest) - {e["key"] for e in entries})
    for k in missing: problems.append(f"{k}: in the manifest but not in catalog.json")

total = len([e for e in entries if not only or e["key"] in only])
for p in problems: print("FAIL", p)
print(f"checked {checked}/{total} renders, {len(problems)} problem(s)")
sys.exit(1 if problems else 0)
