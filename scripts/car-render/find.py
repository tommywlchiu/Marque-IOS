#!/usr/bin/env python3
"""find.py <out.jpg> "query" ["query" ...] — Sketchfab candidates for a car.

Searches downloadable models, drops NonCommercial/NoDerivatives licenses (we
repaint and sell the app), and writes a numbered contact sheet of thumbnails
plus a printed list, so each candidate can be checked by eye before it goes
in manifest.json. A car is only added after its thumbnail is confirmed to be
the right make, model AND generation.
"""
import io, json, sys, urllib.parse, urllib.request
from PIL import Image, ImageDraw

out, queries = sys.argv[1], sys.argv[2:]
seen, rows = set(), []
for q in queries:
    url = ("https://api.sketchfab.com/v3/search?type=models&downloadable=true&count=24&sort_by=-likeCount&q="
           + urllib.parse.quote(q))
    for m in json.load(urllib.request.urlopen(url)).get("results", []):
        lic = (m.get("license") or {}).get("label", "")
        if m["uid"] in seen or "NonCommercial" in lic or "NoDerivs" in lic or not lic:
            continue
        seen.add(m["uid"])
        thumbs = sorted(m["thumbnails"]["images"], key=lambda t: abs(t["width"] - 640))
        rows.append((m["uid"], m["name"], lic, m.get("faceCount"), m.get("likeCount"), thumbs[0]["url"]))
rows = rows[:16]
sheet = Image.new("RGB", (4 * 320, ((len(rows) + 3) // 4) * 200 or 200), (20, 20, 20))
for i, (uid, name, lic, faces, likes, turl) in enumerate(rows):
    print(f"{i:2d} {uid} | {name[:50]:50} | {lic} | faces {faces} | likes {likes}")
    try:
        im = Image.open(io.BytesIO(urllib.request.urlopen(turl).read())).convert("RGB")
        im.thumbnail((320, 180))
        x, y = (i % 4) * 320, (i // 4) * 200
        sheet.paste(im, (x, y))
        ImageDraw.Draw(sheet).text((x + 4, y + 182), f"{i} {name[:42]}", fill=(255, 255, 255))
    except Exception as e:
        print("   thumb failed:", e)
sheet.save(out)
