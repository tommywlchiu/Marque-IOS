import bpy, sys, math, glob, os
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
# blender -b -P render_car.py -- in=<glb> out=<png> yaw=35 paint=r,g,b paintmat=<name> flip=1 samples=96
opt = dict(a.split("=", 1) for a in argv)
src, out = os.path.abspath(opt["in"]), os.path.abspath(opt["out"])
yaw = math.radians(float(opt.get("yaw", 35)))
paint = tuple(float(c) for c in opt["paint"].split(",")) if "paint" in opt else None
paintmats = opt.get("paintmat", "").split("|") if opt.get("paintmat") else []
engine = opt.get("engine", "CYCLES")
FLIP = opt.get("flip") == "1"

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
# hide=mat|mat: delete objects made only of these materials (a baked shadow
# plane, say) before orienting — they'd skew the bounding box.
hidden = set(opt.get("hide", "").split("|")) - {""}
for o in [o for o in bpy.context.scene.objects if o.type == "MESH"]:
    names = {s.material.name for s in o.material_slots if s.material}
    if hidden and names and names <= hidden:
        bpy.data.objects.remove(o, do_unlink=True)
# keep=<node>: a multi-car pack — keep only the car under this node (its
# wheels are separate objects, so keep every mesh whose center falls inside
# the car's footprint), and turn it square to the axes (the pack lays its
# cars out in a circle at arbitrary angles).
keep_rot = None
if "keep" in opt:
    from mathutils import Vector as V
    node = bpy.data.objects[opt["keep"]]
    body = [c for c in node.children_recursive if c.type == "MESH"] + ([node] if node.type == "MESH" else [])
    pts = [m.matrix_world @ V(c) for m in body for c in m.bound_box]
    lo = V([min(p[i] for p in pts) - 0.3 for i in range(3)]); hi = V([max(p[i] for p in pts) + 0.3 for i in range(3)])
    for o in [o for o in bpy.context.scene.objects if o.type == "MESH"]:
        c = sum((o.matrix_world @ V(b) for b in o.bound_box), V()) / 8
        if not all(lo[i] <= c[i] <= hi[i] for i in range(3)):
            bpy.data.objects.remove(o, do_unlink=True)
    keep_rot = node.matrix_world.to_quaternion()
meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]

# Bounding box in world space
def bbox(objs):
    lo = Vector((1e9,) * 3); hi = Vector((-1e9,) * 3)
    for o in objs:
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            lo = Vector(map(min, lo, w)); hi = Vector(map(max, hi, w))
    return lo, hi

root = bpy.data.objects.new("CarRoot", None)
bpy.context.scene.collection.objects.link(root)
for o in bpy.context.scene.objects:
    if o.parent is None and o is not root:
        o.parent = root
bpy.context.view_layer.update()
from mathutils import Matrix
if keep_rot is not None:  # into the kept car's own frame; the checks below square up the rest
    root.matrix_world = keep_rot.inverted().to_matrix().to_4x4() @ root.matrix_world
    bpy.context.view_layer.update()
def rot(axis):
    root.matrix_world = Matrix.Rotation(math.radians(90), 4, axis) @ root.matrix_world
    bpy.context.view_layer.update()
    return bbox(meshes)
# A car is longest along its length, then width, then height: map those to X, Y, Z.
lo, hi = bbox(meshes); s = hi - lo
if s.z > s.x and s.z > s.y: lo, hi = rot("Y"); s = hi - lo
if s.y > s.x: lo, hi = rot("Z"); s = hi - lo
if s.z > s.y: lo, hi = rot("X"); s = hi - lo
# Which way is up: windows are always in the upper half of a car.
def glass_z():
    zs = []
    for o in meshes:
        mw = o.matrix_world
        for poly in o.data.polygons:
            if poly.material_index < len(o.material_slots):
                m = o.material_slots[poly.material_index].material
                if m and "glass" in m.name.lower():
                    zs.append((mw @ poly.center).z)
    return sum(zs) / len(zs) if zs else None
gz = glass_z()
# invert=1 overrides it for a model whose windows aren't a "glass" material.
if (gz is not None and gz < (lo.z + hi.z) / 2) != (opt.get("invert") == "1"):
    lo, hi = rot("X"); lo, hi = rot("X")
    print("FLIPPED_UPRIGHT")
# roll=<deg>: manual turn about the length axis, for a model the size check
# above leaves on its side (something on it is taller than the car is wide).
if "roll" in opt: root.matrix_world = Matrix.Rotation(math.radians(float(opt["roll"])), 4, "X") @ root.matrix_world
if FLIP: root.matrix_world = Matrix.Rotation(math.pi, 4, "Z") @ root.matrix_world
bpy.context.view_layer.update()
lo, hi = bbox(meshes)
size = hi - lo
scale = 4.7 / max(size.x, 0.001)  # normalize to ~4.7 m long
root.scale = (scale,) * 3
bpy.context.view_layer.update()
lo, hi = bbox(meshes)
center = (lo + hi) / 2
root.location -= Vector((center.x, center.y, lo.z))
bpy.context.view_layer.update()
lo, hi = bbox(meshes)
print("CAR_BBOX", tuple(round(v, 2) for v in lo), tuple(round(v, 2) for v in hi))

