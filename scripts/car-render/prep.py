#!/usr/bin/env python3
"""prep.py <glb-dir> <test-dir> [key ...] — for each picks.json car: download the GLB (Sketchfab
token in ~/.config/marque/sketchfab_token), guess its body-paint material, and render a RED test
shot at the hero angle so a wrong paint guess or a backwards car is obvious on the contact sheet.
Writes the guesses to prep.json; a human checks the sheet, then fixes paintmat/flip there."""
import json, os, subprocess, sys, urllib.request
here = os.path.dirname(os.path.abspath(__file__))
glbdir, testdir = sys.argv[1], sys.argv[2]
only = sys.argv[3:]
os.makedirs(glbdir, exist_ok=True); os.makedirs(testdir, exist_ok=True)
picks = {k: v for k, v in json.load(open(os.path.join(here, "picks.json"))).items() if not k.startswith("_")}
token = open(os.path.expanduser("~/.config/marque/sketchfab_token")).read().strip()
out_path = os.path.join(here, "prep.json")
prep = json.load(open(out_path)) if os.path.exists(out_path) else {}
HINTS = ("paint", "body", "carpaint", "car_paint", "primary", "main", "exterior", "color", "colour", "kraska")
SKIP = ("glass", "window", "tire", "tyre", "rubber", "chrome", "black", "interior", "light", "lamp", "wheel", "rim", "plate", "logo", "badge", "mirror")
for key, car in picks.items():
    if only and key not in only: continue
    glb = os.path.join(glbdir, f"{key}.glb")
    if not os.path.exists(glb):
        req = urllib.request.Request(f"https://api.sketchfab.com/v3/models/{car['uid']}/download", headers={"Authorization": f"Token {token}"})
        d = json.load(urllib.request.urlopen(req))
        url = (d.get("glb") or {}).get("url")
        if not url: print("NO GLB", key, list(d)); continue
        urllib.request.urlretrieve(url, glb)
    js = os.path.join(testdir, f"{key}.mats.json")
    subprocess.run(["blender", "-b", "--python-exit-code", "1", "-P", os.path.join(here, "inspect_car.py"), "--", glb, js], stdout=subprocess.DEVNULL, check=True)
    mats = json.load(open(js))
    named = [n for n in mats if any(h in n.lower() for h in HINTS) and not any(s in n.lower() for s in SKIP) and mats[n]["alpha"] > 0.9]
    pool = named or [n for n in mats if not any(s in n.lower() for s in SKIP) and mats[n]["alpha"] > 0.9]
    paint = max(pool, key=lambda n: mats[n]["area"]) if pool else max(mats, key=lambda n: mats[n]["area"])
    entry = prep.get(key, {})
    entry.setdefault("paintmat", paint); entry.setdefault("flip", False)
    prep[key] = entry
    json.dump(prep, open(out_path, "w"), indent=2)
    subprocess.run(["blender", "-b", "--python-exit-code", "1", "-P", os.path.join(here, "render_car.py"), "--", f"in={glb}",
                    f"out={os.path.join(testdir, key + '.png')}", "paint=0.6,0.02,0.02", f"paintmat={entry['paintmat']}",
                    "engine=BLENDER_EEVEE", "samples=24", "res=800x450"] + (["flip=1"] if entry["flip"] else []),
                   stdout=subprocess.DEVNULL, check=True)
    print("PREPPED", key, "paint=" + entry["paintmat"], flush=True)
