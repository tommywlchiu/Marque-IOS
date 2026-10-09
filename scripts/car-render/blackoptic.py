#!/usr/bin/env python3
"""blackoptic.py <glb-dir> <out-dir> [car-key ...] — the Black Optic trim
add-on layer.

For every manifest car with `blackOpticMats` (the model's bright/chrome
trim materials that Audi's real Black Optic package blacks out — grille
surround + rings, mirror caps, window trim — found by isolating each
candidate material off a matid=1 pass and checking by eye which one is
actually the rings, not just a plausible-sounding name), 36 frames of
render_car.py's isolate pass: those materials restyled black (the `trim`
preset) and shown lit normally, everything else a holdout, so the app can
overlay a blacked-out-trim option over the frame's own (chrome) default
without re-rendering the whole car — same technique as seats.py.
Color-independent (black optic trim doesn't depend on body paint), so one
set of 36 frames covers every body color, same as seats.py and tints.py.
Raw PNGs go to <out-dir>/_blackoptic/<car>/blackoptic/<NN>.png;
publish.py crops them like tint and writes <car>/blackOptic/<NN>.webp +
blackOptic: true."""
import glob, json, os, subprocess, sys
here = os.path.dirname(os.path.abspath(__file__))
glbdir, outdir = sys.argv[1], sys.argv[2]
manifest = json.load(open(os.path.join(here, "manifest.json")))
for key in sys.argv[3:] or list(manifest):
    car = manifest[key]
    if not car.get("blackOpticMats"):
        continue
    raw = os.path.join(outdir, "_blackoptic", key)
    if len(glob.glob(os.path.join(raw, "blackoptic", "*.png"))) == 36:
        print("SKIP (already done)", key, flush=True); continue
    args = ["blender", "-b", "--python-exit-code", "1", "-P", os.path.join(here, "render_car.py"), "--",
            f"in={os.path.join(glbdir, key + '.glb')}", f"out={raw}",
            f"styles={car['blackOpticMats']}:trim", f"isolate={car['blackOpticMats']}",
            "colors=blackoptic:1,1,1", "frames=36", "engine=BLENDER_EEVEE", "samples=32", "res=1200x675"]
    for opt in ("flip", "invert"):
        if car.get(opt): args.append(f"{opt}=1")
    for opt in ("roll", "hide", "keep", "paintmat"):
        if car.get(opt) not in (None, ""): args.append(f"{opt}={car[opt]}")
    result = subprocess.run(args, capture_output=True, text=True)
    made = len(glob.glob(os.path.join(raw, "blackoptic", "*.png")))
    print("DONE" if made == 36 else f"FAILED ({made} frames)", key,
          "" if made == 36 else (result.stdout + result.stderr).strip().splitlines()[-1:], flush=True)