# Turntable: spin the car, keep camera/lights fixed
turn = bpy.data.objects.new("Turntable", None)
bpy.context.scene.collection.objects.link(turn)
root.parent = turn
turn.rotation_euler.z = yaw

# Body paint: each named material is rebuilt as a single clean car-paint
# shader (whatever textures/mix nodes it had are dropped), so every model
# repaints the same way. Tires/rubber are forced dark — several models ship
# without their tire textures and would otherwise render white.
def make_paint(m):
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    out_node = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(bsdf.outputs["BSDF"], out_node.inputs["Surface"])
    bsdf.inputs["Metallic"].default_value = 0.5
    bsdf.inputs["Roughness"].default_value = 0.22
    if "Coat Weight" in bsdf.inputs: bsdf.inputs["Coat Weight"].default_value = 1.0
    m.surface_render_method = "DITHERED"
    return bsdf

paint_bsdfs = [make_paint(bpy.data.materials[n]) for n in paintmats]
for m in bpy.data.materials:
    if any(t in m.name.lower() for t in ("tire", "tyre", "rubber", "pneu")) and m.name not in paintmats:
        b = make_paint(m)
        b.inputs["Base Color"].default_value = (0.02, 0.02, 0.02, 1)
        b.inputs["Metallic"].default_value = 0.0
        b.inputs["Roughness"].default_value = 0.85
        if "Coat Weight" in b.inputs: b.inputs["Coat Weight"].default_value = 0.0
if paint:
    for b in paint_bsdfs: b.inputs["Base Color"].default_value = (*paint, 1)

# styles=mat|mat:preset;... — for untextured models (every material the same
# flat gray), give named materials a look so glass, trim and lights read right.
STYLES = {  # base color (linear), metallic, roughness, coat
    "glass":    ((0.004, 0.005, 0.006), 0.0, 0.03, 1.0),
    "chrome":   ((0.9, 0.9, 0.9), 1.0, 0.06, 0.0),
    "satin":    ((0.35, 0.35, 0.36), 1.0, 0.3, 0.0),
    "trim":     ((0.015, 0.015, 0.015), 0.0, 0.55, 0.0),
    "gloss":    ((0.01, 0.01, 0.01), 0.0, 0.15, 1.0),
    "interior": ((0.025, 0.025, 0.025), 0.0, 0.8, 0.0),
    "redlight": ((0.35, 0.005, 0.005), 0.0, 0.05, 1.0),
    "amber":    ((0.6, 0.18, 0.01), 0.0, 0.05, 1.0),
    "lamp":     ((0.7, 0.7, 0.72), 0.3, 0.05, 1.0),
}
for entry in filter(None, opt.get("styles", "").split(";")):
    names, preset = entry.rsplit(":", 1)
    rgb, metal, rough, coat = STYLES[preset]
    for n in names.split("|"):
        b = make_paint(bpy.data.materials[n])
        b.inputs["Base Color"].default_value = (*rgb, 1)
        b.inputs["Metallic"].default_value = metal
        b.inputs["Roughness"].default_value = rough
        if "Coat Weight" in b.inputs: b.inputs["Coat Weight"].default_value = coat

# matid=1: every material a flat, distinct color (printed as MATID lines), to
# tell which unnamed material is which on a model that needs `styles`.
if opt.get("matid") == "1":
    import colorsys
    used = sorted({s.material.name for o in meshes for s in o.material_slots if s.material})
    for i, name in enumerate(used):
        rgb = colorsys.hsv_to_rgb((i * 0.618034) % 1, 0.85, 0.95 if i % 2 else 0.6)
        m = bpy.data.materials[name]; m.use_nodes = True
        nt = m.node_tree; nt.nodes.clear()
        em = nt.nodes.new("ShaderNodeEmission"); em.inputs["Color"].default_value = (*rgb, 1)
        nt.links.new(em.outputs[0], nt.nodes.new("ShaderNodeOutputMaterial").inputs["Surface"])
        print("MATID", name, ",".join(f"{c:.3f}" for c in rgb))

