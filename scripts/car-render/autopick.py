#!/usr/bin/env python3
"""autopick.py [--priority N] [--limit K] [--out file.json] — Sketchfab candidates for the gaps coverage.py lists.

For each missing model-generation it searches Sketchfab (CC BY-type only, like
find.py) and ranks results: the model name must be in the title; a year in the
title inside the generation scores highest, a title year outside it is rejected;
wreck/lego/lowpoly-for-printing style titles and very light or very heavy meshes
are penalised. Writes the best pick per model-generation to --out
(default autopicks.json) as picks.json-shaped entries. These are candidates only:
prep.py's red test shot and the contact sheet still decide what ships."""
import json, os, re, subprocess, sys, time, urllib.parse, urllib.request

here = os.path.dirname(os.path.abspath(__file__))
args = sys.argv[1:]
pri = args[args.index("--priority") + 1] if "--priority" in args else "1"
limit = int(args[args.index("--limit") + 1]) if "--limit" in args else 999
out = args[args.index("--out") + 1] if "--out" in args else os.path.join(here, "autopicks.json")
gaps = []
for line in subprocess.run([sys.executable, os.path.join(here, "coverage.py"), "--priority", pri], capture_output=True, text=True).stdout.splitlines():
    m = re.match(r"\s+(.+?) (\S+(?: \S+)*?) (\d{4})-(\d{4})$", line)
    if m: gaps.append(m.groups())
wish = json.load(open(os.path.join(here, "wishlist.json")))
# split "Make Model" correctly using the wishlist's make names
makes = sorted(wish, key=len, reverse=True)
parsed = []
for line in subprocess.run([sys.executable, os.path.join(here, "coverage.py"), "--priority", pri], capture_output=True, text=True).stdout.splitlines():
    m = re.match(r"\s+(.+) (\d{4})-(\d{4})$", line)
    if not m: continue
    text = m.group(1)
    make = next((k for k in makes if text.startswith(k + " ")), None)
    if make: parsed.append((make, text[len(make) + 1:], int(m.group(2)), int(m.group(3))))
ERA = re.compile(r"\b(e21|e23|e24|e28|e30|e34|e36|e38|e39|e46|e32|w124|w126|w123|w201|w202|w140|ae86|fc3s|fd3s|s13|s14|s15|r32|r33|r34|ek9|b13|b14|b15|1st gen|classic|vintage|retro)\b", re.I)
BAD = re.compile(r"wreck|lego|3d.?print|scan|interior only|wheel|rim|engine|kit|widebody|drift|rally|race|gt3|police|taxi|tractor|bus|truck pack|pack\b|collection|lowpoly|low poly|low-poly", re.I)


def norm(s): return "".join(c for c in s.lower() if c.isalnum())


def search(q):
    url = ("https://api.sketchfab.com/v3/search?type=models&downloadable=true&count=24&sort_by=-likeCount&q=" + urllib.parse.quote(q))
    for attempt in range(3):
        try:
            return json.load(urllib.request.urlopen(url)).get("results", [])
        except Exception:
            time.sleep(3)
    return []


picks = {}
used = set()
for make, model, y0, y1 in parsed[:limit]:
    mid = (y0 + y1) // 2
    seen, scored = set(), []
    for q in (f"{make} {model}", f"{mid} {make} {model}"):
        for r in search(q):
            lic = (r.get("license") or {}).get("label", "")
            if r["uid"] in seen or not lic or "NonCommercial" in lic or "NoDerivs" in lic or lic.startswith("Free Standard") or "Standard" in lic:
                continue
            seen.add(r["uid"])
            name = r["name"]
            if norm(model) not in norm(name) or norm(make) not in norm(name) and make.split()[0].lower() not in name.lower():
                continue
            if BAD.search(name): continue
            if y0 >= 2000 and ERA.search(name): continue
            if r['uid'] in used: continue
            faces = r.get("faceCount") or 0
            if faces < 15000 or faces > 1600000: continue
            years = [int(y) for y in re.findall(r"\b(19[5-9]\d|20[0-3]\d)\b", name)]
            s = 0
            if years:
                if any(y0 - 1 <= y <= y1 + 1 for y in years): s += 50
                else: continue
            s += min(r.get("likeCount") or 0, 60) / 3
            s -= abs(faces - 250000) / 100000
            scored.append((s, r["uid"], name, faces, r.get("likeCount")))
    scored.sort(reverse=True)
    key = re.sub(r"[^a-z0-9]+", "-", f"{make} {model} {y0}".lower()).strip("-")
    if scored:
        s, uid, name, faces, likes = scored[0]
        used.add(uid)
        picks[key] = {"uid": uid, "make": make, "model": model, "years": [y0, y1], "aliases": [], "verify": f"autopick: {name} ({faces} faces, {likes} likes)"}
        print(f"{make} {model} {y0}-{y1}: {name} [{faces}f {likes}L]")
    else:
        print(f"{make} {model} {y0}-{y1}: -- none")
    time.sleep(0.4)
json.dump(picks, open(out, "w"), indent=1)
print(len(picks), "of", len(parsed[:limit]), "have a candidate")
