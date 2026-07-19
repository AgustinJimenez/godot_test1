class_name CharacterEditorAttachmentSlot
extends RefCounted

## One independently editable object attached to a character skeleton bone.

var display_name := "Attachment"
var role := &"prop"
var object_path := ""
var bone_name := &"RightHand"
var attachment_node: BoneAttachment3D
var object_node: Node3D
var visible := true


func serialize() -> Dictionary:
	return {
		"name": display_name,
		"role": String(role),
		"object_scene": object_path,
		"attachment_bone": String(bone_name),
		"position": [
			object_node.position.x,
			object_node.position.y,
			object_node.position.z,
		],
		"rotation_degrees": [
			object_node.rotation_degrees.x,
			object_node.rotation_degrees.y,
			object_node.rotation_degrees.z,
		],
		"scale": object_node.scale.x,
		"visible": visible,
	}
