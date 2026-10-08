# Roof/body extras scene, exec'd by render_car.py when `extra=<id>` is given (see
# the comment there). Runs in render_car.py's namespace: opt, meshes, bbox,
# turn, yaw. Builds the extra from primitives, fitted to the car, so there is
# no third-party model to license — everything is measured with rays straight
# down onto the car at turntable angle 0 (front at -X).
import json
import numpy as np
import bmesh
from mathutils import Vector, Matrix

EXTRA = opt["extra"]
turn.rotation_euler.z = 0
bpy.context.view_layer.update()
_deps = bpy.context.evaluated_depsgraph_get()
_lo, _hi = bbox(meshes)
_car = set(meshes)
_top_z = _hi.z + 1


def down(x, y):
    """Height of the car's top surface at (x, y), nan off the car."""
    hit, loc, _, _, obj, _ = bpy.context.scene.ray_cast(_deps, Vector((x, y, _top_z)), Vector((0, 0, -1)))
    return loc.z if hit and obj in _car else float("nan")


def running_median(a, w):
    out = np.full_like(a, np.nan)
    for i in range(len(a)):
        win = a[max(0, i - w // 2): i + w // 2 + 1]
        win = win[~np.isnan(win)]
        if len(win): out[i] = np.median(win)
    return out


K = (_hi.y - _lo.y) / 1.85          # accessory scale: this car's width vs a typical 1.85 m
HALF_W = (_hi.y - _lo.y) / 2
HEIGHT = _hi.z - _lo.z

# Side profile down the middle (a median across a few lanes so a shark-fin
# antenna or a sunroof seam doesn't count), then smoothed along the length.
XS = np.arange(_lo.x + 0.02, _hi.x - 0.02, 0.02)
lanes = [-0.2, -0.1, 0.0, 0.1, 0.2]
PROF = running_median(np.array([np.nanmedian([down(x, y * K) for y in lanes]) for x in XS]), 9)

# Roof: the run around the highest point within 7 cm of it.
i_top = int(np.nanargmax(PROF)); ROOF_Z = float(PROF[i_top])
i0 = i1 = i_top
while i0 > 0 and PROF[i0 - 1] >= ROOF_Z - 0.07: i0 -= 1
while i1 < len(XS) - 1 and PROF[i1 + 1] >= ROOF_Z - 0.07: i1 += 1
ROOF_FRONT, ROOF_REAR = float(XS[i0]), float(XS[i1])
ROOF_LEN = ROOF_REAR - ROOF_FRONT


def crown(x, half):
    """The highest point of the roof across [-half, half] at x (what a bar must clear)."""
    # A median across neighbors first, so a shark-fin antenna doesn't count.
    zs = np.array([down(x, y) for y in np.linspace(-half, half, 31)])
    return float(np.nanmax(running_median(zs, 5)))


def half_width(x, z_ref, drop=0.10):
    """How far out from the middle the surface at x stays within `drop` of z_ref."""
    best = HALF_W
    for side in (1, -1):
        y = 0.0
        while y < HALF_W:
            z = down(x, side * (y + 0.02))
            if np.isnan(z) or z < z_ref - drop: break
            y += 0.02
        best = min(best, y)
    return best


# What's behind the roof: a trunk (sedan/coupe), a pickup bed, or the roof
# running to the tail (hatchback/wagon/SUV/van).
rear = XS > ROOF_REAR
REAR_LEN = float(_hi.x - ROOF_REAR)
body = "tail"
deck = None
xb = ROOF_REAR + 0.55 * REAR_LEN
bed_center = down(xb, 0.0)
# Rails: the highest point across the bed (the car's widest point is its
# mirrors, so the bed's sides sit well inside HALF_W).
bed_rails = float(np.nanmax([down(xb, s * f * HALF_W) for s in (1, -1) for f in np.linspace(0.3, 0.9, 13)]))
slope = np.abs(np.gradient(PROF, XS))
# The upper surface behind the roof: from the rear window back to where the
# tail drops away (the trunk lip, the tailgate).
j = int(np.searchsorted(XS, ROOF_REAR)) + 5
while j < len(XS) - 1 and not (slope[j] > 0.6 and PROF[j] < ROOF_Z - 0.2): j += 1
TAIL_X = float(XS[max(j - 1, 0)])
# A level run (slope under ~15 deg) behind the rear window, well below the
# roof but above the bumper line: a trunk deck — or a covered pickup bed when
# it's as long as one.
flat = rear & (slope < 0.27) & (PROF < ROOF_Z - 0.22) & (PROF > _lo.z + 0.5 * (ROOF_Z - _lo.z))
runs, start = [], None
for i, f in enumerate(np.append(flat, False)):
    if f and start is None: start = i
    if not f and start is not None: runs.append((start, i - 1)); start = None
flat_run = max(runs, key=lambda r: r[1] - r[0]) if runs else None
flat_len = float(XS[flat_run[1]] - XS[flat_run[0]]) if flat_run else 0.0
# Low and long for its width: a sedan or coupe, fastbacks included (their
# trunk lid slopes all the way to the lip).
LOW = (ROOF_Z - _lo.z) / (2 * HALF_W) < 0.72
if REAR_LEN > 1.3 and (np.isnan(bed_center) or bed_rails - bed_center > 0.15 or flat_len > 0.9):
    body = "pickup"
elif REAR_LEN > 0.9 and (flat_len >= 0.2 or LOW):
    body = "trunk"
    deck = {"rear": TAIL_X, "z": float(PROF[np.searchsorted(XS, TAIL_X)])}

FITS = ["rack", "box"] + (["spoiler"] if body == "trunk" else ["lightbar"])
if opt.get("extras"):  # manifest override
    FITS = opt["extras"].split("|")

if EXTRA == "measure":
    info = {"body": body, "roof": [round(ROOF_FRONT, 2), round(ROOF_REAR, 2), round(ROOF_Z, 2)],
            "rearLen": round(REAR_LEN, 2), "bed": None if np.isnan(bed_center) else round(float(bed_rails - bed_center), 2),
            "flat": round(flat_len, 2), "ratio": round(float((ROOF_Z - _lo.z) / (2 * HALF_W)), 2),
            "deck": deck and {k: round(v, 2) for k, v in deck.items()},
            "hw": round(half_width((ROOF_FRONT + ROOF_REAR) / 2, ROOF_Z), 2), "fits": FITS}
    print("EXTRAS", json.dumps(info))
    if opt.get("profile") == "1":
        print("PROFILE", " ".join(f"{x:.1f}:{z:.2f}" for x, z in zip(XS[::5], PROF[::5])))
        for x in np.arange(ROOF_REAR, _hi.x, 0.2):
            print("XSEC", round(float(x), 1), " ".join(f"{down(x, f * HALF_W):.2f}" for f in np.linspace(0, 1, 11)))
    if out.endswith(".json"): json.dump(info, open(out, "w"))
    sys.exit(0)

if EXTRA not in FITS:
    print("EXTRA_DOES_NOT_FIT", EXTRA, body); sys.exit(1)


# ---- materials -------------------------------------------------------------
def principled(name, rgb, rough, metal=0.0, coat=0.0):
    m = bpy.data.materials.new(name); m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*rgb, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if "Coat Weight" in b.inputs: b.inputs["Coat Weight"].default_value = coat
    return m

SATIN = principled("ExtraSatin", (0.012, 0.012, 0.013), 0.42)
GLOSS = principled("ExtraGloss", (0.008, 0.008, 0.009), 0.12, coat=1.0)
RUBBER = principled("ExtraRubber", (0.02, 0.02, 0.02), 0.8)
LENS = principled("ExtraLens", (0.85, 0.86, 0.88), 0.18, metal=1.0)


def carbon_material(name="ExtraCarbon"):
    """A woven carbon-fiber look built from a checker texture (no third-party
    image, so no credit needed) — two near-black tones in a tight diagonal
    grid under a glossy clearcoat, which reads as a 2x2 twill weave at the
    render's distance and resolution."""
    m = bpy.data.materials.new(name); m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    coord = nt.nodes.new("ShaderNodeTexCoord")
    mapping = nt.nodes.new("ShaderNodeMapping")
    mapping.inputs["Rotation"].default_value = (0, 0, 0.7854)  # 45°, off the panel lines
    checker = nt.nodes.new("ShaderNodeTexChecker")
    checker.inputs["Scale"].default_value = 140  # object-space coords are already in meters
    checker.inputs["Color1"].default_value = (0.006, 0.006, 0.007, 1)
    checker.inputs["Color2"].default_value = (0.055, 0.056, 0.062, 1)
    nt.links.new(coord.outputs["Object"], mapping.inputs["Vector"])
    nt.links.new(mapping.outputs["Vector"], checker.inputs["Vector"])
    nt.links.new(checker.outputs["Color"], bsdf.inputs["Base Color"])
    # The weave reads mainly through how the specular highlight breaks up,
    # not the (dark, subtle) base color alone — vary roughness per cell too.
    rough_ramp = nt.nodes.new("ShaderNodeMapRange")
    rough_ramp.inputs["To Min"].default_value = 0.18
    rough_ramp.inputs["To Max"].default_value = 0.42
    nt.links.new(checker.outputs["Fac"], rough_ramp.inputs["Value"])
    nt.links.new(rough_ramp.outputs["Result"], bsdf.inputs["Roughness"])
    bsdf.inputs["Metallic"].default_value = 0.0
    if "Coat Weight" in bsdf.inputs: bsdf.inputs["Coat Weight"].default_value = 1.0
    if "Coat Roughness" in bsdf.inputs: bsdf.inputs["Coat Roughness"].default_value = 0.1
    return m


CARBON = carbon_material()
# finish=carbon: the spoiler wing in woven carbon fiber instead of gloss
# black, a selectable alternate finish rather than a new extra.
FINISH_MAT = {"carbon": CARBON}.get(opt.get("finish"), GLOSS)

# The car: a holdout, so it still hides whatever part of the extra is behind it.
hold = bpy.data.materials.new("CarHoldout"); hold.use_nodes = True
_nt = hold.node_tree; _nt.nodes.clear()
_nt.links.new(_nt.nodes.new("ShaderNodeHoldout").outputs[0], _nt.nodes.new("ShaderNodeOutputMaterial").inputs["Surface"])
for o in meshes:
    for slot in o.material_slots: slot.link = "DATA"
    o.data = o.data.copy()
    o.data.materials.clear(); o.data.materials.append(hold)
    o.data.polygons.foreach_set("material_index", np.zeros(len(o.data.polygons), dtype=np.int32))


# ---- geometry --------------------------------------------------------------
def block(name, center, size, mat, bevel=0.0, segments=3, shape=None):
    """A box of `size` at `center`, optionally beveled; `shape(v)` may move
    each corner (in the box's own unit frame, -0.5..0.5) before scaling."""
    mesh = bpy.data.meshes.new(name); bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        if shape: shape(v)
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
    bm.to_mesh(mesh); bm.free()
    o = bpy.data.objects.new(name, mesh); bpy.context.scene.collection.objects.link(o)
    o.location = center; o.parent = turn
    mesh.materials.append(mat)
    if bevel:
        mod = o.modifiers.new("Bevel", "BEVEL"); mod.width = bevel; mod.segments = segments
        mod.limit_method = "NONE"
        o.modifiers.new("Smooth", "WEIGHTED_NORMAL")
    for p in mesh.polygons: p.use_smooth = bool(bevel)
    return o


def foot(x, y, z_top, width_x, mat=SATIN):
    """A mounting foot from the roof surface at (x, y) up to z_top."""
    z0 = down(x, y)
    if np.isnan(z0): z0 = z_top - 0.08 * K
    h = z_top - z0 + 0.01
    block(f"Foot{x:.2f}{y:.2f}", (x, y, z0 - 0.01 + h / 2), (width_x, 0.045 * K, h), mat, bevel=0.008)
    block(f"Pad{x:.2f}{y:.2f}", (x, y, z0 + 0.004), (width_x * 1.25, 0.06 * K, 0.012), RUBBER)


def crossbars():
    """Two aero crossbars across the roof, on four feet. Returns the bars'
    x positions and the height of their top surface."""
    b1, b2 = ROOF_FRONT + 0.22 * ROOF_LEN, ROOF_REAR - 0.22 * ROOF_LEN
    if b2 - b1 > 0.95 * K:
        mid = (b1 + b2) / 2; b1, b2 = mid - 0.475 * K, mid + 0.475 * K
    if b2 - b1 < 0.55 * K:  # a short roof: spread to its ends
        b1, b2 = ROOF_FRONT + 0.05, ROOF_REAR - 0.05
    tops = []
    for i, x in enumerate((b1, b2)):
        hw = half_width(x, down(x, 0.0), drop=0.12)
        bar_z = crown(x, hw) + 0.045 * K
        thick = 0.024 * K
        # Aero bar: a flattened teardrop — the trailing edge thinned.
        def teardrop(v):
            if v.co.x > 0: v.co.z *= 0.55
        block(f"Crossbar{i}", (x, 0, bar_z + thick / 2), (0.08 * K, 2 * hw + 0.07 * K, thick), SATIN,
              bevel=0.011 * K, segments=4, shape=teardrop)
        for s in (1, -1):
            foot(x, s * (hw - 0.03 * K), bar_z + 0.004, 0.10 * K)
        tops.append(bar_z + thick)
        print("CROSSBAR", round(x, 2), "z", round(bar_z, 3), "hw", round(hw, 2))
    return (b1, b2), max(tops)


def cargo_box():
    (b1, b2), bar_top = crossbars()
    length = float(np.clip(ROOF_LEN * 1.05, 1.25 * K, 1.9 * K))
    hw = half_width((b1 + b2) / 2, ROOF_Z, drop=0.12)
    width = min(1.6 * hw, 0.86 * K)
    height = 0.30 * K
    # An aero nose: the front bottom swept back, the top a little lower at
    # the front and tail.
    def aero(v):
        if v.co.x < 0 and v.co.z < 0: v.co.x += 0.1
        if v.co.z > 0: v.co.z -= 0.05 if v.co.x < 0 else 0.02
        if v.co.x > 0 and v.co.z < 0: v.co.x -= 0.03
    cx = (b1 + b2) / 2 + 0.03 * K
    block("CargoBox", (cx, 0, bar_top + 0.004 + height / 2), (length, width, height), GLOSS,
          bevel=0.075 * K, segments=6, shape=aero)


def lightbar():
    x = ROOF_FRONT + 0.06 * K
    hw = half_width(x, down(x, 0.0), drop=0.12)
    span = 2 * hw * 0.9
    z = crown(x, hw) + 0.06 * K
    depth, height = 0.075 * K, 0.08 * K
    block("LightbarBody", (x, 0, z), (depth, span, height), SATIN, bevel=0.012 * K)
    lens_x = x - depth / 2 - 0.002
    block("LightbarLens", (lens_x, 0, z), (0.006, span - 0.05 * K, height * 0.72), LENS, bevel=0.002)
    # Dividers between the LED pods.
    n = max(6, int(span / (0.085 * K)))
    for i in range(1, n):
        y = -span / 2 + 0.025 * K + i * (span - 0.05 * K) / n
        block(f"LightbarDiv{i}", (lens_x - 0.004, y, z), (0.006, 0.006, height * 0.72), SATIN)
    for s in (1, -1):
        foot(x + 0.02 * K, s * (span / 2 - 0.09 * K), z - height / 2 + 0.004, 0.07 * K)


def spoiler():
    de = deck["rear"]
    x = de - 0.24 * K
    z_deck = down(x, 0.0)
    hw = half_width(x, z_deck, drop=0.08)
    span = min(2 * hw * 0.85, 1.4 * K)
    chord, thick = 0.2 * K, 0.024 * K
    z = z_deck + 0.1 * K
    # Airfoil: the leading edge rounder, the trailing edge thin; tilted so the
    # trailing edge is higher (front is -X).
    def airfoil(v):
        if v.co.x > 0: v.co.z *= 0.35
    wing = block("Wing", (x, 0, z), (chord, span, thick), FINISH_MAT, bevel=0.012 * K, segments=4, shape=airfoil)
    wing.rotation_euler = (0, math.radians(-8), 0)
    for s in (1, -1):
        y = s * span * 0.32
        z0 = down(x, y)
        h = z - z0
        block(f"Upright{s}", (x + 0.01, y, z0 + h / 2 - 0.005), (0.11 * K, 0.022 * K, h), FINISH_MAT, bevel=0.006)
        block(f"Endplate{s}", (x + 0.01, s * (span / 2 + 0.004), z + 0.012 * K),
              (chord * 1.05, 0.008, 0.075 * K), FINISH_MAT, bevel=0.003)


{"rack": crossbars, "box": cargo_box, "lightbar": lightbar, "spoiler": spoiler}[EXTRA]()
turn.rotation_euler.z = yaw
bpy.context.view_layer.update()
print("EXTRA_BUILT", EXTRA, body)
