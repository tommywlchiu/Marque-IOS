import bpy, sys
argv = sys.argv[sys.argv.index("--") + 1:]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=argv[0])
for m in bpy.data.materials:
    b = next((n for n in (m.node_tree.nodes if m.node_tree else []) if n.type == "BSDF_PRINCIPLED"), None)
    if not b: print("MAT", m.name, "no-bsdf"); continue
    t = b.inputs["Transmission Weight"].default_value
    a = b.inputs["Alpha"].default_value
    c = tuple(round(x, 2) for x in b.inputs["Base Color"].default_value[:3])
    tex = bool(b.inputs["Base Color"].links)
    print("MAT", m.name, "trans", round(t, 2), "alpha", round(a, 2), "color", c, "tex", tex, "blend", m.surface_render_method)
