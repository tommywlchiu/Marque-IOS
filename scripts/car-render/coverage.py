#!/usr/bin/env python3
"""coverage.py [--priority N] [--make M] [--all] — what the car catalog covers of wishlist.json.

wishlist.json is the target: per make, the models worth a render, each as
generations (year ranges) with a priority (1 = very common in the US, 2 =
common, 3 = niche/enthusiast). A generation counts as covered when a
manifest.json car of the same make names the model (exactly, or the wishlist
name is that name plus a trim) and its years include the generation's
midpoint. Prints the gaps, highest priority first; the work queue for adding
cars (see the car-render skill). Rivian-style entries carry "blocked" and are
listed separately."""
import json, os, sys

here = os.path.dirname(os.path.abspath(__file__))
wish = json.load(open(os.path.join(here, "wishlist.json")))
manifest = json.load(open(os.path.join(here, "manifest.json")))
args = sys.argv[1:]
want_pri = int(args[args.index("--priority") + 1]) if "--priority" in args else 3
want_make = args[args.index("--make") + 1].lower() if "--make" in args else None


def norm(s):
    return "".join(c for c in s.lower() if c.isalnum())


entries = []
for key, car in manifest.items():
    c = car.get("covers")
    if not c or not c.get("make") or not c.get("years"):
        continue
    names = [c["model"]] + list(c.get("aliases", []))
    entries.append((c["make"], [norm(n) for n in names], c["years"], key))


def covered(make, model, gen):
    mid = (gen[0] + gen[1]) / 2
    m = norm(model)
    for emake, names, years, key in entries:
        if norm(emake) != norm(make) or not (years[0] <= mid <= years[1]):
            continue
        if any(m == n or m.startswith(n) and len(n) >= 2 for n in names[:1]) or m in names:
            return key
    return None


total = done = 0
gaps, blocked = [], []
for make, models in wish.items():
    if want_make and norm(make) != norm(want_make):
        continue
    for m in models:
        for gen in m["gens"]:
            total += 1
            if covered(make, m["model"], gen):
                done += 1
            elif m.get("blocked"):
                blocked.append(f'{make} {m["model"]} {gen[0]}-{gen[1]}: {m["blocked"]}')
            elif m["priority"] <= want_pri:
                gaps.append((m["priority"], make, m["model"], gen))
print(f"covered {done}/{total} model-generations ({100 * done // max(total, 1)}%)")
for pri in (1, 2, 3):
    rows = [g for g in gaps if g[0] == pri]
    if rows:
        print(f"\n-- priority {pri}: {len(rows)} missing")
        for _, make, model, gen in sorted(rows, key=lambda r: (r[1], r[2], r[3])):
            print(f"   {make} {model} {gen[0]}-{gen[1]}")
if blocked:
    print("\n-- blocked:")
    for b in blocked:
        print("  ", b)
