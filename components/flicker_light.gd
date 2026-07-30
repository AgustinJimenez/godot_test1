extends Light3D
## Layered-sine energy flicker for an unstable fluorescent-light feel.
## Attach directly to an OmniLight3D/SpotLight3D; base_energy should match
## whatever light_energy was set to in the editor before adding this script.

@export var base_energy := 4.5
@export var flicker_amount := 0.6
@export var flicker_speed := 8.0

var _phase_offset := randf() * 1000.0


func _process(_delta: float) -> void:
	var t := (Time.get_ticks_msec() / 1000.0) * flicker_speed + _phase_offset
	var n := sin(t) * 0.5 + sin(t * 2.7) * 0.3 + sin(t * 5.3) * 0.2
	light_energy = max(0.0, base_energy + n * flicker_amount)
