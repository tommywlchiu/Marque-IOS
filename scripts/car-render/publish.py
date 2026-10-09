#!/usr/bin/env python3
"""publish.py <render-dir> — turns batch.py's raw PNGs into what Firebase Hosting serves.

For each manifest car rendered under <render-dir>/_png/<car>/<color>/<NN>.png:
  * crops every frame of every color to ONE shared box (the union of the car's
    opaque pixels across all of them), so the car never jumps while spinning;
  * writes public/carRenders/v1/<car>/<color>/<NN>.webp (alpha WebP).
Then writes public/carRenders/v1/catalog.json, which the app reads to match a
car (make/model/year; else the generic for its body style — manifest entries
with `bodyStyles` instead of `covers`) and to show credits. Credits (author, license, link) are
read from Sketchfab's public API, not typed by hand.
"""
import glob, json, os, sys, urllib.request
from PIL import Image

here = os.path.dirname(os.path.abspath(__file__))
repo = os.path.dirname(os.path.dirname(here))
src = os.path.join(sys.argv[1], "_png")
dst = os.path.join(repo, "public", "carRenders", "v1")
manifest = json.load(open(os.path.join(here, "manifest.json")))
palette = [k for k in json.load(open(os.path.join(here, "palette.json"))) if not k.startswith("_")]
FRAMES, PAD = 36, 12

def credit(uid):
    m = json.load(urllib.request.urlopen(f"https://api.sketchfab.com/v3/models/{uid}"))
    lic = m.get("license") or {}
    return {"title": m["name"], "author": m["user"]["displayName"] or m["user"]["username"],
            "authorURL": m["user"]["profileUrl"], "license": lic.get("label", ""),
            "licenseURL": lic.get("url", ""), "url": m["viewerUrl"]}

def alpha_box(pngs, pad):
    """The union of the images' opaque pixels, padded (clamped to the image)."""
    box = None
    for p in pngs:
        b = Image.open(p).getchannel("A").point(lambda a: 255 if a > 8 else 0).getbbox()
        if b: box = b if box is None else (min(box[0], b[0]), min(box[1], b[1]), max(box[2], b[2]), max(box[3], b[3]))
    if box is None: return None
    w, h = Image.open(pngs[0]).size
    return (max(box[0] - pad, 0), max(box[1] - pad, 0), min(box[2] + pad, w), min(box[3] + pad, h))

def car_box(key):
    """The car's crop box: from its published scale.json, else re-derived
    from its raw frames (cars published before the box was recorded)."""
    scale_path = os.path.join(dst, key, "scale.json")
    scale = json.load(open(scale_path)) if os.path.exists(scale_path) else {}
    if "box" not in scale:
        pngs = sorted(glob.glob(os.path.join(src, key, "*", "*.png")))
        if len(pngs) != FRAMES * len(palette): return None
        scale["box"] = list(alpha_box(pngs, PAD))
        json.dump(scale, open(scale_path, "w"))
    return tuple(scale["box"])

def publish_extras(key, box):
    """Roof/body extras layers (extras.py). Each is cropped to its own box —
    a roof box stands well above the car's — and placed by a rect in
    fractions of the car's cropped frame (y < 0 = above it), written to
    <car>/extras.json for the catalog."""
    rects = {}
    bw, bh = box[2] - box[0], box[3] - box[1]
    for extra_dir in sorted(glob.glob(os.path.join(sys.argv[1], "_extras", key, "*"))):
        layer = sorted(glob.glob(os.path.join(extra_dir, "*.png")))
        if len(layer) != FRAMES: continue
        ebox = alpha_box(layer, 4)
        if ebox is None: continue
        extra = os.path.basename(extra_dir)
        for p in layer:
            out = os.path.join(dst, key, "extras", extra, os.path.basename(p).replace(".png", ".webp"))
            os.makedirs(os.path.dirname(out), exist_ok=True)
            Image.open(p).crop(ebox).save(out, "WEBP", quality=95, method=4)
        rects[extra] = [round((ebox[0] - box[0]) / bw, 4), round((ebox[1] - box[1]) / bh, 4),
                        round((ebox[2] - ebox[0]) / bw, 4), round((ebox[3] - ebox[1]) / bh, 4)]
    json.dump(rects, open(os.path.join(dst, key, "extras.json"), "w"))

