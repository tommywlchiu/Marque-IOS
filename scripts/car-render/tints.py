#!/usr/bin/env python3
"""tints.py <glb-dir> <out-dir> [car-key ...] — window masks for the tint add-on.

For every car, 36 frames of render_car.py's mask=glass pass (the windows flat
white, the rest of the car a holdout) with the car's own manifest options,
so the masks line up with batch.py's frames. Raw PNGs go to
<out-dir>/_tint/<car>/tint/<NN>.png; publish.py crops them like the frames
and writes <car>/tint/<NN>.webp. Glass is `tintmat` when the manifest has it
(checked by eye with maskcheck), else found by name/transparency."""
import glob, json, os, subprocess, sys
here = os.path.dirname(os.path.abspath(__file__))
glbdir, outdir = sys.argv[1], sys.argv[2]
manifest = json.load(open(os.path.join(here, "manifest.json")))
for key in sys.argv[3:] or list(manifest):
    car = manifest[key]
    raw = os.path.join(outdir, "_tint", key)
    if len(glob.glob(os.path.join(raw, "tint", "*.png"))) == 36:
        print("SKIP (already done)", key, flush=True); continue
    args = ["blender", "-b", "--python-exit-code", "1", "-P", os.path.join(here, "render_car.py"), "--",
            f"in={os.path.join(glbdir, key + '.glb')}", f"out={raw}", "mask=glass", "colors=tint:1,1,1",
            "frames=36", "engine=BLENDER_EEVEE", "samples=8", "res=1200x675"]
    for opt in ("flip", "invert"):
        if car.get(opt): args.append(f"{opt}=1")
    for opt in ("roll", "hide", "keep", "styles", "tintmat"):
        if car.get(opt) not in (None, ""): args.append(f"{opt}={car[opt]}")
    result = subprocess.run(args, capture_output=True, text=True)
    made = len(glob.glob(os.path.join(raw, "tint", "*.png")))
    print("DONE" if made == 36 else f"FAILED ({made} frames)", key, flush=True)
