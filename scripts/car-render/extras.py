#!/usr/bin/env python3
"""extras.py <glb-dir> <out-dir> [car-key ...] — the roof/body extras add-on layers.

For every car: render_car.py's extra=measure pass (the roof and what's behind
it, measured with rays; which extras fit — rack and box on every roof, a rear
wing on a car with a trunk, a light bar on everything else), written to
<out-dir>/_extras/<car>/fits.json; then 36 frames of each fitting extra
(built from primitives, fitted to this car, the car a holdout), with the
car's own manifest options so it lines up with batch.py's frames. Raw PNGs go
to <out-dir>/_extras/<car>/<extra>/<NN>.png; publish.py crops them. Manifest
override when the guess is wrong: `extras` ("rack|box|spoiler")."""
import glob, json, os, subprocess, sys
from concurrent.futures import ThreadPoolExecutor
here = os.path.dirname(os.path.abspath(__file__))
glbdir, outdir = sys.argv[1], sys.argv[2]
manifest = json.load(open(os.path.join(here, "manifest.json")))


def base_args(key, car, out):
    args = ["blender", "-b", "--python-exit-code", "1", "-P", os.path.join(here, "render_car.py"), "--",
            f"in={os.path.join(glbdir, key + '.glb')}", f"out={out}"]
    for opt in ("flip", "invert"):
        if car.get(opt): args.append(f"{opt}=1")
    for opt in ("roll", "hide", "keep", "extras"):
        if car.get(opt) not in (None, ""): args.append(f"{opt}={car[opt]}")
    return args


def run(key):
    car = manifest[key]
    raw = os.path.join(outdir, "_extras", key)
    os.makedirs(raw, exist_ok=True)
    fits_path = os.path.join(raw, "fits.json")
    result = subprocess.run(base_args(key, car, fits_path) + ["extra=measure"], capture_output=True, text=True)
    if not os.path.exists(fits_path):
        return [f"FAILED {key} measure {(result.stdout + result.stderr).strip().splitlines()[-1:]}"]
    lines = []
    fits = json.load(open(fits_path))["fits"]
    # spoiler-carbon: the same wing, in woven carbon fiber instead of gloss
    # black — a selectable alternate finish, published as its own layer
    # (same geometry/position as "spoiler", so it shares its crop box).
    jobs = list(fits) + (["spoiler-carbon"] if "spoiler" in fits else [])
    for extra in jobs:
        if len(glob.glob(os.path.join(raw, extra, "*.png"))) == 36:
            continue
        base_extra = "spoiler" if extra == "spoiler-carbon" else extra
        finish = ["finish=carbon"] if extra == "spoiler-carbon" else []
        result = subprocess.run(base_args(key, car, raw) + [
            f"extra={base_extra}", f"colors={extra}:1,1,1", "frames=36", "engine=BLENDER_EEVEE", "samples=32",
            "res=1200x675"] + finish, capture_output=True, text=True)
        made = len(glob.glob(os.path.join(raw, extra, "*.png")))
        lines.append(("DONE" if made == 36 else f"FAILED ({made})") + f" {key} {extra}"
                     + ("" if made == 36 else f" {(result.stdout + result.stderr).strip().splitlines()[-1:]}"))
    return lines


with ThreadPoolExecutor(int(os.environ.get("JOBS", 3))) as pool:
    for lines in pool.map(run, sys.argv[3:] or list(manifest)):
        for line in lines: print(line, flush=True)
