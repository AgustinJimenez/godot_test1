class_name PlanetSettings
extends Resource
## Every number a planet is made from. Same seed + same settings = same planet.

@export var world_seed := 1337
@export var radius := 20000.0 ## m, the sea level sphere (Earth: 6,371,000)
@export var sea_level := 0.0 ## m above `radius`
@export var relief := 0.0 ## m from the sea to the highest ranges; 0: from the radius (at least 300)
@export var ocean_fraction := 0.7 ## the share of the planet's area under the sea
@export var species_count := 120 ## how many plant species the seed makes (SpeciesGenerator)
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
