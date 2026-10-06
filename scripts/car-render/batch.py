#!/usr/bin/env python3
"""batch.py <glb-dir> <out-dir> [car-key ...] — renders every manifest car x palette color x 36 frames,
raw PNGs to <out-dir>/_png/<car>/<color>/<NN>.png; publish.py crops + converts them."""
import json, os, subprocess, sys, glob
from PIL import Image
here = os.path.dirname(os.path.abspath(__file__))
glbdir, outdir = sys.argv[1], sys.argv[2]
only = sys.argv[3:]
manifest = json.load(open(os.path.join(here, "manifest.json")))
palette = {k: v for k, v in json.load(open(os.path.join(here, "palette.json"))).items() if not k.startswith("_")}
lin = lambda c: c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
colors = ";".join(f"{k}:{','.join(f'{lin(c):.4f}' for c in rgb)}" for k, rgb in palette.items())
for key, car in manifest.items():
    if only and key not in only: continue
    glb = os.path.join(glbdir, f"{key}.glb")
    done = glob.glob(os.path.join(outdir, "_png", key, "*", "*.png"))
    if len(done) == 36 * len(palette):
        print("SKIP (already rendered)", key, flush=True); continue
    raw = os.path.join(outdir, "_png", key)
    args = ["blender", "-b", "-P", os.path.join(here, "render_car.py"), "--", f"in={glb}", f"out={raw}",
            f"paintmat={car['paintmat']}", "engine=BLENDER_EEVEE", "samples=48", "res=1200x675",
            f"colors={colors}", "frames=36"] + (["flip=1"] if car.get("flip") else []) \
           + ([f"styles={car['styles']}"] if car.get("styles") else []) \
           + (["invert=1"] if car.get("invert") else [])
    print("RENDER", key, flush=True)
    subprocess.run(args, check=True, stdout=subprocess.DEVNULL)
    print("DONE", key, flush=True)
