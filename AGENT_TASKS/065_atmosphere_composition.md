# 065 - Atmospheric composition, pressure and what they do

Status: **planned (2026-10-17)**. Follows [043](043_planet.md). Branch: `godot-4.7-upgrade`.
Read `docs/planet_lessons.md` first (how to measure, the traps).

Idea (user, 2026-10-17): the air's composition may change the weather and the colours. It does, and it
fits the rule "build causes, derive effects" ([043](043_planet.md)). Goes with [064](064_stars_and_life.md)
(the star's light) and [054](054_universe_foundation.md) (where a planet's numbers come from).

## Goal

An atmosphere is data (surface pressure, which gases, how much dust and haze) and everything the sky,
climate, weather, sound and plants do with the air follows from it, instead of the constants of the Earth
that `PlanetAir` and the weather use today.

## Where we are

- `PlanetAir`: Rayleigh and Mie scattering with the Earth's constants (`BETA_RAYLEIGH`, `BETA_MIE`, scale
  heights 8,000 m and 1,200 m), shrunk by `air_scale` (not below `MIN_AIR_SCALE` 0.25); the same maths is
  in `planet_sky.gdshader`. `air_height` is a setting (100 km Earth-equivalent).
- The climate (`PlanetSeasons`) is an energy balance with fixed longwave and greenhouse behaviour; weather
  (`PlanetWeather`) assumes water: clouds from moisture times lift, rain, snow; winds are zonal with the
  Earth's pattern (`zonal_wind`), cloud and wind speeds from `WIND_TURN`.
- Fog colour, ambient light, sun colour (air transmittance) and the cloud lighting
  (`cloud_sun_light`, `cloud_path`) all derive from those constants.
- Nothing varies the air between planets; there is no pressure, no gas list, no dust.

## What is true (what the air does)

- **Pressure and density.** Surface pressure sets the density (ideal gas: p = rho R T / M) and the scale
  height (H = kT / m g): a thin air (Mars, 0.006 bar) has a small sky glow, long shadows and little wind
  force; a thick one (Venus, 92 bar; Titan, 1.5 bar) is dense, hazy and slow.
- **Sky colour (scattering).** Rayleigh scattering goes as 1/wavelength^4 and grows with the gas's
  polarisability and the density: a nitrogen-oxygen air is blue; CO2 scatters more (a paler, whiter blue);
  methane **absorbs red** (a blue-green sky, as on Uranus and Neptune); **dust** scatters forward and
  absorbs blue (Mars: a butterscotch day sky and a *blue* sunset round the sun); **sulfur and organic
  haze** are orange-yellow (Venus, Titan); a clean thin air is nearly black with a faint glow.
- **Temperature (greenhouse).** CO2, methane and water vapour trap heat (a warming of tens of kelvin on
  Venus, about 33 K on the Earth); a thin air cannot, so the day-night swing is many tens of degrees (low
  heat capacity and little heat transport); a thick air evens it out between day and night side and between
  equator and poles.
- **Weather.** Clouds and rain need a *condensable* gas near its condensation point: water on the Earth,
  methane on Titan (methane rain and lakes), sulfuric acid clouds on Venus, CO2 snow at Mars's poles. The
  amount of vapour sets the humidity and so the cloud cover and the rain. **Winds** follow pressure
  differences and the planet's spin: a fast spin gives bands and storm tracks (the Earth's pattern); a slow
  spin gives one big circulation cell from the hot side to the cold one (Venus); a tidally locked world
  has a day-side to night-side wind ([064](064_stars_and_life.md)). Wind force goes as density times speed
  squared.
- **Boiling point and phases.** Water boils lower at low pressure (no liquid water on Mars) and higher at
  high pressure: whether there is sea, ice or only vapour comes from pressure and temperature together.
