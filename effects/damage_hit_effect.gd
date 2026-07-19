class_name DamageHitEffect
extends Node3D

## Brief world-space burst spawned by weapons at an applied-damage contact.

const PARTICLE_COUNT := 7
const PARTICLE_RADIUS := 0.025
const BURST_DURATION := 0.28


static func spawn(parent: Node, hit_position: Vector3, hit_normal: Vector3) -> void:
	if parent == null:
		return
	var effect := DamageHitEffect.new()
	parent.add_child(effect)
	effect.global_position = hit_position + hit_normal * 0.015
	effect._emit_burst(hit_normal)


func _emit_burst(hit_normal: Vector3) -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.72, 0.015, 0.02)
	material.emission_enabled = true
	material.emission = Color(0.55, 0.005, 0.008)
	material.emission_energy_multiplier = 1.8
	var particle_mesh := SphereMesh.new()
	particle_mesh.radius = PARTICLE_RADIUS
	particle_mesh.height = PARTICLE_RADIUS * 2.0
	particle_mesh.material = material
	var outward := hit_normal.normalized()
	if outward.length_squared() < 0.001:
		outward = Vector3.UP
	var tangent := outward.cross(Vector3.UP)
	if tangent.length_squared() < 0.001:
		tangent = outward.cross(Vector3.RIGHT)
	tangent = tangent.normalized()
	var bitangent := outward.cross(tangent).normalized()
	var tween := create_tween().set_parallel()
	for index in PARTICLE_COUNT:
		var particle := MeshInstance3D.new()
		particle.mesh = particle_mesh
		particle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(particle)
		var angle := TAU * float(index) / float(PARTICLE_COUNT)
		var spread := tangent * cos(angle) + bitangent * sin(angle)
		var direction := (outward * 0.55 + spread * 0.85).normalized()
		var distance := 0.12 + 0.05 * float(index % 3)
		tween.tween_property(
				particle, ^"position", direction * distance, BURST_DURATION
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(
				particle, ^"scale", Vector3.ZERO, BURST_DURATION
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.finished.connect(queue_free)
