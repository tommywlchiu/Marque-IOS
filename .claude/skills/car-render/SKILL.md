---
name: car-render
description: The Blender car-render pipeline in scripts/car-render — finding and vetting Sketchfab models, rendering turntables, plates, tint masks, wheels/stance and roof & body extras, checking and publishing to public/carRenders. Use when adding or re-rendering a car, fixing how one renders, adding a wheel style or extra, or touching any script in scripts/car-render.
---

# Car render pipeline (`scripts/car-render/`)

Real 3D car models rendered in Blender, not drawn in code. How the **app** uses the output (catalog matching, `RenderedCarSpinView`, hosting rules) is in CLAUDE.md › Car Renders; this is how the output is made.

Needs Blender (`brew install --cask blender`) and the owner's Sketchfab API token in `~/.config/marque/sketchfab_token` — never in the repo, never read it into the conversation.

## Working files
**Outside the repo, in `~/MarqueAssets/car-render/`** (never a session temp dir — the first full set lived in one and would have been deleted with it): `glb/<car>.glb` (downloaded models, not redistributable in the repo), `addons/` (wheel pack), `renders/` (raw output: `_png/` frames, `_plates/`, `_tint/`, `_wheels/`, `_extras/` — ~16 GB, hours of rendering; `publish.py` re-reads it for any partial republish). Every script takes these as arguments:
```bash
cd scripts/car-render; A=~/MarqueAssets/car-render
python3 find.py    /tmp/sheet.jpg "2024 audi a5 sportback"
python3 prep.py    $A/glb $A/prep <car>
python3 batch.py   $A/glb $A/renders <car>
python3 plates.py  $A/glb $A/renders <car>
python3 tints.py   $A/glb $A/renders <car>
python3 wheels.py  $A/glb $A/addons $A/renders <car>
python3 extras.py  $A/glb $A/renders <car>
python3 publish.py $A/renders [<car>…] [--extras|--catalog-only]
python3 check.py [<car>…]                          # must end "0 problem(s)"
```
Same disk as the repo, so it's only as safe as the Mac's backup (Time Machine).

## Adding a car, in order
1. **Find** — `find.py` searches Sketchfab (CC BY-type licenses only — **never NonCommercial/NoDerivatives**) and writes a thumbnail contact sheet. A car goes in `picks.json` only after its thumbnail is checked to be the right make, model **and generation** (the first "2003 Accord" found was the UK/Euro car — the US Acura TSX — not the US Accord).
2. **Prep** — `prep.py` downloads each pick, guesses its body-paint material and renders a RED test shot; the sheet shows wrong paint guesses and backwards cars at a glance. Corrections go in `prep.json` (`paintmat`, may be `a|b|c`; `flip`; `rejected`; `known_issue`), then accepted cars are merged into `manifest.json`. Generics (unbadged body-style stand-ins) are manifest entries with `bodyStyles` instead of `covers`; `keep=<node>` renders one car out of a multi-car pack, square to the axes. Never stand a real model in for another make.
3. **Render** — `batch.py`: every manifest car × `palette.json`'s 12 colors × 36 angles (EEVEE, ~2.4 s/frame, ~18 min/car). Studio lighting is camera-invisible emissive softboxes the paint reflects, seen by EEVEE only through the sphere light probe `render_car.py` adds. Cycles looks slightly better but costs 7–11 s/frame (~30+ h for the catalog).
4. **Plates, tint, wheels, extras** (below), then **`check.py`**, then look at a contact sheet — the check catches geometry, not looks.
5. **Publish** — `publish.py` crops each car's frames to one shared box (so it doesn't jump while spinning), writes `public/carRenders/v1/<car>/<color>/<NN>.webp` (~23 KB/frame, gitignored) and `catalog.json` with credits read from Sketchfab's API. Test locally (CLAUDE.md › Car Renders), then deploy Hosting with the `deploy` skill — with approval. Changed pixels for a published car need a new `v2/` path, never an overwrite (1-year immutable cache).

## `render_car.py` — fixing how a model renders
Normalizes orientation (length > width > height; upright by where the glass is; `flip` for front/back), scale, and **rebuilds** each paint material as one clean shader (models' own paint setups vary wildly: textured, mixed, Portuguese names like `Carro_Pintura`). Tires/rubber are forced dark (several models ship without tire textures). Manifest fields / options:
- `styles` (`mat|mat:preset;…`, presets `glass/chrome/satin/trim/gloss/interior/redlight/amber/lamp`) — required for an **untextured** model (every material the same flat gray — the Ram), or its glass, bumpers and trim all render white. **Material styling only**: a generic's body styles are `bodyStyles` (see the Blender pitfall in CLAUDE.md).
- `matid=1` — every material a flat distinct color, names printed as `MATID` lines: how to see which material is which.
- `invert` — overrides the upright check for a model whose windows aren't a "glass" material; `roll=<deg>` turns a model the size check leaves on its side; `hide=mat|mat` deletes objects made only of those materials (a baked shadow plane) before orienting.
- Reject a model whose windows are inside the body-paint material — no `styles` can fix that (every free 2021+ F-150 is like this).
- Always run Blender with `--python-exit-code 1` and judge by the outputs (count PNGs: 432 per car) — Blender exits 0 when the script crashes (`check_pitfalls.py` enforces the flag).

## Layers
- **Plates** — `plates.py` runs the geometry-only `plates=1` pass (seconds per car): where each plate lands in every frame — the model's own plate geometry (`platemat`, else found by name; `platemat: none` when the name match is a badge), otherwise a US 12×6 in plate where a ray at `plate_rear_z` (m from the bounding-box floor) hits the tail; `plate_rear_w` for a European-width recess. Check each car's position by eye against a straight-behind view. `publish.py` writes `<car>/plates.json` (quads as fractions of the cropped frame) and `plates: true`.
- **Tint** — `tints.py` renders the `mask=glass` pass (windows white, everything else a holdout; glass = manifest `tintmat`, else styles/name/transparency, minus faces below `belt` 0.6 of the height so lamp lenses aren't tinted); `publish.py` writes lossless `<car>/tint/NN.webp` + `tint: true`.
- **Wheels** — `addons.json` lists styles from a CC BY wheel pack (node per style; `wheelout` flips which face is outward, checked by eye). `wheels.py` renders the `wheelpack` pass per car × style: the car's own wheels found by geometry (tire-named faces, else the tallest floor-touching connected piece per corner, mirrored per axle; `wheel_r`/`wheelfix` overrides) and hidden, the body a holdout so fenders still cover the new wheel, the pack wheel's axle found by PCA. The `stock` layer (`wheelstock=1`: the car's own wheels alone) plus `meter` (one meter as a fraction of the frame) drive stance in the app. The far-side wheels legitimately show under a high body (trucks), more for a deep-dish style — `check.py` matches wheel by wheel for that reason.
- **Roof & body extras** — built from primitives (`extras_scene.py`, exec'd by `render_car.py`'s `extra=<id>`: rack, box, lightbar, spoiler), so no third-party model or credit. Fitted by rays cast straight down onto the car (roof run, crown — median-filtered past antennas — and half-width); the body behind the roof decides pickup / trunk → rear wing / otherwise → light bar; manifest `extras` overrides; `extra=measure` (+ `profile=1`) prints the measurements. `extras.py` renders each car's fitting layers (the car a holdout) and writes `_extras/<car>/fits.json`. `publish.py --extras [car…]` crops each layer to **its own** box and lists it as `extras: {id: [x, y, w, h]}` in fractions of the car's frame (y < 0 = above); the car's crop box is kept in `scale.json`.
