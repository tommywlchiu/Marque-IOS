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
if opt.get("matid") == "1": scene.view_settings.view_transform = "Standard"; scene.view_settings.look = "None"; scene.view_settings.exposure = 0
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGBA"

def set_paint(rgb):
    for b in paint_bsdfs: b.inputs["Base Color"].default_value = (*rgb, 1)

# colors=key:r,g,b;key:r,g,b (linear RGB)  frames=N  -> out is a directory: <out>/<key>/<frame:02d>.png
import time
if "colors" in opt:
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
