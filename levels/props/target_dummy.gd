extends StaticBody3D
## Shooting-range dummy: red flash on hit, topples and goes inert on death.
## Damage arrives through the Health child — the weapon never knows this type.

@onready var health: Health = $Health

var _mat: StandardMaterial3D
var _flash_tween: Tween


func _ready() -> void:
	# One shared material instance per dummy so the hit flash (emission pulse)
	# affects the whole figure without touching other dummies.
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.72, 0.7, 0.63)
	_mat.roughness = 0.9
	_mat.emission_enabled = true
	_mat.emission = Color(1, 0.2, 0.15)
	_mat.emission_energy_multiplier = 0.0
	for child in $Visual.get_children():
		(child as MeshInstance3D).material_override = _mat
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)


func _on_damaged(_amount: float) -> void:
	if _flash_tween:
		_flash_tween.kill()
	_mat.emission_energy_multiplier = 1.4
	_flash_tween = create_tween()
	_flash_tween.tween_property(_mat, "emission_energy_multiplier", 0.0, 0.25)


func _on_died() -> void:
	collision_layer = 0  # stop eating bullets once down
	_mat.albedo_color = Color(0.35, 0.33, 0.3)
	var tween := create_tween()
	tween.tween_property(self, "rotation:x", rotation.x + TAU / 4.0, 0.7)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
