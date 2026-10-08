#!/usr/bin/env python3
"""seats.py <glb-dir> <out-dir> [car-key ...] — the seat-color add-on layer.

For every manifest car with a `seatmat` (the model's seat material, found by
eye off a matid=1 pass — most models lump seats into one whole-interior
material and don't get this layer), 36 frames of render_car.py's isolate
pass: the seat material restyled (the `interior` preset — dark, matte) and
shown lit normally, everything else a holdout, so the app can overlay a
black-seat option over the frame's own (lighter) default seats without
re-rendering the whole car — same technique as tints.py's glass mask, but
the isolated part keeps its real shading instead of being a flat stencil.
Raw PNGs go to <out-dir>/_seats/<car>/black/<NN>.png; publish.py crops them
like the frames and writes <car>/seats/black/<NN>.webp + seats: true."""
import glob, json, os, subprocess, sys
here = os.path.dirname(os.path.abspath(__file__))
glbdir, outdir = sys.argv[1], sys.argv[2]
manifest = json.load(open(os.path.join(here, "manifest.json")))
for key in sys.argv[3:] or list(manifest):
    car = manifest[key]
    if not car.get("seatmat"):
        continue
    raw = os.path.join(outdir, "_seats", key)
    if len(glob.glob(os.path.join(raw, "black", "*.png"))) == 36:
        print("SKIP (already done)", key, flush=True); continue
    args = ["blender", "-b", "--python-exit-code", "1", "-P", os.path.join(here, "render_car.py"), "--",
            f"in={os.path.join(glbdir, key + '.glb')}", f"out={raw}",
            f"styles={car['seatmat']}:interior", f"isolate={car['seatmat']}",
            "colors=black:1,1,1", "frames=36", "engine=BLENDER_EEVEE", "samples=32", "res=1200x675"]
    for opt in ("flip", "invert"):
        if car.get(opt): args.append(f"{opt}=1")
    for opt in ("roll", "hide", "keep", "paintmat"):
        if car.get(opt) not in (None, ""): args.append(f"{opt}={car[opt]}")
    result = subprocess.run(args, capture_output=True, text=True)
    made = len(glob.glob(os.path.join(raw, "black", "*.png")))
    print("DONE" if made == 36 else f"FAILED ({made} frames)", key,
          "" if made == 36 else (result.stdout + result.stderr).strip().splitlines()[-1:], flush=True)
