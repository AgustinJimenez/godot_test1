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
TS = importlib.import_module("bl_ext.blender_org.mpfb.services.targetservice").TargetService
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import heavy_mix   # the weight_heavy shape: max-weight macro plus fat / girth targets (shared with make_rig.py)
BODY_VERTS = 13380   # MakeHuman base: body verts first, helper geometry after
RACE = {"asian":0.0,"caucasian":1.0,"african":0.0}

# Face and age shape keys (the user's editor): each key is one end of a signed slider (decr/incr pairs become two keys). `age` is a macro (MPFB age 0.5 = 25 years, 0.1875 = 11, 1.0 = 90);
# the others load MakeHuman core targets (CC0, MPFB data/targets) at weight 1, both sides for the l-/r- pairs. Keep the list short: every key is a blend shape on the body, the eyes, the brows and the lashes.
FACE_KEYS = {
    "age_young": {"macro": {"age": 0.34}},
    "age_old": {"macro": {"age": 0.85}},
    "head_narrow": {"targets": ["head-scale-horiz-decr"]},
    "head_wide": {"targets": ["head-scale-horiz-incr"]},
    "nose_narrow": {"targets": ["nose-scale-horiz-decr"]},
    "nose_wide": {"targets": ["nose-scale-horiz-incr"]},
    "nose_short": {"targets": ["nose-scale-vert-decr"]},
    "nose_long": {"targets": ["nose-scale-vert-incr"]},
    "ears_small": {"targets": ["l-ear-scale-decr", "r-ear-scale-decr"]},
    "ears_big": {"targets": ["l-ear-scale-incr", "r-ear-scale-incr"]},
    "chin_receding": {"targets": ["chin-prominent-decr"]},
    "chin_prominent": {"targets": ["chin-prominent-incr"]},
    "cheeks_hollow": {"targets": ["l-cheek-volume-decr", "r-cheek-volume-decr"]},
    "cheeks_full": {"targets": ["l-cheek-volume-incr", "r-cheek-volume-incr"]},
    "eyes_small": {"targets": ["l-eye-scale-decr", "r-eye-scale-decr"]},
    "eyes_big": {"targets": ["l-eye-scale-incr", "r-eye-scale-incr"]},
    "lips_thin": {"targets": ["mouth-lowerlip-volume-decr", "mouth-upperlip-volume-decr"]},
    "lips_full": {"targets": ["mouth-lowerlip-volume-incr", "mouth-upperlip-volume-incr"]},
    # more of the face (2026-11-26): jaw, cheekbones, eyes, brows, mouth, nose, forehead, face length, neck
    "jaw_narrow": {"targets": ["chin-bones-decr"]},
    "jaw_wide": {"targets": ["chin-bones-incr"]},
    "chin_narrow": {"targets": ["chin-width-decr"]},
    "chin_wide": {"targets": ["chin-width-incr"]},
    "cheekbones_low": {"targets": ["l-cheek-bones-decr", "r-cheek-bones-decr"]},
    "cheekbones_high": {"targets": ["l-cheek-bones-incr", "r-cheek-bones-incr"]},
    "eyes_close": {"targets": ["l-eye-trans-in", "r-eye-trans-in"]},
    "eyes_apart": {"targets": ["l-eye-trans-out", "r-eye-trans-out"]},
    "eyes_down": {"targets": ["l-eye-trans-down", "r-eye-trans-down"]},
    "eyes_up": {"targets": ["l-eye-trans-up", "r-eye-trans-up"]},
    "brows_down": {"targets": ["eyebrows-trans-down"]},
    "brows_up": {"targets": ["eyebrows-trans-up"]},
    "brows_angle_down": {"targets": ["eyebrows-angle-down"]},
    "brows_angle_up": {"targets": ["eyebrows-angle-up"]},
    "mouth_narrow": {"targets": ["mouth-scale-horiz-decr"]},
    "mouth_wide": {"targets": ["mouth-scale-horiz-incr"]},
    "mouth_corners_down": {"targets": ["mouth-angles-down"]},
    "mouth_corners_up": {"targets": ["mouth-angles-up"]},
    "nose_hump_less": {"targets": ["nose-hump-decr"]},
    "nose_hump_more": {"targets": ["nose-hump-incr"]},
    "nose_tip_down": {"targets": ["nose-point-down"]},
    "nose_tip_up": {"targets": ["nose-point-up"]},
    "nostrils_narrow": {"targets": ["nose-flaring-decr"]},
    "nostrils_wide": {"targets": ["nose-flaring-incr"]},
    "forehead_low": {"targets": ["forehead-scale-vert-decr"]},
    "forehead_high": {"targets": ["forehead-scale-vert-incr"]},
    "face_short": {"targets": ["head-scale-vert-decr"]},
    "face_long": {"targets": ["head-scale-vert-incr"]},
    "neck_thin": {"targets": ["measure-neck-circ-decr"]},
    "neck_thick": {"targets": ["measure-neck-circ-incr"]},
    "eyes_slant_down": {"targets": ["l-eye-corner2-down", "r-eye-corner2-down"]},   # (corner2 = the outer corner)
    "eyes_slant_up": {"targets": ["l-eye-corner2-up", "r-eye-corner2-up"]},
    "eyelids_low": {"targets": ["l-eye-eyefold-down", "r-eye-eyefold-down"]},
    "eyelids_high": {"targets": ["l-eye-eyefold-up", "r-eye-eyefold-up"]},
    "eye_bags_less": {"targets": ["l-eye-bag-decr", "r-eye-bag-decr"]},
    "eye_bags_more": {"targets": ["l-eye-bag-incr", "r-eye-bag-incr"]},
    "brow_ridge_less": {"targets": ["eyebrows-trans-backward"]},
    "brow_ridge_more": {"targets": ["eyebrows-trans-forward"]},
    "eyes_shallow": {"targets": ["l-eye-push1-out", "r-eye-push1-out"]},
    "eyes_deep": {"targets": ["l-eye-push1-in", "r-eye-push1-in"]},
    # the body's proportions (same mechanism; the lab bakes them into the hair build like the face keys)
    "shoulders_narrow": {"targets": ["measure-shoulder-dist-decr"]},
    "shoulders_wide": {"targets": ["measure-shoulder-dist-incr"]},
    "waist_narrow": {"targets": ["measure-waist-circ-decr"]},
    "waist_wide": {"targets": ["measure-waist-circ-incr"]},
    "hips_narrow": {"targets": ["measure-hips-circ-decr"]},
    "hips_wide": {"targets": ["measure-hips-circ-incr"]},
    "belly_flat": {"targets": ["stomach-pregnant-decr"]},
    "belly_round": {"targets": ["stomach-pregnant-incr"]},
    "bust_small": {"macro": {"cupsize": 0.0}},
    "bust_big": {"macro": {"cupsize": 1.0}},
}

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
        macro = {"gender":g,"age":0.5,"muscle":mu,"weight":w,"proportions":0.5,"height":h,"cupsize":0.5,"firmness":0.5,"race":RACE}
        if key == "weight_heavy":
            macro.update(heavy_mix.macros_for(g))
        tmp = HS.create_human(macro_detail_dict=macro)
        if key == "weight_heavy":
            heavy_mix.load_heavy(tmp, g, TS)
        variants[key] = positions(tmp)
        bpy.data.objects.remove(tmp, do_unlink=True)
    for key, spec in FACE_KEYS.items():
        macro = {"gender":g,"age":0.5,"muscle":0.5,"weight":0.5,"proportions":0.5,"height":0.5,"cupsize":0.5,"firmness":0.5,"race":RACE}
        macro.update(spec.get("macro", {}))
        tmp = HS.create_human(macro_detail_dict=macro)
        for target in spec.get("targets", []):
            path = TS.target_full_path(target)
            assert path, "target not found: " + target
            TS.load_target(tmp, path, weight=1.0)
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
    # the helper eyeball of the MakeHuman mesh moves and scales with the eye keys (the joint vertices do not): its centre and size per shape drive our eyeballs
    helper_ids = {}
    for side in ("l", "r"):
        gi_h = base.vertex_groups[f"helper-{side}-eye"].index
        helper_ids[side] = [v.index for v in base.data.vertices if any(vg.group == gi_h for vg in v.groups)]
    def helper_info(pts):
        info = {}
        for side, members in helper_ids.items():
            c = [sum(pts[i][a] for i in members) / len(members) for a in range(3)]
            r = sum(((pts[i][0]-c[0])**2 + (pts[i][1]-c[1])**2 + (pts[i][2]-c[2])**2) ** 0.5 for i in members) / len(members)
            info[side] = (c, r)
        return info
    base_helper = helper_info(base_pts)
    def with_helper(entry, pts):
        h = helper_info(pts)
        for side in ("l", "r"):
            entry[f"eye_{side}_helper"] = h[side][0]
            entry[f"eye_{side}_scale"] = h[side][1] / base_helper[side][1]
        return entry
    landmarks = {"basis": with_helper(centres(base_pts), base_pts)}
    for key, pts in variants.items():
        landmarks[key] = with_helper(centres(pts), pts)
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
