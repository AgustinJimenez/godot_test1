class_name StarLight
extends RefCounted
## What a star's light does to the colour of leaves (task 064). A leaf is the colour of the light it
## does not use: under a red dwarf, with little blue and much red and infrared, plants may absorb
## nearly everything and look dark, purple or deep red; under a hot white star there is plenty of
## light and a lot of UV, so leaves may be paler, yellower and waxy. This is a hypothesis of
## astrobiology, kept here as the rule of the game. Applied after the species are made, so the
## random draws are the same and a Sun-like star changes nothing. `readability` (0 true .. 1
## readable) blends back to Earth-like greens.

const COOL := 2800.0 ## K below the Sun at which the cool-star look is complete (a red dwarf)
const HOT := 2800.0 ## K above the Sun for the hot-star look (an F or A star)


## How far the star's colour is from the Sun's: +1 a red dwarf (cool), 0 the Sun, -1 a hot star.
static func coolness(star: Star) -> float:
	var shift := Star.SUN_TEMPERATURE - star.temperature
	return clampf(shift / (COOL if shift > 0.0 else HOT), -1.0, 1.0)


## The leaf colour a plant of Earth-like green `colour` has under `star`.
static func leaf_colour(colour: Color, star: Star, readability := 0.0) -> Color:
	var k := coolness(star) * (1.0 - clampf(readability, 0.0, 1.0))
	if is_zero_approx(k):
		return colour
	var hue := colour.h
	var saturation := colour.s
	var value := colour.v
	if k > 0.0: # cool star: toward dark purple and red
		hue = lerp_angle(hue * TAU, 0.82 * TAU, 0.6 * k) / TAU
		saturation *= 1.0 - 0.2 * k
		value *= 1.0 - 0.55 * k
	else: # hot star: paler, yellower, a little lighter
		hue = lerp_angle(hue * TAU, 0.17 * TAU, -0.5 * k) / TAU
		saturation *= 1.0 + 0.25 * k
		value = minf(value * (1.0 - 0.15 * k), 1.0)
	return Color.from_hsv(fposmod(hue, 1.0), clampf(saturation, 0.0, 1.0), clampf(value, 0.0, 1.0),
			colour.a)


## Recolours the leaves (and their tips) of `species` for `star`.
static func apply(species: Array[PlantSpecies], star: Star, readability := 0.0) -> void:
	for one in species:
		one.leaf = leaf_colour(one.leaf, star, readability)
		one.leaf_tip = leaf_colour(one.leaf_tip, star, readability)