- **Ozone and UV.** Oxygen makes an ozone layer that shields the ground from UV; no free oxygen, no ozone
  (links to the plants' tolerance in 064). Free oxygen is itself a product of life.
- **Sound.** Speed and loudness depend on the air's density and temperature (a thin air is almost silent).
- **Light on the ground** is the star's light filtered by the air: a thick or dusty air changes the colour
  of the ground light as well as the sky, which is what plants get (064).
- **Escape.** A small, hot planet cannot hold light gases (hydrogen, helium) or any air at all (the Moon,
  Mercury): the planet's mass, temperature and the star's activity decide which gases remain.

## Plan

1. **`AtmosphereSettings` data** (a resource inside the planet's settings): surface pressure (bar), gas
   fractions (N2, O2, CO2, CH4, H2O vapour as humidity, Ar, SO2), aerosols (dust, haze, sulfur: amount and
   colour). Presets: Earth-like, Mars-like (thin, dusty), Venus-like (thick, hazy), Titan-like (thick,
   orange, methane), Neptune-like (methane blue, for gas giants seen from afar), airless.
2. **Derive the physics** in one place (`PlanetAir` from the settings): density and scale height from
   pressure, temperature and gravity; per-gas Rayleigh coefficients (a small table of relative
   cross-sections) and absorption (methane's red band); Mie from the aerosols (amount, forward
   scattering, colour). The CPU and the sky shader read the *same* numbers (pass them as uniforms; do not
   keep two copies of constants as today).
3. **Sky, sun, fog, clouds, ambient** use the derived coefficients (all colours follow; a blue sunset under
   dust comes out of the maths and needs no special case); cloud colour from the condensate (white water,
   yellow sulfur, orange methane haze).
4. **Climate:** the greenhouse effect as a function of CO2, CH4 and H2O (a temperature offset or a change of
   the outgoing longwave in `PlanetSeasons`), the heat capacity from the pressure (day-night swing), and
   the pressure-dependent boiling point deciding sea, ice or none ([058](058_climate_and_orbit_depth.md)).
5. **Weather:** the condensable species decides what falls (rain, methane rain, snow, none) and how
   clouds are made (`PlanetWeather` stays water by default); the wind pattern from the spin and the
   pressure (number of bands from the rotation rate; a locked planet's day-night wind); wind force from the
   density (sway of the plants and the strength of storms).
6. **Light for life:** the ground spectrum (star times air) feeds the plant colour and productivity rule of
   [064](064_stars_and_life.md); the UV index uses ozone from the oxygen.
7. **Sound:** a loudness and speed factor from the density ([051](051_life_and_sound.md)).
8. **Derive a planet's air** from its mass, temperature, the star and a seed
   ([054](054_universe_foundation.md), [061](061_other_planet_types.md)): small and hot means thin or none,
   a habitable world gets an N2-O2 air, a cold giant gets hydrogen-helium with methane; the start-menu
   parameter "sun-like habitable or any" picks the first or lets the dice choose.
9. **Check:** a screenshot table at noon and sunset for the six presets; the lab prints the derived numbers
   (density, scale height, Rayleigh colour, greenhouse offset, boiling point).

## Done when

- The six presets give six visibly different skies and sunsets from the same code, a different
  temperature, and the right kind of weather; the CPU and the shader agree (a check compares the sun's
  transmittance on both); the doc ("Levels of the air") explains the settings.

## Risks and open questions

- Do not over-model: three scattering colours, a handful of gases and one greenhouse number are enough; a
  spectrum or a radiative-transfer model is not needed.
- The air shrinking with the planet (`air_scale`, `MIN_AIR_SCALE`, [047](047_sky_and_sunsets.md)) is a game
  choice for small planets; the composition settings must keep working with it (the optical depths stay
  the Earth's by design; the *colours* change with the gases).
- **Decided (user, 2026-10-17): small first**: pressure, greenhouse, dust and methane (and the humidity
  the weather already has); keep the data model open to more gases later.
- The player's breathing and health are not considered now (the player is parked).
