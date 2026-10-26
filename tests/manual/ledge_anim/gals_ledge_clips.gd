extends RefCounted
## Swaps the climb's hang, grab and pull-up clips for the reverse-engineered game's (BVH, read from its folder,
## retargeted onto the player and baked). The folder is not in the repo: no folder, no swap.

const BVH_BAKE := preload("res://tests/manual/ledge_anim/bvh_bake.gd")
const BVH_RETARGET := preload("res://tests/manual/ledge_anim/bvh_retarget.gd")
## clip -> [BVH file, frame lined up with the wrists (0 first, 1 last)]
const CLIPS := {
	ClimbClips.IDLE: ["ledge-hang-idle-base", 0],
	ClimbClips.GRAB: ["ledge-land-waist-contact_to_ledge-grab-idle", 1],
	ClimbClips.UP: ["ledge-grab-idle_to_ledge-facing-idle-full", 0],
}
const WRIST := 1.8 # m the wrists are above the capsule's feet in the hang


## `on`: the BVH clips, else the Mixamo ones back. Returns whether the swap happened.
static func apply(player: Player, on: bool) -> bool:
	if player == null or player.climb == null or not player.climb.clips_ok:
		return false
	if on and not BVH_BAKE.available():
		push_warning("GALS ledge clips: %s not found" % BVH_BAKE.DIR)
		return false
	player.climb.release()
	var library := player.body.anim_player.get_animation_library(&"moves")
	var idle := library.get_animation(&"unarmed_idle")
	var stand_hips: Vector3 = idle.track_get_key_value(ClimbClips.hips_track(idle), 0)
	var overrides := {}
	if on:
		var retarget := BVH_RETARGET.new(player.skeleton, player.body._target_humanoid_map)
		var prefix := String(idle.track_get_path(ClimbClips.hips_track(idle))).get_slice(":", 0)
		for clip: StringName in CLIPS:
			var spec: Array = CLIPS[clip]
			var anim: Animation = BVH_BAKE.bake(spec[0], retarget, prefix, WRIST, spec[1], clip == ClimbClips.IDLE)
			if anim == null:
				push_warning("GALS ledge clips: could not bake %s" % spec[0])
				return false
			overrides[clip] = anim
	if not ClimbClips.add_to(library, player.skeleton, player.body._target_humanoid_map, stand_hips, player, overrides):
		return false
	if on:
		player.climb.use_clips(WRIST, WRIST)
	else:
		player.climb.use_clips()
	print("CLIMB_LAB clips: ", "GALS (BVH)" if on else "Mixamo")
	return true
