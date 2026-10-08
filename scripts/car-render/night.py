#!/usr/bin/env python3
"""night.py <glb-dir> <out-dir> [car-key ...] — renders every manifest car x
palette color x 36 frames under render_car.py's lighting=night (the studio
dimmed and cooled, headlights/taillights/signals actually glowing), raw PNGs
to <out-dir>/_png_night/<car>/<color>/<NN>.png; publish.py crops + converts
them to <car>/night/<color>/NN.webp. Same shape as batch.py — the day pass —
kept a separate script because it's a genuinely separate pass (different
lighting opt, different output tree), not a flag on the same one."""
import json, os, subprocess, sys, glob
here = os.path.dirname(os.path.abspath(__file__))
glbdir, outdir = sys.argv[1], sys.argv[2]
only = sys.argv[3:]
manifest = json.load(open(os.path.join(here, "manifest.json")))
palette = {k: v for k, v in json.load(open(os.path.join(here, "palette.json"))).items() if not k.startswith("_")}
lin = lambda c: c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
colors = ";".join(f"{k}:{','.join(f'{lin(c):.4f}' for c in rgb)}" for k, rgb in palette.items())
for key in only or list(manifest):
    car = manifest[key]
    glb = os.path.join(glbdir, f"{key}.glb")
    done = glob.glob(os.path.join(outdir, "_png_night", key, "*", "*.png"))
    if len(done) == 36 * len(palette):
        print("SKIP (already rendered)", key, flush=True); continue
    raw = os.path.join(outdir, "_png_night", key)
    args = ["blender", "-b", "--python-exit-code", "1", "-P", os.path.join(here, "render_car.py"), "--", f"in={glb}", f"out={raw}",
            f"paintmat={car['paintmat']}", "engine=BLENDER_EEVEE", "samples=48", "res=1200x675",
            f"colors={colors}", "frames=36", "lighting=night"] + (["flip=1"] if car.get("flip") else []) \
           + ([f"styles={car['styles']}"] if car.get("styles") else []) \
           + (["invert=1"] if car.get("invert") else []) \
           + ([f"hide={car['hide']}"] if car.get("hide") else []) \
           + ([f"roll={car['roll']}"] if car.get("roll") else []) \
           + ([f"keep={car['keep']}"] if car.get("keep") else [])
    print("RENDER", key, flush=True)
    result = subprocess.run(args, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
    made = len(glob.glob(os.path.join(raw, "*", "*.png")))
    if result.returncode != 0 or made != 36 * len(palette):
        print("FAILED", key, f"{made} frames", result.stderr.strip().splitlines()[-1:], flush=True)
    else:
        print("DONE", key, flush=True)
