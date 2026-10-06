# blender -b -P inspect_car.py -- <in.glb> <out.json>: material surface areas (world units) + name hints
import bpy, sys, json
argv = sys.argv[sys.argv.index("--") + 1:]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=argv[0])
area = {}
for o in bpy.context.scene.objects:
    if o.type != "MESH": continue
    s = sum(o.matrix_world.to_scale()) / 3
    for p in o.data.polygons:
        if p.material_index < len(o.material_slots):
            m = o.material_slots[p.material_index].material
            if m: area[m.name] = area.get(m.name, 0) + p.area * s * s
info = {}
for name, a in area.items():
    m = bpy.data.materials[name]
    b = next((n for n in (m.node_tree.nodes if m.node_tree else []) if n.type == "BSDF_PRINCIPLED"), None)
    info[name] = {"area": a, "alpha": b.inputs["Alpha"].default_value if b else 1,
                  "textured": bool(b and b.inputs["Base Color"].links),
                  "color": list(b.inputs["Base Color"].default_value[:3]) if b else None}
json.dump(info, open(argv[1], "w"))
