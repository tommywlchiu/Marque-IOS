#!/usr/bin/env python3
"""wheels.py <glb-dir> <addon-dir> <out-dir> [car-key ...] — the wheels add-on layers.

For every car and every wheel style in addons.json: 36 frames of
render_car.py's wheelpack pass (the car's wheels hidden, the rest a holdout,
the style's wheel fitted to each tire), with the car's own manifest options
so it lines up with batch.py's frames. Raw PNGs go to
<out-dir>/_wheels/<car>/<style>/<NN>.png; publish.py crops them like the
frames. Manifest overrides for cars detection gets wrong: wheel_r, wheelfix."""
import glob, json, os, subprocess, sys
here = os.path.dirname(os.path.abspath(__file__))
glbdir, addondir, outdir = sys.argv[1], sys.argv[2], sys.argv[3]
manifest = json.load(open(os.path.join(here, "manifest.json")))
addons = json.load(open(os.path.join(here, "addons.json")))
for key in sys.argv[4:] or list(manifest):
    car = manifest[key]
    if car.get("noWheels"):  # detection can't place wheels on this model
        continue
    # "stock" = the car's own wheels alone: the stance add-on draws the car's
    # frame shifted over it (and its alpha says where the wheels show).
    for style in addons["wheels"] + [{"id": "stock"}]:
        raw = os.path.join(outdir, "_wheels", key)
        if len(glob.glob(os.path.join(raw, style["id"], "*.png"))) == 36:
            continue
        args = ["blender", "-b", "--python-exit-code", "1", "-P", os.path.join(here, "render_car.py"), "--",
                f"in={os.path.join(glbdir, key + '.glb')}", f"out={raw}", f"colors={style['id']}:1,1,1",
                "frames=36", "engine=BLENDER_EEVEE", "samples=32", "res=1200x675"]
        if style["id"] == "stock":
            args.append("wheelstock=1")
        else:
            pack = addons["wheelPacks"][style["pack"]]
            args += [f"wheelpack={os.path.join(addondir, pack['file'])}", f"wheelnode={style['node']}",
                     f"wheelout={style['wheelout']}"]
        for opt in ("flip", "invert"):
            if car.get(opt): args.append(f"{opt}=1")
        for opt in ("roll", "hide", "keep", "wheel_r", "wheelfix"):
            if car.get(opt) not in (None, ""): args.append(f"{opt}={car[opt]}")
        result = subprocess.run(args, capture_output=True, text=True)
        made = len(glob.glob(os.path.join(raw, style["id"], "*.png")))
        print("DONE" if made == 36 else f"FAILED ({made})", key, style["id"],
              "" if made == 36 else (result.stdout + result.stderr).strip().splitlines()[-1:], flush=True)
