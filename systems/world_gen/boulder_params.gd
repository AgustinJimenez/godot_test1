class_name BoulderParams
extends RefCounted
## The hand-set numbers of the procedural boulder (lump_bake.gdshader, array `bp`).
## Each entry: name, default, low, high. The square scene shows a slider for each;
## `values` is what the next bake uses.

const LIST: Array = [
	["lobe_cover", 0.72, 0.2, 1.0], ["lobe_radius", 0.4, 0.15, 0.9],
	["lobe_radius_var", 0.55, 0.0, 1.2],
	["lobe_squash", 0.45, 0.2, 1.0], ["warp_big_cm", 9.0, 0.0, 25.0],
	["warp_small_cm", 3.0, 0.0, 10.0],
	["merge_level", 0.3, 0.1, 0.8], ["edge_width", 0.18, 0.03, 0.5], ["rim_height", 0.5, 0.0, 3.0],
	["plateau", -1.4, -2.5, 2.5], ["rim_variation", 0.75, 0.0, 1.0], ["swell", 1.6, 0.0, 4.0],
	["snake_ridge", 0.9, 0.0, 3.0], ["snake_width", 0.014, 0.004, 0.05], ["pit_cover", 0.12, 0.0, 0.5],
	["pit_depth", 1.0, 0.0, 3.0], ["crumb", 2.2, 0.0, 5.0], ["fine_bumps", 0.055, 0.0, 0.2],
	["fine_size", 2.0, 0.5, 4.0], ["crease", 0.3, 0.0, 1.0], ["colour_gain", 1.18, 0.8, 1.6],
	["colour_contrast", 0.85, 0.4, 1.2], ["dark_specks", 0.35, 0.0, 1.0], ["grain", 0.6, 0.0, 1.5],
	["edge_detail_cm", 0.9, 0.0, 6.0], ["edge_scallop", 0.03, 0.0, 0.4],
	["edge_soft", 0.07, 0.02, 0.5],
	["speck_cover", 0.022, 0.0, 0.8], ["speck_depth", 0.075, 0.0, 0.15],
	["traced_features", 1.0, 0.0, 1.0], ["traced_gain", 1.0, 0.0, 3.0],
	["traced_soft_cm", 0.6, 0.1, 4.0], ["edge_layer", 1.05, 0.0, 3.0],
	["colour_swell", 1.0, 0.0, 1.0], ["lobe_tint", 1.0, 0.0, 2.0], ["edge_dark", 0.5, 0.0, 4.0],
	["colour_detail", 0.0, 0.0, 3.0],
	["cavity_colour", 1.4, 0.0, 3.0], ["cavity_chroma", 0.3, 0.0, 1.0],
	["fine_colour", 0.085, 0.0, 0.5], ["fine_height", 0.0028, 0.0, 0.03],
	["fine_cm", 0.6, 0.4, 2.0], ["cavity_clip", 0.03, 0.01, 1.0], ["cavity_small", 0.4, 0.0, 1.5],
	["lip_cover", 0.005, 0.0, 0.5], ["lip_depth", 0.11, 0.0, 0.2], ["lip_cm", 0.6, 0.3, 1.5],
]

## The sliders that still change the bake while `traced_features` is on. The others drive the old
## procedural lobes, rims, pits and cracks, which the traced features replace (checked by
## baking each at its extreme).
const LIVE_WHEN_TRACED: Array[String] = [
	"fine_bumps", "fine_size", "traced_features", "traced_gain", "traced_soft_cm",
	"edge_layer", "colour_swell", "lobe_tint", "edge_dark", "colour_detail",
	"cavity_colour", "cavity_chroma", "fine_colour", "fine_height", "fine_cm",
	"cavity_clip", "cavity_small",
	"lip_cover", "lip_depth", "lip_cm",
]

## On/off switches: two positions, 0 and 1 (the shader only checks above or below 0.5).
const SWITCHES: Array[String] = ["traced_features"]

static var values: Array[float] = defaults()


static func defaults() -> Array[float]:
	var out: Array[float] = []
	for entry: Array in LIST:
		out.append(float(entry[1]))
	return out


static func as_packed() -> PackedFloat32Array:
	return PackedFloat32Array(values)


## Whether a slider changes the bake in the current mode: with the traced features on only the
## LIVE_WHEN_TRACED ones do, with them off the others (the old procedural controls) do instead.
static func is_live(entry_name: String) -> bool:
	var traced := values[traced_index()] > 0.5
	return LIVE_WHEN_TRACED.has(entry_name) or not traced


static func traced_index() -> int:
	for index in LIST.size():
		if LIST[index][0] == "traced_features":
			return index
	return 0
