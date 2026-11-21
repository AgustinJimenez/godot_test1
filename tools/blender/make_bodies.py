"""Make the two base bodies (female, male) from MPFB, with blend shapes and eye landmarks.

Run headless (MPFB must be installed, see docs/blender_workflow.md):
  blender -b --factory-startup --python tools/blender/make_bodies.py -- <output folder>
Writes {female,male}_body.glb and {female,male}_landmarks.json into the folder.
"""
import json
import bpy, sys, addon_utils, importlib, bmesh
out = sys.argv[sys.argv.index("--")+1]
e = bpy.context.preferences.addons.new(); e.module = "bl_ext.blender_org.mpfb"
addon_utils.enable("bl_ext.blender_org.mpfb")
HS = importlib.import_module("bl_ext.blender_org.mpfb.services.humanservice").HumanService
BODY_VERTS = 13380   # MakeHuman base: body verts first, helper geometry after
RACE = {"asian":0.0,"caucasian":1.0,"african":0.0}

def positions(o):
    # shape keys mixed: read through the key-block mix via evaluated object with modifiers disabled
    for md in o.modifiers: md.show_viewport = False
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    me = o.evaluated_get(dg).to_mesh()
    pts = [v.co.copy() for v in me.vertices]
    for md in o.modifiers: md.show_viewport = True
    return pts

for name, g in (("female",0.0),("male",1.0)):
    # reset scene objects
    for ob in list(bpy.data.objects): bpy.data.objects.remove(ob, do_unlink=True)
    base = HS.create_human(macro_detail_dict={"gender":g,"age":0.5,"muscle":0.5,"weight":0.5,"proportions":0.5,"height":0.5,"cupsize":0.5,"firmness":0.5,"race":RACE})
    base.name = f"{name}_body"
    base_pts = positions(base)
    print(name, "verts", len(base_pts), "dims", tuple(round(d,2) for d in base.dimensions))
    variants = {}
    for key,(h,w,mu) in {"height_short":(0.0,0.5,0.5),"height_tall":(1.0,0.5,0.5),"weight_light":(0.5,0.0,0.5),"weight_heavy":(0.5,1.0,0.5),"muscle_low":(0.5,0.5,0.0),"muscle_high":(0.5,0.5,1.0)}.items():
        tmp = HS.create_human(macro_detail_dict={"gender":g,"age":0.5,"muscle":mu,"weight":w,"proportions":0.5,"height":h,"cupsize":0.5,"firmness":0.5,"race":RACE})
        variants[key] = positions(tmp)
        bpy.data.objects.remove(tmp, do_unlink=True)
    # Landmarks for things that sit on the body (eyes now; brows, lashes, hair later): the centre of a few helper
    # vertex groups in the base shape and in every variant, in Blender space, saved next to the body as JSON.
    GROUPS = {"eye_l": "joint-l-eye", "eye_r": "joint-r-eye",
              "eye_l_target": "joint-l-eye-target", "eye_r_target": "joint-r-eye-target"}
    ids = {}
    for key, group in GROUPS.items():
        gi = base.vertex_groups[group].index
        ids[key] = [v.index for v in base.data.vertices if any(vg.group == gi for vg in v.groups)]
    def centres(pts):
        return {key: [sum(pts[i][a] for i in members) / len(members) for a in range(3)] for key, members in ids.items()}
    landmarks = {"basis": centres(base_pts)}
    for key, pts in variants.items():
        landmarks[key] = centres(pts)
    helper_eye = base.vertex_groups["helper-l-eye"].index
    eye_ids = [v.index for v in base.data.vertices if any(vg.group == helper_eye for vg in v.groups)]
    centre_l = landmarks["basis"]["eye_l"]
    landmarks["eye_radius"] = sum(((base_pts[i][0]-centre_l[0])**2 + (base_pts[i][1]-centre_l[1])**2 + (base_pts[i][2]-centre_l[2])**2) ** 0.5 for i in eye_ids) / len(eye_ids)
    # eyelid helper vertices (basis shape): where the lashes start. -1 = lower row, -2 = upper row of each eye.
    for side in ("l", "r"):
        for row in ("1", "2"):
            gi = base.vertex_groups[f"helper-{side}-eyelashes-{row}"].index
            members = [v.index for v in base.data.vertices if any(vg.group == gi for vg in v.groups)]
            landmarks[f"lash_{side}_{row}"] = [list(base_pts[i]) for i in members]
    with open(f"{out}/{name}_landmarks.json", "w") as handle:
        json.dump(landmarks, handle, indent=1)
    print(name, "landmarks saved, helper eye radius", round(landmarks["eye_radius"], 4))
    # bake the base geometry as the plain mesh, drop MPFB's own shape keys/targets and helper geometry
    me = base.data
    if me.shape_keys:
        base.shape_key_clear()
    for i,v in enumerate(me.vertices): v.co = base_pts[i]
    base.shape_key_add(name="Basis", from_mix=False)
    for key,pts in variants.items():
        sk = base.shape_key_add(name=key, from_mix=False)
        for i,p in enumerate(pts): sk.data[i].co = p
        sk.value = 0.0
    # drop helper verts (keeps shape keys through bmesh)
    for md in list(base.modifiers): base.modifiers.remove(md)
    bpy.context.view_layer.objects.active = base
    bm = bmesh.new(); bm.from_mesh(me)
    bm.verts.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.index >= BODY_VERTS], context="VERTS")
    bm.to_mesh(me); bm.free()
    for vg in list(base.vertex_groups):
        if vg.name.startswith(("helper","joint")): base.vertex_groups.remove(vg)
    bpy.ops.object.select_all(action="DESELECT"); base.select_set(True)
    print(name, "final verts", len(me.vertices), "keys", [k.name for k in me.shape_keys.key_blocks])
    for k in me.shape_keys.key_blocks[1:]:
        d = max((k.data[i].co - me.shape_keys.reference_key.data[i].co).length for i in range(0,len(me.vertices),50))
        print("  ", k.name, "max delta ~", round(d,3))
    bpy.ops.export_scene.gltf(filepath=f"{out}/{name}_body.glb", use_selection=True, export_format="GLB", export_morph=True, export_apply=False, export_yup=True)
print("DONE")