# mask=glass: a window mask for the app's tint add-on — the glass flat white,
# everything else a holdout (transparent, but still hiding what's behind
# it). Glass is `tintmat=a|b`, else the materials `styles` makes glass, else
# found by name (not headlight/taillight lenses).
if opt.get("mask") == "glass":
    import re
    if opt.get("tintmat"):
        glass = set(opt["tintmat"].split("|"))
    else:
        lens = re.compile(r"light|lamp|head|tail|brake|signal|led|mirror|interior|trim|feux|phare|lampu|clignot|vermelho|laranja|kuning|red|orange|amber", re.I)
        def transparent(m):
            bsdf = next((n for n in (m.node_tree.nodes if m.node_tree else []) if n.type == "BSDF_PRINCIPLED"), None)
            return bsdf is not None and (bsdf.inputs["Alpha"].default_value < 0.95 or bsdf.inputs["Transmission Weight"].default_value > 0.3)
        glass = {n for e in filter(None, opt.get("styles", "").split(";")) if e.endswith(":glass") for n in e.rsplit(":", 1)[0].split("|")}
        glass |= {m.name for m in bpy.data.materials if not lens.search(m.name)
                  and (re.search(r"glass|window|windshield|vidro|vitre|steklo|kaca|backlight", m.name, re.I) or transparent(m))}
    # Lamp lenses are often glass too; they sit low on the body, windows
    # above the beltline. Glass faces below it get a holdout of their own.
    low = bpy.data.materials.new("MaskHoldoutLow"); low.use_nodes = True
    nt = low.node_tree; nt.nodes.clear()
    nt.links.new(nt.nodes.new("ShaderNodeHoldout").outputs[0], nt.nodes.new("ShaderNodeOutputMaterial").inputs["Surface"])
    blo, bhi = bbox(meshes); belt = blo.z + float(opt.get("belt", 0.6)) * (bhi.z - blo.z)
    for o in meshes:
        if not any(s.material and s.material.name in glass for s in o.material_slots): continue
        o.data.materials.append(low); low_index = len(o.material_slots) - 1; mw = o.matrix_world
        for p in o.data.polygons:
            mat = o.material_slots[p.material_index].material
            if mat and mat.name in glass and (mw @ p.center).z < belt:
                p.material_index = low_index
    for o in meshes:
        for slot in o.material_slots:
            m = slot.material
            if not m or m is low: continue
            m.use_nodes = True; nt = m.node_tree; nt.nodes.clear()
            if m.name in glass:
                sh = nt.nodes.new("ShaderNodeEmission"); sh.inputs["Color"].default_value = (1, 1, 1, 1)
            else:
                sh = nt.nodes.new("ShaderNodeHoldout")
            nt.links.new(sh.outputs[0], nt.nodes.new("ShaderNodeOutputMaterial").inputs["Surface"])
            m.surface_render_method = "DITHERED"
    print("GLASS", sorted(glass))

