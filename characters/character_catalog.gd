class_name CharacterCatalog
extends RefCounted

## Reads/writes the on-disk character catalog - the ".character.json"
## manifests the character editor tool's Import/Generate Rig features
## produce. Extracted out of tools/character_editor/character_editor_rig_handler.gd
## so anything (gameplay code, not just the tool) can list or load a
## character without depending on the tool's own scene/node instance. Pure
## data layer only: no UI side effects, no `editor` back-reference.

const GENERATED_DIRECTORY := "res://assets/models/generated_characters"
const IMPORTED_DIRECTORY := "res://assets/models/imported_characters"

## Built-in characters (CHARACTER_KINDS in character_editor.gd) keep their
## source models where they already lived before the catalog existed, not
## copied into IMPORTED_DIRECTORY - their manifests are written directly
## alongside those existing files instead (matching every other manifest's
## "<model_basename>.character.json" convention), so these directories need
## their own scan roots. Migrated one at a time as each is actually needed
## (see CURRENT_TASK.md's Phase 0) rather than all of CHARACTER_KINDS at
## once - directories are safe to list here before every file in them has
## a manifest yet, since the scan just skips anything that doesn't.
const BUILTIN_DIRECTORIES: PackedStringArray = [
	"res://assets/models/pistol_starter/MotusMan",
	"res://assets/models/mixamo_characters",
	"res://assets/models/action_adventure_pack",
]


## Every character (imported or generated) gets one of these at creation
## time, stored as its manifest's "id" field and used as its storage
## folder name under IMPORTED_DIRECTORY/GENERATED_DIRECTORY - unlike a
## filename-derived kind_id, it can never collide with another character
## and never changes across renames or re-imports. Crypto is used purely
## as a convenient source of random bytes, not for any security property.
static func generate_uuid_v4() -> String:
	var bytes := Crypto.new().generate_random_bytes(16)
	bytes[6] = (bytes[6] & 0x0F) | 0x40
	bytes[8] = (bytes[8] & 0x3F) | 0x80
	var hex := bytes.hex_encode()
	return "%s-%s-%s-%s-%s" % [
		hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4),
		hex.substr(16, 4), hex.substr(20, 12),
	]


## Returns info's existing "id", assigning one first if it predates
## per-character ids. info is the live Dictionary the caller owns, so this
## mutation needs no explicit write-back.
static func ensure_id(info: Dictionary) -> String:
	var character_id: String = info.get("id", "")
	if character_id.is_empty():
		character_id = generate_uuid_v4()
		info["id"] = character_id
	return character_id


## Scans both IMPORTED_DIRECTORY and GENERATED_DIRECTORY for
## ".character.json" manifests and returns kind_id -> info for every valid
## one found (skips anything whose model no longer resolves - a manifest
## left behind after its asset was deleted by hand).
static func list_all() -> Dictionary:
	var found: Dictionary = {}
	_scan_directory(IMPORTED_DIRECTORY, found)
	_scan_directory(GENERATED_DIRECTORY, found)
	for directory: String in BUILTIN_DIRECTORIES:
		_scan_directory(directory, found)
	return found


## Recurses one or more levels so both the flat legacy layout (manifests
## directly under path) and per-character id folders (path/<uuid>/*) are
## found; bounded in practice since these two directories only ever hold
## catalog character assets.
static func _scan_directory(path: String, found: Dictionary) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		var entry_path := path.path_join(entry)
		if directory.current_is_dir():
			_scan_directory(entry_path, found)
		elif entry.ends_with(".character.json"):
			_read_manifest(entry_path, found)
		entry = directory.get_next()
	directory.list_dir_end()


