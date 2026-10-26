extends RefCounted
## Swaps the climb's hang, grab and pull-up clips for the reverse-engineered game's (BVH, read from its folder,
## retargeted onto the player and baked). The folder is not in the repo: no folder, no swap.

const BVH_BAKE := preload("res://tests/manual/ledge_anim/bvh_bake.gd")
const BVH_RETARGET := preload("res://tests/manual/ledge_anim/bvh_retarget.gd")
## The hang swings the body out from the wall about the hands: the clips hang plumb under them, and the real wall
## is where the chest and feet are (feet 0.5 m past the wrists).
const HANG_TILT := deg_to_rad(20.0)
## clip -> [BVH file, frame lined up with the wrists (0 first, 1 last), tilt at the start, tilt after the span, span (fraction of the clip)]
const CLIPS := {
	ClimbClips.IDLE: ["ledge-hang-idle-base", 0, HANG_TILT, HANG_TILT, 1.0],
	ClimbClips.GRAB: ["ledge-land-waist-contact_to_ledge-grab-idle", 1, 0.0, HANG_TILT, 1.0],
	ClimbClips.UP: ["ledge-grab-idle_to_ledge-facing-idle-full", 0, HANG_TILT, 0.0, 0.3],
}
## Each hand this far from the body: between the player's grip (0.22, the clip's arms cross over the head when pulled
## in to it) and the clip's own (0.33, the wrists then fall short of the hold).
const HAND_HOME := 0.27
const WRIST := 1.7 # m the wrists are above the capsule's feet in the hang
## The clips hold the arms angled into the wall (elbows 0.15 m past the wrists' depth); the body is baked this far out
## so the elbows and shoulders are not inside it, and the hand IK draws the wrists the rest of the way to the ledge.
const HANDS_OUT := 0.14


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
			var anim: Animation = BVH_BAKE.bake(spec[0], retarget, prefix, WRIST, WRIST, spec[1], clip == ClimbClips.IDLE, PlayerClimb.HAND_BACK - HANDS_OUT, spec[2], spec[3], spec[4],
					overrides.get(ClimbClips.IDLE) if clip != ClimbClips.IDLE else null)
			if anim == null:
				push_warning("GALS ledge clips: could not bake %s" % spec[0])
				return false
			overrides[clip] = anim
	if not ClimbClips.add_to(library, player.skeleton, player.body._target_humanoid_map, stand_hips, player, overrides):
		return false
	if on:
		player.climb.use_clips(WRIST, WRIST, PlayerClimb.HANG_BACK, HAND_HOME)
	else:
		player.climb.use_clips()
	print("CLIMB_LAB clips: ", "GALS (BVH)" if on else "Mixamo")
	return true
