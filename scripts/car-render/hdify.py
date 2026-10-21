#!/usr/bin/env python3
"""hdify.py <car-key> [...] — registers `<key>-hd`, a higher-resolution re-render of an
existing car, in manifest.json and links its model as glb/<key>-hd.glb. Render it with
RENDER_SCALE=1.5 (see renderconfig.py) into a renders dir of its own, then publish.py
`<key>-hd` (RENDER_OUT=v1): the catalog lists the -hd entry instead of the original
(`supersedes`). A new key means a new URL, so devices that cached the old frames
(immutable, a year) never mix resolutions."""
import json, os, sys
here = os.path.dirname(os.path.abspath(__file__))
glb = os.path.expanduser("~/MarqueAssets/car-render/glb")
m = json.load(open(os.path.join(here, "manifest.json")))
for key in sys.argv[1:]:
    hd = key + "-hd"
    m[hd] = {**m[key], "supersedes": key}
    link = os.path.join(glb, hd + ".glb")
    if not os.path.lexists(link): os.symlink(os.path.join(glb, key + ".glb"), link)
    print("registered", hd)
open(os.path.join(here, "manifest.json"), "w").write(json.dumps(m, indent=2) + "\n")