# wheelpack=<glb> wheelnode=<node>: the wheels add-on layer — the car's own
# wheels made invisible, the rest of the car a holdout (the fenders still
# hide what they should), and the pack's wheel (rim + its own tire) placed at
# each of the car's wheels, scaled to its tire. The app draws this over the
# car's frames. Tires are `tiremat=a|b`, else found by name.
# wheelstock=1: the car's own wheels alone (the body a holdout). Its alpha is
# also where the wheels show in the frame, so with the frame shifted over it
# the app fakes a lowered/lifted stance without re-rendering the car.
WHEEL_MODE = "wheelpack" if "wheelpack" in opt else "stock" if opt.get("wheelstock") == "1" else None
if WHEEL_MODE:
    import re
    from mathutils import Vector as V
    turn.rotation_euler.z = 0; bpy.context.view_layer.update()
    tire_pat = re.compile(r"tire|tyre|pneu|reifen|gomma|llanta|shina", re.I)
    def is_tire(m): return bool(m) and bool(tire_pat.search(m.name))
    # The car's wheels, found by geometry (names are unreliable — one
    # model's "Rubber" is its door seals; and many models merge the tires
    # into the body mesh): in each corner, the connected piece of geometry
    # that touches the floor and is wheel-sized is the tire.
    import numpy as np
    def world_verts(o):
        co = np.empty(len(o.data.vertices) * 3); o.data.vertices.foreach_get("co", co)
        co = co.reshape(-1, 3); m = np.array(o.matrix_world)
        return co @ m[:3, :3].T + m[:3, 3]
    def components(o):
        """Connected pieces of a mesh: a component id per vertex (union-find)."""
        n = len(o.data.vertices); parent = np.arange(n)
        ev = np.empty(len(o.data.edges) * 2, dtype=np.int32); o.data.edges.foreach_get("vertices", ev)
        ev = ev.reshape(-1, 2)
        def find(a):
            while parent[a] != a:
                parent[a] = parent[parent[a]]; a = parent[a]
            return a
        for a, b in ev:
            ra, rb = find(a), find(b)
            if ra != rb: parent[ra] = rb
        return np.array([find(i) for i in range(n)])
    verts = {o.name: world_verts(o) for o in meshes}
    floor = min(v[:, 2].min() for v in verts.values() if len(v))
    comp_cache = {}
    def comps(o):
        if o.name not in comp_cache: comp_cache[o.name] = components(o)
        return comp_cache[o.name]
    def box(o):
        v = verts[o.name]; return V(v.min(0)), V(v.max(0))
    # Tire-named geometry per corner, when a model has it (most reliable).
    named = {}
    for o in meshes:
        v = verts[o.name]; mw = o.matrix_world
        for p in o.data.polygons:
            if p.material_index < len(o.material_slots) and is_tire(o.material_slots[p.material_index].material):
                pts = v[list(p.vertices)]
                c = pts.mean(0)
                named.setdefault((c[0] > 0, c[1] > 0), []).append(pts)
    wheels = []
    for sx in (1, -1):
        for sy in (1, -1):
            best = None
            tire = named.get((sx > 0, sy > 0))
            if tire:
                pts = np.vstack(tire); lo, hi = V(pts.min(0)), V(pts.max(0)); size = hi - lo
                if 0.3 <= size.z <= 1.2 and size.y <= size.z and size.x <= size.z * 1.4:
                    wheels.append({"center": (lo + hi) / 2, "radius": size.z / 2, "width": size.y,
                                   "side": sy, "axle": sx, "floor": lo.z})
                    continue
            # The lowest point in this corner (a model can carry something
            # lower than its tires elsewhere, like a shadow plane).
            corner_floor = min((v[(v[:, 0] * sx > 0.4) & (v[:, 1] * sy > 0.2)][:, 2].min()
                                for v in verts.values() if ((v[:, 0] * sx > 0.4) & (v[:, 1] * sy > 0.2)).any()), default=floor)
            for o in meshes:
                v = verts[o.name]
                touch = np.where((v[:, 2] <= corner_floor + 0.03) & (v[:, 0] * sx > 0.4) & (v[:, 1] * sy > 0.2))[0]
                if not len(touch): continue
                cid = comps(o)
                for c in np.unique(cid[touch]):
                    piece = v[cid == c]; lo, hi = V(piece.min(0)), V(piece.max(0)); size = hi - lo
                    if not (0.3 <= size.z <= 1.2) or size.y > size.z or size.x > size.z * 1.4: continue
                    if best is None or size.z > best[0]: best = (size.z, lo, hi)
            if best:
                _, lo, hi = best
                wheels.append({"center": (lo + hi) / 2, "radius": (hi.z - lo.z) / 2, "width": hi.y - lo.y,
                               "side": sy, "axle": sx, "floor": corner_floor})
            else:
                # A tire fused to the body (no separate piece): place it at the
                # contact patch, with the manifest's radius (wheel_r) or a typical one.
                pts = np.vstack([v[(v[:, 2] <= corner_floor + 0.03) & (v[:, 0] * sx > 0.4) & (v[:, 1] * sy > 0.2)]
                                 for v in verts.values()])
                if len(pts):
                    r = float(opt.get("wheel_r", 0.36)); cx, cy = float(np.median(pts[:, 0])), float(np.median(pts[:, 1]))
                    wheels.append({"center": V((cx, cy, corner_floor + r)), "radius": r, "width": 0.26,
                                   "side": sy, "axle": sx, "floor": corner_floor, "guessed": True})
    # Cars are symmetric: per axle, keep the more plausible side (its center
    # sits one radius above the floor) and mirror it to the other.
    def badness(w):
        return abs(w["center"].z - (w["floor"] + w["radius"])) + (0.5 if w.get("guessed") else 0) + (0 if 0.26 <= w["radius"] <= 0.5 else 1)
    fixed = []
    for sx in (1, -1):
        pair = [w for w in wheels if w["axle"] == sx]
        if not pair: continue
        good = min(pair, key=badness)
        for sy in (1, -1):
            c = good["center"].copy(); c.y = abs(c.y) * sy
            fixed.append(dict(good, center=c, side=sy))
    # Front and rear wheels are close to the same size; an axle whose pick
    # is >20% bigger caught something else (a fender, a mud flap) — it takes
    # the other axle's radius, sitting on its own floor.
    axles = {w["axle"]: w["radius"] for w in fixed}
    if len(axles) == 2:
        small = min(axles.values())
        for w in fixed:
            if w["radius"] > small * 1.2:
                w["radius"] = small
                w["center"] = w["center"].copy(); w["center"].z = w["floor"] + small
    # Front and rear tracks are nearly equal; an axle that picked an inboard
    # piece (hidden in the body) takes the other axle's wider track.
    if len({w["axle"] for w in fixed}) == 2:
        track = max(abs(w["center"].y) for w in fixed)
        for w in fixed:
            if abs(w["center"].y) < track - 0.08:
                w["center"] = w["center"].copy(); w["center"].y = track * w["side"]
    wheels = fixed
    # wheelfix=front_x,rear_x,y,z,r: placed by hand, for a model detection gets wrong.
    if opt.get("wheelfix"):
        fx, rx, y, z, r = (float(t) for t in opt["wheelfix"].split(","))
        wheels = [{"center": V((x, sy * y, z)), "radius": r, "width": 0.26, "side": sy, "axle": 1 if x > 0 else -1}
                  for x in (fx, rx) for sy in (1, -1)]
    if len(wheels) != 4:
        print("WHEELS_NOT_FOUND", len(wheels)); sys.exit(1)
    print("WHEELS", [(tuple(round(v, 2) for v in w["center"]), round(w["radius"], 3)) for w in wheels])
    # The car: its wheels invisible, everything else a holdout.
    invisible = bpy.data.materials.new("WheelGone"); invisible.use_nodes = True
    nt = invisible.node_tree; nt.nodes.clear()
    nt.links.new(nt.nodes.new("ShaderNodeBsdfTransparent").outputs[0], nt.nodes.new("ShaderNodeOutputMaterial").inputs["Surface"])
    invisible.surface_render_method = "DITHERED"
    hold = bpy.data.materials.new("CarHoldout"); hold.use_nodes = True
    nt = hold.node_tree; nt.nodes.clear()
    nt.links.new(nt.nodes.new("ShaderNodeHoldout").outputs[0], nt.nodes.new("ShaderNodeOutputMaterial").inputs["Surface"])
    # Every connected piece that sits inside a wheel's volume (tire, rim,
    # brake, caliper) goes invisible — even when it shares a mesh with the
    # body; everything else (fenders, bumpers) stays a holdout so it still
    # covers the new wheel where it should.
    def inside(lo, hi):
        for w in wheels:
            c, r, half = w["center"], w["radius"] * 1.15, w["width"] / 2 + 0.3
            if (lo[0] >= c.x - r and hi[0] <= c.x + r and lo[2] >= c.z - r and hi[2] <= c.z + r
                    and lo[1] >= c.y - half and hi[1] <= c.y + half):
                return True
        return False
    white = bpy.data.materials.new("WheelWhite"); white.use_nodes = True
    nt = white.node_tree; nt.nodes.clear()
    em = nt.nodes.new("ShaderNodeEmission"); em.inputs["Color"].default_value = (1, 1, 1, 1)
    nt.links.new(em.outputs[0], nt.nodes.new("ShaderNodeOutputMaterial").inputs["Surface"])
    for o in meshes:
        for slot in o.material_slots: slot.link = "DATA"
        o.data = o.data.copy()
        # stock: a mask — the car's own wheels flat white, the body a holdout
        # (publish.py takes the frame's own pixels through it). Rendering the
        # wheels with their own materials instead leaked: some models link
        # materials per object, so the appended holdout slot didn't take.
        o.data.materials.clear(); o.data.materials.append(hold)
        o.data.materials.append(white if WHEEL_MODE == "stock" else invisible)
        v = verts[o.name]
        if not len(v): continue
        lo, hi = v.min(0), v.max(0)
        gone_vert = np.zeros(len(v), dtype=bool)
        if inside(lo, hi):
            gone_vert[:] = True
        elif any(lo[2] < w["center"].z + w["radius"] and abs((lo[0] + hi[0]) / 2) < 99 for w in wheels):
            cid = comps(o)
            for c in np.unique(cid):
                piece = v[cid == c]
                if inside(piece.min(0), piece.max(0)): gone_vert[cid == c] = True
        pv = np.empty(len(o.data.polygons), dtype=np.int32)
        o.data.polygons.foreach_get("loop_start", pv)
        loops = np.empty(len(o.data.loops), dtype=np.int32); o.data.loops.foreach_get("vertex_index", loops)
        wheel_poly = gone_vert[loops[pv]] if len(pv) else np.zeros(0, dtype=bool)
        idx = wheel_poly.astype(np.int32)
        o.data.polygons.foreach_set("material_index", idx)
