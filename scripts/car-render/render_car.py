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
if opt.get("matid") == "1" or "mask" in opt: scene.view_settings.view_transform = "Standard"; scene.view_settings.look = "None"; scene.view_settings.exposure = 0
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
            w = float(opt.get(f"plate_{side}_w", 0.305))
            plates[side] = rect(loc + normal * 0.004, normal, w, w / 2 if w <= 0.33 else 0.115) + ("ray",)

    def visible(point, cam_pos):
        # First thing a ray from the camera hits, skipping the softboxes
        # (camera-invisible, but still geometry).
        d = point - cam_pos; dist = d.length; d.normalize(); start = cam_pos.copy()
        for _ in range(6):
            hit, loc, _, _, obj, _ = bpy.context.scene.ray_cast(deps, start, d)
            if not hit: return True
            if obj in car_objs: return (loc - cam_pos).length > dist - 0.05
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