def publish_frames(key, pngs):
    box = alpha_box(pngs, PAD)
    for p in pngs:
        color, name = p.split(os.sep)[-2:]
        out = os.path.join(dst, key, color, name.replace(".png", ".webp"))
        os.makedirs(os.path.dirname(out), exist_ok=True)
        Image.open(p).crop(box).save(out, "WEBP", quality=95, method=4)
    # Plate positions (plates.py), as fractions of the cropped frame, so the
    # app can draw the owner's plate on whatever size it shows the frame at.
    has_plates = False
    plate_src = os.path.join(sys.argv[1], "_plates", f"{key}.json")
    if os.path.exists(plate_src):
        meta = json.load(open(plate_src))
        bw, bh = box[2] - box[0], box[3] - box[1]
        frames = [{side: {"quad": [[round((x - box[0]) / bw, 4), round((y - box[1]) / bh, 4)] for x, y in p["quad"]],
                          "facing": p["facing"]} for side, p in f.items()} for f in meta["frames"]]
        sizes = {side: {"aspect": round(v["w"] / v["h"], 3)} for side, v in meta["plates"].items()}
        json.dump({"plates": sizes, "frames": frames}, open(os.path.join(dst, key, "plates.json"), "w"))
        has_plates = True
    # One meter of height as a fraction of the cropped frame (the camera is
    # fixed: ~208.5 px/m at 1200x675), so the app can shift the body a given
    # height for the stance add-on.
    json.dump({"meter": round(208.5 / (box[3] - box[1]), 4), "box": list(box)}, open(os.path.join(dst, key, "scale.json"), "w"))
    publish_extras(key, box)
    # Night-lighting pass (night.py), same crop box as day so the two frame
    # sets line up pixel-for-pixel and swapping between them never jumps.
    night_pngs = sorted(glob.glob(os.path.join(sys.argv[1], "_png_night", key, "*", "*.png")))
    has_night = len(night_pngs) == FRAMES * len(palette)
    if has_night:
        for p in night_pngs:
            color, name = p.split(os.sep)[-2:]
            out = os.path.join(dst, key, "night", color, name.replace(".png", ".webp"))
            os.makedirs(os.path.dirname(out), exist_ok=True)
            Image.open(p).crop(box).save(out, "WEBP", quality=95, method=4)
    # Window masks (tints.py), cropped the same way: the app darkens through
    # them for the tint add-on. Lossless — a soft edge would halo.
    tint_src = sorted(glob.glob(os.path.join(sys.argv[1], "_tint", key, "tint", "*.png")))
    if len(tint_src) == FRAMES:
        for p in tint_src:
            out = os.path.join(dst, key, "tint", os.path.basename(p).replace(".png", ".webp"))
            os.makedirs(os.path.dirname(out), exist_ok=True)
            Image.open(p).crop(box).save(out, "WEBP", lossless=True, method=4)
    # Wheel add-on layers (wheels.py), one folder per style, same crop.
    for style_dir in sorted(glob.glob(os.path.join(sys.argv[1], "_wheels", key, "*"))):
        layer = sorted(glob.glob(os.path.join(style_dir, "*.png")))
        if len(layer) != FRAMES: continue
        stock = os.path.basename(style_dir) == "stock"
        for p in layer:
            out = os.path.join(dst, key, "wheels", os.path.basename(style_dir), os.path.basename(p).replace(".png", ".webp"))
            os.makedirs(os.path.dirname(out), exist_ok=True)
            img = Image.open(p)
            if stock:
                # The mask (car's own wheels white) applied to the frame itself.
                frame = Image.open(os.path.join(src, key, "silver", os.path.basename(p))).convert("RGBA")
                a = Image.composite(frame.getchannel("A"), Image.new("L", frame.size, 0), img.convert("RGBA").getchannel("A"))
                frame.putalpha(a); img = frame
            img.crop(box).save(out, "WEBP", quality=95, method=4)
    # Seat-color add-on layers (seats.py), one folder per option, same crop
    # — the isolated seat geometry, lit normally (not a stencil), so the app
    # overlays it straight over the frame.
    for opt_dir in sorted(glob.glob(os.path.join(sys.argv[1], "_seats", key, "*"))):
        layer = sorted(glob.glob(os.path.join(opt_dir, "*.png")))
        if len(layer) != FRAMES: continue
        for p in layer:
            out = os.path.join(dst, key, "seats", os.path.basename(opt_dir), os.path.basename(p).replace(".png", ".webp"))
            os.makedirs(os.path.dirname(out), exist_ok=True)
            Image.open(p).crop(box).save(out, "WEBP", quality=95, method=4)
    return has_plates