if WHEEL_MODE == "wheelpack":
    # The pack wheel, in its own frame: axle = its thinnest extent, outward
    # = away from where its non-tire mass (barrel, brake) sits.
    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=opt["wheelpack"])
    new = [o for o in bpy.context.scene.objects if o not in before]
    new_names = [o.name for o in new]
    node = bpy.data.objects[opt["wheelnode"]]
    keep = set(node.children_recursive) | {node}
    for o in new:
        if o not in keep and o.type == "MESH": bpy.data.objects.remove(o, do_unlink=True)
    parts = [o for o in node.children_recursive if o.type == "MESH"] + ([node] if node.type == "MESH" else [])
    # The pack may hold its wheel at any angle. The axle is the direction the
    # tire's vertices vary least along (the smallest principal axis, by power
    # iteration on trace·I − covariance); the radius is the farthest tire
    # vertex from it.
    tire_pts = [o.matrix_world @ v.co for o in parts
                for p in o.data.polygons if p.material_index < len(o.material_slots)
                and is_tire(o.material_slots[p.material_index].material) for v in [o.data.vertices[i] for i in p.vertices]]
    if not tire_pts:
        tire_pts = [o.matrix_world @ v.co for o in parts for v in o.data.vertices]
    wcenter = sum(tire_pts, V()) / len(tire_pts)
    cov = Matrix(((0.0,) * 3,) * 3)
    for q in tire_pts:
        d = q - wcenter
        for i in range(3):
            for j in range(3): cov[i][j] += d[i] * d[j]
    tr = cov[0][0] + cov[1][1] + cov[2][2]
    m = Matrix.Identity(3) * tr - cov
    axis_dir = V((0.3, 0.5, 0.8)).normalized()
    for _ in range(60): axis_dir = (m @ axis_dir).normalized()
    # Outer radius of the whole wheel (a low-profile tire can sit inside a
    # bigger rim lip), so nothing ends up bigger than the car's own tire.
    all_pts = [o.matrix_world @ v.co for o in parts for v in o.data.vertices]
    wradius = max(((q - wcenter) - axis_dir * (q - wcenter).dot(axis_dir)).length for q in all_pts)
    mass = [o.matrix_world @ p.center for o in parts for p in o.data.polygons
            if not is_tire(o.material_slots[p.material_index].material if p.material_index < len(o.material_slots) else None)]
    inward = sum(((c - wcenter).dot(axis_dir) for c in mass), 0.0) / max(len(mass), 1)
    # The barrel and brake sit inside; spokes at the outer face. wheelout=-1
    # flips it for a pack where that guess is wrong.
    out_sign = (-1 if inward > 0 else 1) * int(opt.get("wheelout", 1))
    axis = "pca"
    # Bake the kept parts into one mesh in the wheel's own unit frame:
    # center at the origin, outward along +Y, radius 1.
    for o in parts:
        o.data = o.data.copy(); o.data.transform(o.matrix_world)
        o.parent = None; o.matrix_world = Matrix.Identity(4)
    bpy.ops.object.select_all(action="DESELECT")
    for o in parts: o.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    wheel = bpy.context.view_layer.objects.active
    for name in new_names:
        o = bpy.data.objects.get(name)
        if o is not None and o is not wheel and o.type != "MESH":
            bpy.data.objects.remove(o, do_unlink=True)
    axis_vec = axis_dir * out_sign
    wheel.data.transform(Matrix.Translation(-wcenter))
    wheel.data.transform(axis_vec.rotation_difference(V((0, 1, 0))).to_matrix().to_4x4())
    wheel.data.transform(Matrix.Scale(1 / wradius, 4))
    # Width along the axle in the unit frame, to match the car's own tire
    # width: a deep-dish wheel scaled only by height pokes out of the body.
    ys = [v.co.y for v in wheel.data.vertices]
    unit_width = max(max(ys) - min(ys), 1e-3)
    for i, w in enumerate(wheels):
        inst = wheel if i == 0 else wheel.copy()
        if i: bpy.context.scene.collection.objects.link(inst)
        inst.parent = turn
        inst.location = w["center"]
        # glTF imports in quaternion mode, where rotation_euler is ignored.
        inst.rotation_mode = "XYZ"
        inst.rotation_euler = (0, 0, 0 if w["side"] > 0 else math.pi)
        width = min(max(w["width"], w["radius"] * 0.45), w["radius"] * 0.9)
        inst.scale = (w["radius"], width / unit_width, w["radius"])
    turn.rotation_euler.z = yaw  # measured at 0; the render (or the frame loop) turns it
    print("WHEEL_PACK axis", axis, "out", out_sign, "radius", round(wradius, 3))

