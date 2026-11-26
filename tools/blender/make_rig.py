"""Rig the two base bodies (female, male) with MPFB's Mixamo skeleton, for every body shape.

Run headless (MPFB must be installed, see docs/blender_workflow.md):
  blender -b --factory-startup --python tools/blender/make_rig.py -- <output folder>
Writes {female,male}_rigged.glb (the body mesh of make_bodies.py, same vertex order, its six shape keys, plus the skeleton and the skin weights) and
{female,male}_rig.json into the folder.

Why a JSON: the shape keys move the vertices when a slider moves, but a skeleton has no shape keys. So the rig is fitted again to the body at every
macro extreme (the same six humans make_bodies.py bakes: height, weight, muscle) and the joint positions are stored as moves from the base rig; in
Godot the HumanRig class applies the same slider weights to the bones (and to the skin's bind poses), so the skeleton follows the body exactly.
Coordinates in the JSON are Godot's (y up, z toward the viewer): a Blender point (x, y, z) is written as (x, z, -y).
Bone names are the Mixamo ones (mixamorig:Hips ...), the skeleton the game's retargeting already knows (HumanoidRetargeter, player_body.gd).
"""
import json
import sys

import addon_utils
import bmesh
import bpy
import importlib

out = sys.argv[sys.argv.index("--") + 1]
entry = bpy.context.preferences.addons.new()
entry.module = "bl_ext.blender_org.mpfb"
addon_utils.enable("bl_ext.blender_org.mpfb")
HS = importlib.import_module("bl_ext.blender_org.mpfb.services.humanservice").HumanService
TS = importlib.import_module("bl_ext.blender_org.mpfb.services.targetservice").TargetService
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import heavy_mix   # the weight_heavy shape: max-weight macro plus fat / girth targets (the same as make_bodies.py)

BODY_VERTS = 13380  # MakeHuman base: body verts first, helper geometry after
RACE = {"asian": 0.0, "caucasian": 1.0, "african": 0.0}
RIG = "mixamo"
SHAPES = {
    "height_short": (0.0, 0.5, 0.5),
    "height_tall": (1.0, 0.5, 0.5),
    "weight_light": (0.5, 0.0, 0.5),
    "weight_heavy": (0.5, 1.0, 0.5),
    "muscle_low": (0.5, 0.5, 0.0),
    "muscle_high": (0.5, 0.5, 1.0),
}


def human(gender, height=0.5, weight=0.5, muscle=0.5):
    macros = {"gender": gender, "age": 0.5, "muscle": muscle, "weight": weight, "proportions": 0.5, "height": height,
              "cupsize": 0.5, "firmness": 0.5, "race": RACE}
    if weight >= 1.0:
        macros.update(heavy_mix.macros_for(gender))
    made = HS.create_human(macro_detail_dict=macros)
    if weight >= 1.0:
        heavy_mix.load_heavy(made, gender, TS)   # (the rig is then fitted to, and the mesh variant baked from, the heavy body with its targets)
    return made


def godot(v):
    return [v[0], v[2], -v[1]]


def bone_points(armature):
    """The head and tail of every bone in the armature's rest pose, in Godot space, in the order of the bones."""
    world = armature.matrix_world
    return {b.name: (godot(world @ b.head_local), godot(world @ b.tail_local)) for b in armature.data.bones}


def positions(obj):
    # the mesh with its shape keys mixed in but not its modifiers (an armature modifier at rest changes nothing, but be exact)
    for md in obj.modifiers:
        md.show_viewport = False
    bpy.context.view_layer.update()
    mesh = obj.evaluated_get(bpy.context.evaluated_depsgraph_get()).to_mesh()
    pts = [v.co.copy() for v in mesh.vertices]
    for md in obj.modifiers:
        md.show_viewport = True
    return pts


for name, gender in (("female", 0.0), ("male", 1.0)):
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    base = human(gender)
    base.name = f"{name}_body"
    base_rig = HS.add_builtin_rig(base, RIG)
    base_rig.name = f"{name}_skeleton"
    base_pts = positions(base)
    base_bones = bone_points(base_rig)
    order = [b.name for b in base_rig.data.bones]
    parents = {b.name: (b.parent.name if b.parent else "") for b in base_rig.data.bones}
    print(name, "bones", len(order), "armature scale", tuple(round(s, 4) for s in base_rig.matrix_world.to_scale()))
    shapes = {}
    for key, (h, w, mu) in SHAPES.items():
        tmp = human(gender, h, w, mu)
        tmp_rig = HS.add_builtin_rig(tmp, RIG)
        points = bone_points(tmp_rig)
        shapes[key] = {
            "head": [[points[n][0][i] - base_bones[n][0][i] for i in range(3)] for n in order],
            "tail": [[points[n][1][i] - base_bones[n][1][i] for i in range(3)] for n in order],
        }
        biggest = max(abs(c) for n in range(len(order)) for c in shapes[key]["head"][n])
        print("  ", key, "largest joint move", round(biggest, 3))
        bpy.data.objects.remove(tmp_rig, do_unlink=True)
        bpy.data.objects.remove(tmp, do_unlink=True)
    data = {
        "rig": RIG,
        "bones": order,
        "parents": [parents[n] for n in order],
        "head": [base_bones[n][0] for n in order],
        "tail": [base_bones[n][1] for n in order],
        "shapes": shapes,
    }
    with open(f"{out}/{name}_rig.json", "w") as handle:
        json.dump(data, handle)

    # the mesh as make_bodies.py bakes it: MPFB's own shape keys and targets dropped, the six macro variants as shape keys, helper geometry cut.
    variants = {}
    for key, (h, w, mu) in SHAPES.items():
        tmp = human(gender, h, w, mu)
        variants[key] = positions(tmp)
        bpy.data.objects.remove(tmp, do_unlink=True)
    mesh = base.data
    if mesh.shape_keys:
        base.shape_key_clear()
    for i, v in enumerate(mesh.vertices):
        v.co = base_pts[i]
    base.shape_key_add(name="Basis", from_mix=False)
    for key, pts in variants.items():
        block = base.shape_key_add(name=key, from_mix=False)
        for i, p in enumerate(pts):
            block.data[i].co = p
        block.value = 0.0
    for md in list(base.modifiers):
        if md.type != "ARMATURE":
            base.modifiers.remove(md)
    bpy.context.view_layer.objects.active = base
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bm.verts.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.index >= BODY_VERTS], context="VERTS")
    bm.to_mesh(mesh)
    bm.free()
    for vg in list(base.vertex_groups):
        if vg.name.startswith(("helper", "joint")):
            base.vertex_groups.remove(vg)
    skinned = sum(1 for v in mesh.vertices if len(v.groups) > 0)
    print(name, "final verts", len(mesh.vertices), "skinned", skinned, "groups", len(base.vertex_groups), "keys", [k.name for k in mesh.shape_keys.key_blocks])
    bpy.ops.object.select_all(action="DESELECT")
    base.select_set(True)
    base_rig.select_set(True)
    bpy.context.view_layer.objects.active = base_rig
    bpy.ops.export_scene.gltf(filepath=f"{out}/{name}_rigged.glb", use_selection=True, export_format="GLB", export_morph=True, export_skins=True,
                              export_def_bones=False, export_apply=False, export_yup=True, export_animations=False)
print("DONE")
