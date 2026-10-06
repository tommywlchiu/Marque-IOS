#!/usr/bin/env python3
"""plates.py <glb-dir> <out-dir> [car-key ...] — license-plate positions for every frame.

Runs render_car.py's plates=1 pass (geometry only, no rendering; seconds per
car) with each car's own manifest options, so the plates line up with
batch.py's frames. Writes <out-dir>/_plates/<car>.json; publish.py turns the
pixel quads into fractions of the cropped frame. Manifest keys: `platemat`
(the model's plate material(s), else found by name), `plate_rear_z` /
`plate_front_z` (meters from the ground, for a model without a plate)."""
import json, os, subprocess, sys
here = os.path.dirname(os.path.abspath(__file__))
glbdir, outdir = sys.argv[1], sys.argv[2]
manifest = json.load(open(os.path.join(here, "manifest.json")))
os.makedirs(os.path.join(outdir, "_plates"), exist_ok=True)
for key in sys.argv[3:] or list(manifest):
    car = manifest[key]
    out = os.path.join(outdir, "_plates", f"{key}.json")
    args = ["blender", "-b", "-P", os.path.join(here, "render_car.py"), "--",
            f"in={os.path.join(glbdir, key + '.glb')}", f"out={out}", "plates=1", "frames=36",
            "engine=BLENDER_EEVEE", "res=1200x675"]
    for opt in ("flip", "invert"):
        if car.get(opt): args.append(f"{opt}=1")
    for opt in ("roll", "hide", "keep", "platemat", "plate_rear_z", "plate_front_z"):
        if car.get(opt) not in (None, ""): args.append(f"{opt}={car[opt]}")
    result = subprocess.run(args, capture_output=True, text=True)
    line = next((l for l in result.stdout.splitlines() if l.startswith("PLATES")), "FAILED " + result.stderr[-300:])
    print(key, line, flush=True)