if WHEEL_MODE:
    turn.rotation_euler.z = yaw  # wheels were measured at 0

# extra=<id>: a roof/body extras add-on layer — the whole car a holdout and
# the extra built here, fitted to this car's roof or trunk (measured with
# rays down onto the body), so it needs no third-party model. Ids: rack
# (crossbars), box (cargo box on crossbars), lightbar (LED bar over the
# windshield), spoiler (trunk wing). extra=measure prints the measurements
# (EXTRAS line) and which extras fit this body, without rendering.
if "extra" in opt:
    exec(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "extras_scene.py")).read())

scene = bpy.context.scene
# World: Blender's bundled studio HDRI for reflections, kept out of the shot.
world = bpy.data.worlds.new("Studio"); scene.world = world
world.use_nodes = True
nt = world.node_tree; nt.nodes.clear()
env = nt.nodes.new("ShaderNodeTexEnvironment")
env.image = bpy.data.images.load(glob.glob("/Applications/Blender.app/Contents/Resources/*/datafiles/studiolights/world/studio.exr")[0])
bg = nt.nodes.new("ShaderNodeBackground"); bg.inputs["Strength"].default_value = 0.7
outn = nt.nodes.new("ShaderNodeOutputWorld")
nt.links.new(env.outputs["Color"], bg.inputs["Color"]); nt.links.new(bg.outputs["Background"], outn.inputs["Surface"])

def area_light(name, loc, energy, size):
    l = bpy.data.lights.new(name, "AREA"); l.energy = energy; l.size = size
    o = bpy.data.objects.new(name, l); o.location = loc
    scene.collection.objects.link(o)
    d = o.constraints.new("TRACK_TO"); d.target = turn
    return o

def softbox(name, loc, rot, size, strength):
    # An emissive panel the camera can't see but the paint reflects, like a
    # photo studio's softboxes: long clean highlights instead of a blurry HDRI.
    bpy.ops.mesh.primitive_plane_add(size=1, location=loc, rotation=rot)
    o = bpy.context.active_object; o.name = name; o.scale = (*size, 1)
    m = bpy.data.materials.new(name); m.use_nodes = True
    nt2 = m.node_tree; nt2.nodes.clear()
    em = nt2.nodes.new("ShaderNodeEmission"); em.inputs["Strength"].default_value = strength
    o2 = nt2.nodes.new("ShaderNodeOutputMaterial"); nt2.links.new(em.outputs[0], o2.inputs["Surface"])
    o.data.materials.append(m)
    o.visible_camera = False; o.visible_shadow = False
    return o

# Car-photography studio: an overhead softbox (long highlight down the hood
# and roof), a wide panel above the camera (what the side facing us
# reflects — without it dark paint goes flat black), and two tall side strips
# (the vertical streaks that show a body's shape). The world HDRI is turned
# down so the softboxes, not its blur, make the reflections.
bg.inputs["Strength"].default_value = float(opt.get("world", 0.5))
softbox("Overhead", (0, 0, 7), (0, 0, 0), (7, 3.2), 9)
softbox("Front", (0, -11, 3.6), (math.radians(80), 0, 0), (9, 2.2), 3.5)
softbox("StripL", (-6, -6, 2.4), (math.radians(90), 0, math.radians(-45)), (1.4, 4.5), 6)
softbox("StripR", (7, 1.5, 2.4), (math.radians(90), 0, math.radians(95)), (1.4, 4.5), 6)
# Area lights shape the body but cast no shadows, so a Cycles shadow catcher
# gets only a soft contact shadow, not a long one that would widen the crop.
for l in (area_light("Key", (5, -7, 5), 450, 5), area_light("Rim", (-5, 7, 4), 400, 6)):
    l.data.use_shadow = False
