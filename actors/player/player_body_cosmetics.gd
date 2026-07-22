class_name PlayerBodyCosmetics
extends RefCounted

## Character Creator hair/skin-tone data + application logic for the two
## Universal Base Characters bodies - extracted from player_body.gd purely
## to keep that file under the lint line-count ceiling. Duplicated from
## ui/character_creator.gd's own BODIES/HAIRSTYLES constants rather than
## shared, matching this project's established "duplicated on purpose"
## convention for anything gameplay-critical (see HumanoidRetargeter's own
## doc comment).

const FEMALE_DIR := "res://assets/models/imported_characters/402453fc-7d0e-4139-9cb0-f2dbe6276161/"
const MALE_DIR := "res://assets/models/imported_characters/8bcc06df-6c6e-42f0-b2c1-5f37ccf2b28b/"
const HAIR_DIR := "res://assets/models/universal_base_characters/hairstyles/"

const BODY_DATA: Dictionary = {
	"custom_superhero_female_fullbody": {
		"dir": FEMALE_DIR,
		"mesh_name": "Superhero_Female",
		"base_texture": FEMALE_DIR + "T_Superhero_Female_Light_BaseColor.png",
	},
	"custom_superhero_male_fullbody": {
		"dir": MALE_DIR,
		"mesh_name": "SuperHero_Male",
		"base_texture": MALE_DIR + "T_Superhero_Male_Light_BaseColor.png",
	},
}

## The pack's only shipped eye art is T_Eye_Brown.png, with no other iris colors - real eye/skin
## shader customization is a paid "Source"-tier feature of this pack, not included in what we
## imported. These variants are generated (see ui/character_creator.gd's EYE_COLORS doc comment)
## by recoloring just the iris region of that one texture, preserving its shading/highlight.
const EYE_COLORS: Dictionary = {
	"brown": "Brown",
	"blue": "Blue",
	"green": "Green",
	"gray": "Gray",
	"hazel": "Hazel",
}

## The pack's "Light"/"Dark" texture pair turned out to differ only in outfit color, not skin
## tone (confirmed by comparing the two files directly) - there's no actual light/pale skin art
## to select, so tones are approximated by tinting the one base texture above; "tan" (no tint) is
## as light as this asset pack gets, darkening from there. See ui/character_creator.gd's
## SKIN_TONES doc comment for why a multiply tint can't go lighter than the base texture.
const SKIN_TONES: Dictionary = {
	"tan": Color(1.0, 1.0, 1.0),
	"caramel": Color(0.82, 0.68, 0.56),
	"brown": Color(0.62, 0.48, 0.38),
	"deep": Color(0.42, 0.31, 0.24),
}
## The hair/beard/eyebrow meshes share a near-white base texture (unlike the skin textures) made
## for tinting - white multiplies against any tint near-losslessly, so this palette reaches real
## blonde/gray, not just progressively darker shades like SKIN_TONES above.
const HAIR_COLORS: Dictionary = {
	"black": Color(0.05, 0.045, 0.045),
	"dark_brown": Color(0.22, 0.14, 0.09),
	"brown": Color(0.4, 0.26, 0.15),
	"blonde": Color(0.82, 0.68, 0.42),
	"auburn": Color(0.45, 0.16, 0.09),
	"gray": Color(0.75, 0.75, 0.75),
}
## Hair_Buns/Hair_BuzzedFemale excluded - see ui/character_creator.gd's
## HAIRSTYLES doc comment (different scale/axis convention, not yet tuned).
const HAIR_PATHS: Dictionary = {
	"long": HAIR_DIR + "Hair_Long.gltf",
	"simple_parted": HAIR_DIR + "Hair_SimpleParted.gltf",
	"buzzed": HAIR_DIR + "Hair_Buzzed.gltf",
	"beard": HAIR_DIR + "Hair_Beard.gltf",
	"eyebrows_regular": HAIR_DIR + "Eyebrows_Regular.gltf",
	"eyebrows_female": HAIR_DIR + "Eyebrows_Female.gltf",
}

## Each hairstyle mesh is baked against one specific body's Head-bone rest position; on the other
## body it needs an extra vertical nudge - see ui/character_creator.gd's HAIR_Y_CORRECTIONS.
const HAIR_Y_CORRECTIONS: Dictionary = {
	"custom_superhero_male_fullbody": {"long": 0.05, "eyebrows_female": 0.03},
	"custom_superhero_female_fullbody":
			{"buzzed": -0.03, "simple_parted": -0.05, "eyebrows_regular": -0.04},
}


