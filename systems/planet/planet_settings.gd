class_name PlanetSettings
extends Resource
## Every number a planet is made from. Same seed + same settings = same planet.

@export var world_seed := 1337
@export var radius := 20000.0 ## m, the sea level sphere (Earth: 6,371,000)
@export var sea_level := 0.0 ## m above `radius`
@export var relief := 0.0 ## m from the sea to the highest ranges; 0: from the radius (at least 300)
@export var ocean_fraction := 0.7 ## the share of the planet's area under the sea
@export var species_count := 120 ## how many plant species the seed makes (SpeciesGenerator)
@export var plants_on := true ## false: no plants grow (a stage of the generation switched off)
@export var animals_on := true ## false: no animals
@export var plant_density := 1.0
@export var rock_density := 1.0
@export var lake_depth_share := 0.08 ## a hollow is a lake when deeper than this share of the relief
@export var hydrology_cells := 96 ## cells along a cube face for rivers and lakes (0: none)
@export var day_seconds := 1440.0 ## a solar day in seconds of play (what a clock day is)
@export var year_days := 16.0 ## solar days in a year
@export var month_days := 3.5 ## solar days the moon takes to go round (game scale)
@export var axial_tilt := 23.4 ## degrees: how far the spin axis leans from the orbit's normal
@export var start_hour := 9.0 ## local solar time of the first moment (12 is noon)
@export var start_year := 0.12 ## share of the year at the start (0: the northern spring equinox)
@export var time_scale := 1.0 ## 1: real play time; more makes the days and years pass faster
@export var star_mass := 1.0 ## solar masses of the planet's star (1: the Sun, a white light)
@export var star_readability := 0.0 ## 0 the star's true colour .. 1 readable (Sun-like light)
@export var eccentricity := 0.0 ## the orbit's: 0 a circle (Earth 0.017)
@export var perihelion_share := 0.0 ## share of the year the planet is nearest its star
@export var insolation := 1.0 ## the star's light here against the Earth's: luminosity / distance^2
@export var universe_seed := 0 ## the universe this planet comes from (0: none, a plain planet)
@export var universe_system := 0 ## its star system's number in that universe
@export var universe_planet := 0 ## its number among that system's planets
@export var universe_sunlike := 1 ## 1: that universe's home system was made Sun-like
@export var air_height := 100000.0 ## m the Earth air would reach (scaled to the radius)
@export var plates := 14 ## tectonic plates (Earth has about 15 big ones)
@export var tile_cells := 48 ## quads along one tile edge, at every level of detail
@export var tile_max := 128.0 ## m, the widest a finest tile may be
@export var split_factor := 2.0 ## a tile splits when the player is closer than this many widths
@export var collide_tiles := 1.2 ## finest tiles within this many tile widths get a collider


## How many times a cube face is halved to get the finest tiles.
func max_level() -> int:
	var face_arc := radius * PI * 0.5
	return maxi(ceili(log(face_arc / tile_max) / log(2.0)), 0)
