#!/usr/bin/env python3
"""publish.py <render-dir> — turns batch.py's raw PNGs into what Firebase Hosting serves.

For each manifest car rendered under <render-dir>/_png/<car>/<color>/<NN>.png:
  * crops every frame of every color to ONE shared box (the union of the car's
    opaque pixels across all of them), so the car never jumps while spinning;
  * writes public/carRenders/v1/<car>/<color>/<NN>.webp (alpha WebP).
Then writes public/carRenders/v1/catalog.json, which the app reads to match a
car (make/model/year; else the generic for its body style — manifest entries
with `styles` instead of `covers`) and to show credits. Credits (author, license, link) are
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

cars, generics = [], []
for key, car in manifest.items():
    pngs = sorted(glob.glob(os.path.join(src, key, "*", "*.png")))
    if len(pngs) != FRAMES * len(palette):
        print(f"SKIP {key}: {len(pngs)} frames, expected {FRAMES * len(palette)}")
        continue
    box = None
    for p in pngs:
        b = Image.open(p).getchannel("A").point(lambda a: 255 if a > 8 else 0).getbbox()
        if b: box = b if box is None else (min(box[0], b[0]), min(box[1], b[1]), max(box[2], b[2]), max(box[3], b[3]))
    w, h = Image.open(pngs[0]).size
    box = (max(box[0] - PAD, 0), max(box[1] - PAD, 0), min(box[2] + PAD, w), min(box[3] + PAD, h))
    for p in pngs:
        color, name = p.split(os.sep)[-2:]
        out = os.path.join(dst, key, color, name.replace(".png", ".webp"))
        os.makedirs(os.path.dirname(out), exist_ok=True)
        Image.open(p).crop(box).save(out, "WEBP", quality=82, method=4)
    if "styles" in car:  # an unbadged stand-in for every car of these body styles
        generics.append({"key": key, "styles": car["styles"], "credit": credit(car["sketchfab"])})
    else:
        c = car["covers"]
        cars.append({"key": key, "make": c["make"], "models": c.get("aliases", [c["model"]]),
                     "years": c["years"], "credit": credit(car["sketchfab"])})
    print(f"PUBLISHED {key} crop={box}")

json.dump({"version": 1, "frames": FRAMES, "colors": palette, "cars": cars, "generics": generics},
          open(os.path.join(dst, "catalog.json"), "w"), indent=2)
print("catalog:", len(cars), "cars,", len(generics), "generics")
