class_name Star
extends Resource
## A star as a physical object: its mass sets the rest (main sequence). Units are the Sun's
## (mass, luminosity, radius), Kelvin, billions of years. Pure data: nothing here touches a scene.

const SUN_TEMPERATURE := 5772.0 ## K

@export var mass := 1.0 ## solar masses
@export var age := 4.6 ## billions of years

var luminosity: float: get = _get_luminosity ## solar luminosities
var radius: float: get = _get_radius ## solar radii
var temperature: float: get = _get_temperature ## K, the surface
var lifetime: float: get = _get_lifetime ## billions of years on the main sequence
var colour: Color: get = _get_colour ## the blackbody colour, as seen (sRGB, brightest channel 1)
var spectral_class: String: get = _get_spectral_class
var flare_level: float: get = _get_flare_level ## 0..1: how often and how hard it flares


static func from_mass(star_mass: float, star_age := 4.6) -> Star:
	var star := Star.new()
	star.mass = star_mass
	star.age = star_age
	return star


func _get_luminosity() -> float:
	if mass < 0.43:
		return 0.23 * pow(mass, 2.3)
	if mass < 2.0:
		return pow(mass, 4.0)
	return 1.4 * pow(mass, 3.5)


func _get_radius() -> float:
	return pow(mass, 0.8) if mass < 1.0 else pow(mass, 0.57)


func _get_temperature() -> float:
	return SUN_TEMPERATURE * pow(luminosity / (radius * radius), 0.25)


func _get_lifetime() -> float:
	return 10.0 * mass / luminosity


## The inner and outer edge of the zone where water can be liquid, in AU (a rough single-planet
## estimate from the flux an Earth-like world would need: 1.1 and 0.53 of what Earth gets).
func habitable_zone() -> Vector2:
	return Vector2(sqrt(luminosity / 1.1), sqrt(luminosity / 0.53))


## The distance (AU) beyond which ice survives in the system's youth.
func frost_line() -> float:
	return 2.7 * sqrt(luminosity)


## True if complex life has had the time to appear (the star's age against a few billion years).
func old_enough_for_life() -> bool:
	return age >= 2.5 and age < lifetime


func _get_spectral_class() -> String:
	var t := temperature
	var letter := "M"
	if t >= 30000.0:
		letter = "O"
	elif t >= 10000.0:
		letter = "B"
	elif t >= 7500.0:
		letter = "A"
	elif t >= 6000.0:
		letter = "F"
	elif t >= 5200.0:
		letter = "G"
	elif t >= 3700.0:
		letter = "K"
	return letter


func _get_flare_level() -> float:
	return clampf((0.6 - mass) / 0.5, 0.0, 1.0)


## Blackbody colour for a temperature (Tanner Helland's fit, good from 1000 K to 40000 K).
static func blackbody(kelvin: float) -> Color:
	var t := clampf(kelvin, 1000.0, 40000.0) / 100.0
	var red := 255.0
	if t > 66.0:
		red = 329.698727446 * pow(t - 60.0, -0.1332047592)
	var green := 255.0
	if t <= 66.0:
		green = 99.4708025861 * log(t) - 161.1195681661
	else:
		green = 288.1221695283 * pow(t - 60.0, -0.0755148492)
	var blue := 255.0
	if t < 66.0:
		blue = 0.0 if t <= 19.0 else 138.5177312231 * log(t - 10.0) - 305.0447927307
	return Color(clampf(red, 0.0, 255.0) / 255.0, clampf(green, 0.0, 255.0) / 255.0,
			clampf(blue, 0.0, 255.0) / 255.0)


func _get_colour() -> Color:
	return blackbody(temperature)