if engine == "CYCLES":
    bpy.ops.mesh.primitive_plane_add(size=60, location=(0, 0, 0))
    bpy.context.active_object.is_shadow_catcher = True
else:
    # EEVEE reflects off-screen objects (the softboxes, which the camera
    # can't see) only through a light probe; without one the paint reflects
    # just the dim world. No floor: EEVEE has no shadow catcher, and the
    # app draws the contact shadow and floor reflection itself.
    bpy.ops.object.lightprobe_add(type="SPHERE", location=(0, 0, 1.2))
    bpy.context.active_object.data.influence_distance = 8

cam_data = bpy.data.cameras.new("Cam"); cam_data.lens = 85
cam = bpy.data.objects.new("Cam", cam_data); scene.collection.objects.link(cam)
cam.location = (0, -15.5, 3.2)
tgt = bpy.data.objects.new("Target", None); tgt.location = (0, 0, 0.62); scene.collection.objects.link(tgt)
c = cam.constraints.new("TRACK_TO"); c.target = tgt
scene.camera = cam

scene.render.engine = engine
if engine == "CYCLES":
    scene.cycles.device = "GPU"
    prefs = bpy.context.preferences.addons["cycles"].preferences
    prefs.compute_device_type = "METAL"; prefs.get_devices()
    for d in prefs.devices: d.use = True
    scene.cycles.samples = int(opt.get("samples", 96))
    scene.cycles.use_denoising = True
else:
    scene.eevee.taa_render_samples = int(opt.get("samples", 64))
    if hasattr(scene.eevee, "use_raytracing"): scene.eevee.use_raytracing = True
scene.render.film_transparent = True
w, h = (int(v) for v in opt.get("res", "1600x900").split("x"))
scene.render.resolution_x, scene.render.resolution_y = w, h
scene.view_settings.view_transform = "AgX"; scene.view_settings.look = "AgX - Punchy"
# EEVEE has less bounce light than Cycles; lift it so white paint isn't gray.
if engine != "CYCLES": scene.view_settings.exposure = float(opt.get("exposure", 0.45))
if opt.get("matid") == "1" or "mask" in opt or opt.get("wheelstock") == "1": scene.view_settings.view_transform = "Standard"; scene.view_settings.look = "None"; scene.view_settings.exposure = 0
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGBA"

def set_paint(rgb):
    for b in paint_bsdfs: b.inputs["Base Color"].default_value = (*rgb, 1)

