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
if gz is not None and gz < (lo.z + hi.z) / 2:
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

# Soft key + rim area lights
def area_light(name, loc, energy, size):
    l = bpy.data.lights.new(name, "AREA"); l.energy = energy; l.size = size
    o = bpy.data.objects.new(name, l); o.location = loc
    scene.collection.objects.link(o)
    d = o.constraints.new("TRACK_TO"); d.target = turn
    return o
area_light("Key", (4, -6, 6), 700, 6)
area_light("Rim", (-6, 5, 4), 500, 6)
area_light("Top", (0, 0, 8), 500, 8)

# Shadow-catcher floor so the car sits on the ground over a transparent background
# (Cycles only — EEVEE has no shadow catcher and would render the floor
# opaque; the app draws its own contact shadow under the car anyway.)
if engine == "CYCLES":
    bpy.ops.mesh.primitive_plane_add(size=40, location=(0, 0, 0))
    bpy.context.active_object.is_shadow_catcher = True

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
