extends Node
func _scan(dir: String, bad: Array) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd") and load(dir + "/" + f) == null:
			bad.append(dir + "/" + f)
	for d in DirAccess.get_directories_at(dir):
		if not d.begins_with(".") and d != "addons" and d != ".venv":
			_scan(dir + "/" + d, bad)
func _ready() -> void:
	var bad := []
	_scan("res:/", bad)
	for b in bad: print("PARSEFAIL ", b)
	print("PARSE_ALL bad=", bad.size())
	get_tree().quit(1 if bad.size() > 0 else 0)