static func _read_manifest(manifest_path: String, found: Dictionary) -> void:
	var file := FileAccess.open(manifest_path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	if not parsed is Dictionary:
		return
	var info: Dictionary = parsed
	var kind_id: String = info.get("kind_id", "")
	var model_path: String = info.get("model_path", "")
	if kind_id.is_empty() or not ResourceLoader.exists(model_path):
		return
	info["manifest_path"] = manifest_path
	var had_id := not String(info.get("id", "")).is_empty()
	ensure_id(info)
	if not had_id:
		persist_character(info, manifest_path)
	found[kind_id] = info


## Writes info as manifest_path's JSON contents, removing any previous
## manifest location first if info is moving (e.g. a rig reset returning a
## character to its unrigged source path). Returns false if the file
## couldn't be written, so the caller can surface that to its own UI.
static func persist_character(info: Dictionary, manifest_path: String) -> bool:
	var old_manifest: String = info.get("manifest_path", "")
	if not old_manifest.is_empty() and old_manifest != manifest_path:
		remove_file(old_manifest)
	info["manifest_path"] = manifest_path
	var file := FileAccess.open(manifest_path, FileAccess.WRITE)
	if file == null:
		return false
	var persistent := info.duplicate(true)
	persistent["version"] = 1
	file.store_string(JSON.stringify(persistent, "  "))
	return true


static func manifest_path_for_info(info: Dictionary) -> String:
	var model_path: String = info.get("model_path", "")
	return model_path.get_basename() + ".character.json"


static func generated_output_path(character_id: String, source_path: String) -> String:
	return "%s/%s/%s_rigged.tscn" % [
		GENERATED_DIRECTORY, character_id, source_path.get_file().get_basename().to_snake_case(),
	]


static func remove_file(path: String) -> void:
	if path.is_empty() or not FileAccess.file_exists(path):
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## Removes everything a character owns at one asset path. Characters
## imported/generated after per-character id folders were added have their
## own folder (named after their id) holding nothing but their own files, so
## that whole folder is removed outright. Characters from before that change
## still share a flat directory with every other character and have no such
## folder to remove - delete_files_by_basename's basename sweep is the
## fallback for those.
static func delete_character_assets(path: String, character_id: String) -> void:
	if path.is_empty():
		return
	var directory := path.get_base_dir()
	if not character_id.is_empty() and directory.get_file() == character_id:
		remove_directory_recursive(ProjectSettings.globalize_path(directory))
	else:
		delete_files_by_basename(path)


static func remove_directory_recursive(absolute_path: String) -> void:
	var directory := DirAccess.open(absolute_path)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while entry != "":
		if directory.current_is_dir():
			remove_directory_recursive(absolute_path.path_join(entry))
		else:
			directory.remove(entry)
		entry = directory.get_next()
	directory.list_dir_end()
	DirAccess.remove_absolute(absolute_path)


## Imports and rig generation both leave a cluster of sibling files next to
## the primary asset - .import metadata, and textures Godot's importer
## extracts to disk as "<basename>_<index>.<ext>" (seen with both FBX and
## GLB sources). There is no manifest of exactly what got created at import
## time, so this sweeps the asset's own directory for anything sharing its
## basename instead of hardcoding an extension list: "<basename>.*" and
## "<basename>_<digits>.*" only - never a bare prefix match - so an
## unrelated file that merely starts with the same characters (e.g. a
## separately imported "zombie2_details.glb" beside "zombie2.glb") is not
## swept up by accident. Fallback for characters imported before
## per-character id folders existed; see delete_character_assets.
static func delete_files_by_basename(path: String) -> void:
	if path.is_empty():
		return
	var directory := path.get_base_dir()
	var basename := path.get_file().get_basename()
	var dir_access := DirAccess.open(ProjectSettings.globalize_path(directory))
	if dir_access == null:
		return
	dir_access.list_dir_begin()
	var entry := dir_access.get_next()
	while entry != "":
		if not dir_access.current_is_dir() and _basename_owns_entry(entry, basename):
			dir_access.remove(entry)
		entry = dir_access.get_next()
	dir_access.list_dir_end()


static func _basename_owns_entry(entry: String, basename: String) -> bool:
	if not entry.begins_with(basename):
		return false
	var remainder := entry.substr(basename.length())
	if remainder.begins_with("."):
		return true
	if not remainder.begins_with("_"):
		return false
	var dot_index := remainder.find(".")
	if dot_index <= 1:
		return false
	return remainder.substr(1, dot_index - 1).is_valid_int()
