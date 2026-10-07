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
            box = w.point(lambda a: 255 if a > 128 else 0).getbbox()
            if not box:
                if f != 6: bad(f"wheels: {s} empty at frame {f}")  # head-on, a narrow wheel can hide entirely
                continue
            cbox = car[f].point(lambda a: 255 if a > 128 else 0).getbbox()
            ch = cbox[3] - cbox[1]
            if s == "stock":
                stock_box[f] = box
                if box[1] < cbox[1] + ch * 0.25: bad(f"wheels: stock layer reaches too high at frame {f}")
            elif f in stock_box:
                sb = stock_box[f]
                # The new wheels stand where the car's own do.
                # (Head-on, frame 6, how much tire peeks past the bumper
                # depends on the wheel's offset — only its bottom must match.)
                if (f != 6 and abs(box[1] - sb[1]) > ch * 0.1) or abs(box[3] - sb[3]) > ch * 0.06 \
                        or (f != 6 and (abs(box[0] - sb[0]) > W * 0.06 or abs(box[2] - sb[2]) > W * 0.06)):
                    bad(f"wheels: {s} off the car's wheels at frame {f} ({box} vs stock {sb})")
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
