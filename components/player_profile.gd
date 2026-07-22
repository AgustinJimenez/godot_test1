extends Node
## Persists the player's Character Creator choice (which catalog character, hairstyle, facial
## hair, eyebrows, hair color, eye color, skin tone) across restarts - same ConfigFile/user://
## shape as graphics_settings.gd, not a general save system. PlayerBody reads this on
## _ready() to spawn as the chosen look instead of its default character_scene.

const SAVE_PATH := "user://player_profile.cfg"
const SECTION := "character"

var has_profile := false
var character_kind := ""
var hairstyle_id := ""
var facial_hair_id := "none"
var eyebrows_id := "none"
var hair_color_id := "brown"
var eye_color_id := "brown"
var skin_tone := "tan"


func _ready() -> void:
	_load()


func set_profile(
		kind: String, hair: String, facial_hair: String, eyebrows: String, hair_color: String,
		eye_color: String, tone: String) -> void:
	has_profile = true
	character_kind = kind
	hairstyle_id = hair
	facial_hair_id = facial_hair
	eyebrows_id = eyebrows
	hair_color_id = hair_color
	eye_color_id = eye_color
	skin_tone = tone
	_save()


func _load() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return
	has_profile = bool(config.get_value(SECTION, "has_profile", false))
	character_kind = String(config.get_value(SECTION, "character_kind", ""))
	hairstyle_id = String(config.get_value(SECTION, "hairstyle_id", ""))
	facial_hair_id = String(config.get_value(SECTION, "facial_hair_id", "none"))
	eyebrows_id = String(config.get_value(SECTION, "eyebrows_id", "none"))
	hair_color_id = String(config.get_value(SECTION, "hair_color_id", "brown"))
	eye_color_id = String(config.get_value(SECTION, "eye_color_id", "brown"))
	skin_tone = String(config.get_value(SECTION, "skin_tone", "tan"))


func _save() -> void:
	var config := ConfigFile.new()
	config.set_value(SECTION, "has_profile", has_profile)
	config.set_value(SECTION, "character_kind", character_kind)
	config.set_value(SECTION, "hairstyle_id", hairstyle_id)
	config.set_value(SECTION, "facial_hair_id", facial_hair_id)
	config.set_value(SECTION, "eyebrows_id", eyebrows_id)
	config.set_value(SECTION, "hair_color_id", hair_color_id)
	config.set_value(SECTION, "eye_color_id", eye_color_id)
	config.set_value(SECTION, "skin_tone", skin_tone)
	var error := config.save(SAVE_PATH)
	if error != OK:
		push_warning("Could not save player profile: %s" % error_string(error))
