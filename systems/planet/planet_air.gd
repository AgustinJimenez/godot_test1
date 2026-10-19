class_name PlanetAir
extends RefCounted
## The planet's atmosphere as physics, the same maths as shaders/world/planet_sky.gdshader so the
## sky the player sees and the light and fog the game sets agree. Air scatters sunlight: the
## molecules (Rayleigh) scatter blue far more than red, which is why the day sky is blue and the
## low sun is red (its light has gone through a lot of air and lost its blue), and haze and dust
## (Mie) scatter all colours forward round the sun. The density of both falls off exponentially with
## height (their scale heights). All lengths are metres; positions are relative to the planet's
## centre. Above the atmosphere there is no air: no sky light, only the sun.
##
## A planet smaller than the Earth gets an atmosphere shrunk to match (`air_scale`, the planet's
## radius over the Earth's, but not under MIN_AIR_SCALE): every length of the air (its scale heights
## and its top) is multiplied by it and the scattering per metre is divided by it, so the optical
## depths are the Earth's and a small planet has the Earth's blue day and red sunset, only in a
## shell of a few hundred metres. (With the Earth's air round a 20 km planet the sun's path at
## sunset would be 28 times too thin to turn red.)

## per metre at sea level: red, green, blue
const BETA_RAYLEIGH := Vector3(5.8e-6, 13.5e-6, 33.1e-6)
const BETA_MIE := 21e-6
## Ozone takes the green and some red out of light that crosses a lot of air (it keeps the
## horizon blue instead of yellow-green and turns the sunset pink). Its layer is about 15 km thick
## against the 8 km scale height of the molecules: OZONE_DEPTH times their optical depth.
const BETA_OZONE := Vector3(0.65e-6, 1.881e-6, 0.085e-6)
const OZONE_DEPTH := 1.9
const SCALE_RAYLEIGH := 8000.0 ## m: how fast the molecules thin out with height (the Earth's)
const SCALE_MIE := 1200.0 ## m: the haze and dust, which hug the ground (the Earth's)
const EARTH_RADIUS := 6371000.0
## The least `air_scale`: a planet smaller than a quarter of the Earth still has air a quarter as
## deep (its top at 25 km, a scale height of 2 km), so the weather, the clouds and the mountains lie
## in the lower air and the sky only darkens high above them, as on the Earth. Its sunsets are a
## little less red than the Earth's for it (the sun's path through the air is shorter), still
## orange.
const MIN_AIR_SCALE := 0.25


## The air's size against the Earth's for a planet of `radius` (see the top of this file).
static func scale_for(radius: float) -> float:
	return maxf(radius / EARTH_RADIUS, MIN_AIR_SCALE)


## True if the ray from `from` along `along` (a unit vector) hits the planet of `radius`.
static func hits_planet(from: Vector3, along: Vector3, radius: float) -> bool:
	var b := from.dot(along)
	if b > 0.0:
		return false # pointing away from the planet's centre
	var closest_sq := from.length_squared() - b * b
	return closest_sq < radius * radius


## The distance along the ray from `from` to where it leaves the atmosphere (radius `top`).
static func to_top(from: Vector3, along: Vector3, top: float) -> float:
	var b := from.dot(along)
	var c := from.length_squared() - top * top
	return -b + sqrt(maxf(b * b - c, 0.0))


## The share of the sun's light of each colour that reaches the point `from` (relative to the
## planet's centre) through the air toward `sun`: 0 where the planet is in the way.
static func sun_transmittance(from: Vector3, sun: Vector3, radius: float, top: float,
		air_scale: float = 1.0) -> Vector3:
	if hits_planet(from, sun, radius):
		return Vector3.ZERO
	var length := to_top(from, sun, top)
	var steps := 12
	var step_length := length / float(steps)
	var rayleigh := 0.0
	var mie := 0.0
	for index in steps:
		var at := from + sun * (float(index) + 0.5) * step_length
		var height := at.length() - radius
		rayleigh += exp(-height / (SCALE_RAYLEIGH * air_scale)) * step_length
		mie += exp(-height / (SCALE_MIE * air_scale)) * step_length
	var beta := BETA_RAYLEIGH + BETA_OZONE * OZONE_DEPTH
	var tau := (beta * rayleigh + Vector3.ONE * BETA_MIE * 1.1 * mie) / air_scale
	return Vector3(exp(-tau.x), exp(-tau.y), exp(-tau.z))


## The colour of the sky seen from `from` along `along`, lit by `sun` (single scattering; the same
## integral as the sky shader, fewer steps), in units where the sun's own light is 1.
static func sky_color(from: Vector3, along: Vector3, sun: Vector3, radius: float, top: float,
		intensity: float, air_scale: float = 1.0) -> Vector3:
	var far := to_top(from, along, top)
	if hits_planet(from, along, radius):
		var b := from.dot(along)
		var disc := b * b - (from.length_squared() - radius * radius)
		far = minf(far, maxf(-b - sqrt(maxf(disc, 0.0)), 0.0))
	var steps := 10
	var mu := along.dot(sun)
	var phase_r := 3.0 / (16.0 * PI) * (1.0 + mu * mu)
	var g := 0.76
	var phase_m := 3.0 / (8.0 * PI) * ((1.0 - g * g) * (1.0 + mu * mu)) \
			/ ((2.0 + g * g) * pow(1.0 + g * g - 2.0 * g * mu, 1.5))
	var sum_r := Vector3.ZERO
	var sum_m := Vector3.ZERO
	var depth_r := 0.0
	var depth_m := 0.0
	for index in steps:
		# the steps crowd toward the eye (cubed), as in the sky shader: equal steps skip the dense air
		# near the viewer and turn the horizon yellow
		var u0 := pow(float(index) / float(steps), 3.0)
		var u1 := pow(float(index + 1) / float(steps), 3.0)
		var step_length := far * (u1 - u0)
		var at := from + along * far * 0.5 * (u0 + u1)
		var height := at.length() - radius
		var hr := exp(-height / (SCALE_RAYLEIGH * air_scale)) * step_length
		var hm := exp(-height / (SCALE_MIE * air_scale)) * step_length
		depth_r += hr
		depth_m += hm
		var light := sun_transmittance_inner(at, sun, radius, top, air_scale)
		if light.x < 0.0:
			continue
		var tau := (BETA_RAYLEIGH + BETA_OZONE * OZONE_DEPTH) * (depth_r + light.x)
		tau += Vector3.ONE * BETA_MIE * 1.1 * (depth_m + light.y)
		tau /= air_scale
		var attenuation := Vector3(exp(-tau.x), exp(-tau.y), exp(-tau.z))
		sum_r += attenuation * hr
		sum_m += attenuation * hm
	return intensity * (sum_r * BETA_RAYLEIGH * phase_r + sum_m * BETA_MIE * phase_m) / air_scale


## The optical depths (Rayleigh, Mie) from `at` to the sun, or (-1, 0) if the planet blocks it.
static func sun_transmittance_inner(at: Vector3, sun: Vector3, radius: float, top: float,
		air_scale: float = 1.0) -> Vector2:
	if hits_planet(at, sun, radius):
		return Vector2(-1.0, 0.0)
	var length := to_top(at, sun, top)
	var steps := 4
	var step_length := length / float(steps)
	var rayleigh := 0.0
	var mie := 0.0
	for index in steps:
		var point := at + sun * (float(index) + 0.5) * step_length
		var height := point.length() - radius
		rayleigh += exp(-height / (SCALE_RAYLEIGH * air_scale)) * step_length
		mie += exp(-height / (SCALE_MIE * air_scale)) * step_length
	return Vector2(rayleigh, mie)