static func apply_skin_tone(character: Node3D, kind_id: String, skin_tone_id: String) -> void:
	if not BODY_DATA.has(kind_id):
		return
	var data: Dictionary = BODY_DATA[kind_id]
	var mesh_instance := character.find_child(
			String(data["mesh_name"]), true, false) as MeshInstance3D
	if mesh_instance == null:
		return
	var texture := load(String(data["base_texture"])) as Texture2D
	var tint: Color = SKIN_TONES.get(skin_tone_id, Color.WHITE)
	for i in mesh_instance.mesh.get_surface_count():
		var material := mesh_instance.get_active_material(i)
		if material is BaseMaterial3D:
			(material as BaseMaterial3D).albedo_texture = texture
			(material as BaseMaterial3D).albedo_color = tint


static func apply_eye_color(character: Node3D, kind_id: String, eye_color_id: String) -> void:
	if not BODY_DATA.has(kind_id):
		return
	var mesh_instance := character.find_child("Eyes", true, false) as MeshInstance3D
	if mesh_instance == null:
		return
	var suffix: String = EYE_COLORS.get(eye_color_id, "Brown")
	var texture := load(String(BODY_DATA[kind_id]["dir"]) + "T_Eye_" + suffix + ".png") as Texture2D
	for i in mesh_instance.mesh.get_surface_count():
		var material := mesh_instance.get_active_material(i)
		if material is BaseMaterial3D:
			(material as BaseMaterial3D).albedo_texture = texture


## Returns {"hair":, "facial_hair":, "eyebrows":} BoneAttachment3D (or null per slot) - the three
## head attachment slots are independent (a male can combine any hairstyle with Beard, etc.).
## Frees each slot's previous attachment from `existing` first; caller stores the returned
## Dictionary and passes it back in as `existing` next time (e.g. after swap_character()).
static func apply_head_attachments(
		skeleton: Skeleton3D, head_bone: StringName, kind_id: String,
		hair_id: String, facial_hair_id: String, eyebrows_id: String, hair_color_id: String,
		existing: Dictionary) -> Dictionary:
	_hide_builtin_eyebrows(skeleton)
	return {
		"hair": _apply_one(
				skeleton, head_bone, kind_id, hair_id, hair_color_id, existing.get("hair")),
		"facial_hair": _apply_one(
				skeleton, head_bone, kind_id, facial_hair_id, hair_color_id,
				existing.get("facial_hair")),
		"eyebrows": _apply_one(
				skeleton, head_bone, kind_id, eyebrows_id, hair_color_id, existing.get("eyebrows")),
	}


## The imported body ships its own permanently-visible, never-tinted "Eyebrows" sibling mesh
## (same T_Hair_1_BaseColor.png as our own attachable eyebrows) - it's what was actually showing
## through as a second, uncolored eyebrow, not the skin texture. Removing it once is the real fix.
static func _hide_builtin_eyebrows(skeleton: Skeleton3D) -> void:
	var builtin := skeleton.find_child("Eyebrows", true, false)
	if builtin != null:
		builtin.queue_free()


static func _apply_one(
		skeleton: Skeleton3D, head_bone: StringName, kind_id: String, attachment_id: String,
		hair_color_id: String, current: Variant) -> BoneAttachment3D:
	if current is BoneAttachment3D and is_instance_valid(current):
		(current as BoneAttachment3D).queue_free()
	var bone_idx := skeleton.find_bone(head_bone)
	if not BODY_DATA.has(kind_id) or bone_idx < 0:
		return null
	var path: String = HAIR_PATHS.get(attachment_id, "")
	if path.is_empty():
		return null
	var resource := load(path)
	if not resource is PackedScene:
		return null
	var instance := (resource as PackedScene).instantiate() as Node3D
	if instance == null:
		return null
	var tint: Color = HAIR_COLORS.get(hair_color_id, Color.WHITE)
	for node in instance.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		for i in mesh_instance.mesh.get_surface_count():
			var material := mesh_instance.get_active_material(i)
			if material is BaseMaterial3D:
				(material as BaseMaterial3D).albedo_color = tint
	var attachment := BoneAttachment3D.new()
	attachment.bone_name = head_bone
	skeleton.add_child(attachment)
	# The attachment mesh is baked in world-space matching the body's rest pose, not local to the
	# bone; re-expressing it in the bone's rest-relative space lets BoneAttachment3D carry it
	# correctly through animated poses too, not just cancel translation at rest.
	var correction_y: float = HAIR_Y_CORRECTIONS.get(kind_id, {}).get(attachment_id, 0.0)
	instance.transform = (skeleton.get_bone_global_rest(bone_idx).affine_inverse()
			* Transform3D(Basis.IDENTITY, Vector3(0, correction_y, 0)))
	attachment.add_child(instance)
	return attachment