# --catalog-only: rewrite catalog.json from what's already published (no
# frame conversion) — for a manifest change that touches no pixels.
catalog_only = "--catalog-only" in sys.argv
# --extras: publish only the extras layers (no frame conversion), then the catalog.
extras_only = "--extras" in sys.argv
# Optional car keys after the render dir: publish just those; every other
# car keeps its published files and stays in the catalog.
only = [a for a in sys.argv[2:] if not a.startswith("--")]
cars, generics = [], []
for key, car in manifest.items():
    if extras_only and (not only or key in only):
        box = car_box(key)
        if box: publish_extras(key, box)
    if catalog_only or extras_only or (only and key not in only):
        # Only the color frames — tint/, wheels/ and extras/ hold more webp files.
        if sum(len(glob.glob(os.path.join(dst, key, c, "*.webp"))) for c in palette) != FRAMES * len(palette):
            continue
        has_plates = os.path.exists(os.path.join(dst, key, "plates.json"))
    else:
        has_plates = None
    convert = not catalog_only and not extras_only and (not only or key in only)
    pngs = sorted(glob.glob(os.path.join(src, key, "*", "*.png"))) if convert else []
    if convert and len(pngs) != FRAMES * len(palette):
        print(f"SKIP {key}: {len(pngs)} frames, expected {FRAMES * len(palette)}")
        continue
    if convert:
        has_plates = publish_frames(key, pngs)
    has_tint = len(glob.glob(os.path.join(dst, key, "tint", "*.webp"))) == FRAMES
    has_night = len(glob.glob(os.path.join(dst, key, "night", "*", "*.webp"))) == FRAMES * len(palette)
    wheels = sorted(os.path.basename(d) for d in glob.glob(os.path.join(dst, key, "wheels", "*"))
                    if len(glob.glob(os.path.join(d, "*.webp"))) == FRAMES)
    seats = sorted(os.path.basename(d) for d in glob.glob(os.path.join(dst, key, "seats", "*"))
                   if len(glob.glob(os.path.join(d, "*.webp"))) == FRAMES)
    scale_path = os.path.join(dst, key, "scale.json")
    meter = json.load(open(scale_path))["meter"] if os.path.exists(scale_path) else None
    extras_path = os.path.join(dst, key, "extras.json")
    extras = {e: r for e, r in (json.load(open(extras_path)) if os.path.exists(extras_path) else {}).items()
              if len(glob.glob(os.path.join(dst, key, "extras", e, "*.webp"))) == FRAMES}
    if "bodyStyles" in car:  # an unbadged stand-in for every car of these body styles
        generics.append({"key": key, "styles": car["bodyStyles"], "credit": credit(car["sketchfab"]),
                         "plates": has_plates, "tint": has_tint, "night": has_night, "wheels": wheels, "meter": meter,
                         "extras": extras, "seats": seats})
    else:
        c = car["covers"]
        cars.append({"key": key, "make": c["make"], "models": c.get("aliases", [c["model"]]),
                     "years": c["years"], "credit": credit(car["sketchfab"]), "plates": has_plates, "tint": has_tint, "night": has_night,
                     "wheels": wheels, "meter": meter, "extras": extras, "seats": seats})
    print(f"PUBLISHED {key}")

addons = json.load(open(os.path.join(here, "addons.json")))
wheel_styles = [{"id": w["id"], "title": w["title"], "credit": credit(addons["wheelPacks"][w["pack"]]["sketchfab"])}
                for w in addons["wheels"]]
json.dump({"version": 1, "frames": FRAMES, "colors": palette, "cars": cars, "generics": generics,
           "wheelStyles": wheel_styles},
          open(os.path.join(dst, "catalog.json"), "w"), indent=2)
print("catalog:", len(cars), "cars,", len(generics), "generics")