# plates=1 frames=N: no rendering — writes <out> (JSON): where the license
# plates land in each turntable frame, so the app can draw the owner's own
# plate there. A plate is the model's own plate geometry when it has a plate
# material (`platemat=a|b`, else found by name), split into front and rear;
# without one, a standard US plate (12x6 in) placed where a ray at plate
# height (`plate_rear_z`/`plate_front_z`, meters from the ground) hits the
# tail (and the nose only when `plate_front_z` is given). Same scene, camera
# and turntable as the renders, so it lines up frame for frame.
def write_plates():
    import json, re
    from bpy_extras.object_utils import world_to_camera_view
    turn.rotation_euler.z = 0
    bpy.context.view_layer.update()
    deps = bpy.context.evaluated_depsgraph_get()
    car_objs = set(meshes)
    lo, hi = bbox(meshes)
    up = Vector((0, 0, 1))
    pattern = re.compile(r"plate|licen|nomer|regist", re.I)
    wanted = set(opt["platemat"].split("|")) if opt.get("platemat") else None

    def is_plate(m):
        return m and (m.name in wanted if wanted is not None else bool(pattern.search(m.name)))

    def rect(center, normal, w, h):
        r = up.cross(normal).normalized()  # the viewer's right, looking at the plate
        u = normal.cross(r).normalized()
        return [center - r * w / 2 + u * h / 2, center + r * w / 2 + u * h / 2,
                center + r * w / 2 - u * h / 2, center - r * w / 2 - u * h / 2], normal

    plates = {}
    # The model's own plates. Front is -X, rear +X (frame 0's yaw shows the
    # front three-quarter, after `flip`).
    faces = {"front": [], "rear": []}
    for o in meshes:
        mw = o.matrix_world; nm = mw.to_3x3()
        for p in o.data.polygons:
            if p.material_index < len(o.material_slots) and is_plate(o.material_slots[p.material_index].material):
                c = mw @ p.center
                verts = [mw @ o.data.vertices[i].co for i in p.vertices]
                faces["rear" if c.x > 0 else "front"].append((c, (nm @ p.normal).normalized(), p.area, verts))
    for side, fs in faces.items():
        if not fs: continue
        side_sign = 1 if side == "rear" else -1
        # Outward normal: the average of the faces pointing out of this end.
        outward = [n * a for _, n, a, _ in fs if n.x * side_sign > 0.3]
        normal = (sum(outward, Vector()) if outward else Vector((side_sign, 0, 0))).normalized()
        vs = [v for *_, verts in fs for v in verts]
        ys = [v.y for v in vs]; zs = [v.z for v in vs]
        w = max(max(ys) - min(ys), 0.2); h = max(max(zs) - min(zs), 0.08)
        center = Vector(((max(v.x for v in vs) if side == "rear" else min(v.x for v in vs)),
                         (max(ys) + min(ys)) / 2, (max(zs) + min(zs)) / 2))
        plates[side] = rect(center + normal * 0.004, normal, w, h) + ("model",)
    # Fallback: a standard US plate where a ray at plate height hits the body.
    for side, key, default in (("rear", "plate_rear_z", 0.75), ("front", "plate_front_z", None)):
        if side in plates or (key not in opt and default is None): continue
        z = float(opt.get(key, default)); s = 1 if side == "rear" else -1
        origin = Vector((s * (abs(hi.x if s > 0 else lo.x) + 2), 0, z))
        hit, loc, nrm, _, obj, _ = bpy.context.scene.ray_cast(deps, origin, Vector((-s, 0, 0)))
        if hit and obj in car_objs:
            normal = Vector((nrm.x, 0, nrm.z)).normalized() if abs(nrm.x) > 0.3 else Vector((s, 0, 0))
            if normal.x * s < 0: normal = -normal  # some models' normals point inward
            w = float(opt.get(f"plate_{side}_w", 0.305))
            plates[side] = rect(loc + normal * 0.004, normal, w, w / 2 if w <= 0.33 else 0.115) + ("ray",)

    def visible(point, cam_pos):
        # First thing a ray from the camera hits, skipping the softboxes
        # (camera-invisible, but still geometry).
        d = point - cam_pos; dist = d.length; d.normalize(); start = cam_pos.copy()
        for _ in range(6):
            hit, loc, _, _, obj, _ = bpy.context.scene.ray_cast(deps, start, d)
            if not hit: return True
            # plate_tol: how much geometry may sit in front of the plate (a
            # model with a doubled hatch shell needs more than the default).
            if obj in car_objs: return (loc - cam_pos).length > dist - float(opt.get("plate_tol", 0.05))
            start = loc + d * 0.01
        return True

    frames = int(opt.get("frames", 36))
    res = (scene.render.resolution_x, scene.render.resolution_y)
    out_frames = []
    for f in range(frames):
        turn.rotation_euler.z = yaw + 2 * math.pi * f / frames
        bpy.context.view_layer.update()
        deps = bpy.context.evaluated_depsgraph_get()
        m = turn.matrix_world; m3 = m.to_3x3()
        cam_pos = cam.matrix_world.translation
        entry = {}
        for side, (corners, normal, source) in plates.items():
            world = [m @ c for c in corners]
            center = sum(world, Vector()) / 4
            facing = (m3 @ normal).normalized().dot((cam_pos - center).normalized())
            if facing < 0.12 or not visible(center, cam_pos): continue
            quad = []
            for p in world:
                v = world_to_camera_view(scene, cam, p)
                quad.append([round(v.x * res[0], 1), round((1 - v.y) * res[1], 1)])
            entry[side] = {"quad": quad, "facing": round(facing, 3)}
        out_frames.append(entry)
    sizes = {s: {"w": round((c[1] - c[0]).length, 3), "h": round((c[0] - c[3]).length, 3), "source": src}
             for s, (c, _, src) in plates.items()}
    result = {"res": list(res), "plates": sizes, "frames": out_frames}
    if opt.get("zgrid") == "1":
        # Straight-behind view (yaw -90): where each height lands on screen,
        # for choosing plate_rear_z by eye against a render at the same yaw.
        turn.rotation_euler.z = math.radians(-90); bpy.context.view_layer.update()
        m = turn.matrix_world
        result["zgrid"] = {f"{z / 100:.2f}": round((1 - world_to_camera_view(scene, cam, m @ Vector((hi.x, 0, z / 100))).y) * res[1], 1)
                           for z in range(20, 141, 10)}
    json.dump(result, open(out, "w"))
    print("PLATES", sizes)

# colors=key:r,g,b;key:r,g,b (linear RGB)  frames=N  -> out is a directory: <out>/<key>/<frame:02d>.png
import time
if opt.get("plates") == "1":
    write_plates()
elif "colors" in opt:
    colors = [(k, tuple(float(c) for c in v.split(","))) for k, v in (e.split(":") for e in opt["colors"].split(";"))]
    frames = int(opt.get("frames", 36))
    for key, rgb in colors:
        set_paint(rgb)
        for f in range(frames):
            t0 = time.time()
            turn.rotation_euler.z = yaw + 2 * math.pi * f / frames
            scene.render.filepath = os.path.join(out, key, f"{f:02d}.png")
            bpy.ops.render.render(write_still=True)
            print("FRAME", key, f, round(time.time() - t0, 2))
else:
    scene.render.filepath = out
    bpy.ops.render.render(write_still=True)
    print("RENDERED", out)
