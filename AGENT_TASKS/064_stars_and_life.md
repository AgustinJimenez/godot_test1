# 064 - Stars and what their light does to life

Status: **planned (2026-10-17)**. Follows [043](043_planet.md). Branch: `godot-4.7-upgrade`.
Read `docs/planet_lessons.md` first (how to measure, the traps).

Decision (user, 2026-10-17): stars may have different colours, and that may alter the life on their planets.
It does, in real physics, and it fits the rule "build causes, derive effects" ([043](043_planet.md)).

## Goal

A star is a physical object (mass, then temperature, luminosity, radius, colour, lifetime, activity) whose
light sets the planet's sky, climate, day length of the year, and the colours and kinds of plants.

## What is true (and what is a guess)

- **Mass sets the rest.** Luminosity ~ M^3.5, main-sequence lifetime ~ M^-2.5 (the Sun ~ 10 billion years),
  radius ~ M^0.8, surface temperature from L and R. Colour is the blackbody colour of that temperature.
- **Kinds:** M (red dwarfs, 2,400-3,700 K, dim, long-lived, most common), K (orange, 3,700-5,200 K),
  G (yellow, the Sun 5,800 K), F (yellow-white, 6,000-7,500 K), A (white-blue, 7,500-10,000 K, short-lived).
  O and B stars live too short for complex life.
- **Habitable zone** (liquid water): distance ~ sqrt(L). Around a red dwarf it is so close that the year is
  days, the planet is probably **tidally locked** (one side always lit: a day side, a night side and a
  twilight ring) and flares can strip air and bathe the surface in UV.
- **Sky and sun:** the air scatters by wavelength: the sky is blue under a G star, paler and bluer under an
  F/A star, a dim orange under a K and a dark red-orange under an M star. The sun's disc is bigger and redder
  for a close red dwarf. Sunsets follow.
- **Light for plants (photosynthesis):** plants use the light they get; under a red star there are few
  photons in the blue and many in the red and infrared, so leaves may be dark (black, purple, deep red) to
  absorb as much as possible; under a hot blue-white star there is more light and much more UV, so plants
  may be lighter or yellower, shorter, with thick skins and pigments, or live in shade and under water. This
  is a hypothesis in astrobiology, not a fact: we state it as the rule of the game.
- **Productivity:** growth follows the photosynthetically active light (a PAR number from the star's
  spectrum and the planet's distance and air); less light means fewer, smaller plants, fewer layers, more
  bare ground; more light means denser forests.
- **UV:** high UV (hot star, thin air, no ozone) means no surface life or only hardy and dark forms; an
  ozone layer (from oxygen made by plants) is a result of life, not a given.
- **Time:** a planet around a short-lived star has had little time for life; the star's age is a setting.

The light that reaches the ground is the star's light filtered by the air, so the air's composition matters
here too (ozone and UV, haze, the ground spectrum): see [065](065_atmosphere_composition.md).

## Plan

1. `Star` resource: mass -> L, R, T, colour (Planck sRGB), lifetime, a flare level for M stars; a lab table
   of masses 0.1 - 3 solar masses (`--stars`).
2. **Light model:** the star's spectrum as three numbers (red, green, blue weights from the temperature)
   used by the sky shader (colour of the scattering input), the cloud shader (`cloud_sun`), the sun disc and
   the ambient. Do not hard-code white anywhere.
3. **Planet temperature from insolation** (`PlanetSeasons` energy balance gets the star's flux at the
   planet's distance), so a red dwarf's habitable world is close, and an F star's is far.
4. **Orbit and year by Kepler's third law** from distance and star mass; day length random or locked.
5. **Tidal locking:** if close enough to a dim star the planet is locked (spin = orbit): the sun stays at
   one place in the sky; the climate model needs a day side and a night side (heat transport by the wind
   to the night side): use [058](058_climate_and_orbit_depth.md).
6. **Plants:** `SpeciesGenerator` takes the star's light: leaf hue range and darkness from the spectrum,
   height and layer count from the PAR, UV tolerance (a bark and cuticle colour, the share of shade
   plants); the biome fitness uses the light too. Keep it a few parameters, not a new system.
7. **Ground and water colour:** the sea's colour and the ground's follow the light (a red world looks
   red-brown).
8. **UV and flares:** a surface UV index shown in the planet info; a flare is an event (a bright flash,
   an aurora) on active M stars, optional.
9. **Look checks:** a screenshot table at noon and dusk for M, K, G, F, A planets at their habitable
   distance; the plants' colours in each.

## Done when

- Five stars of different class give five visibly different skies, suns, plants and climates from the same
  code; the numbers (T, L, HZ distance, year) are printed by the lab and match the formulas; docs updated.

## Risks and open questions

- Colour is physics but beauty is not: a plain black-forest world may look bad; give the user a "plausible
  but readable" slider that blends toward Earth-like greens (default full physical? ask).
- A single scattering model with three channels is enough for the sky; a real spectrum is overkill.
- **Decided (user, 2026-10-17):** both colour modes exist as a start-menu parameter, **physical** and
  **readable**, and we look at the results and decide later. Implement it as one number
  (`star_colour_readability`, 0 physical .. 1 readable) that blends the star's spectrum weights, the plant
  hues and the darkness of the leaves toward Earth-like values, so the two modes are the ends of a slider
  and any middle value works too. A red dwarf's sun looks orange-red, not pure red, because the eye adapts:
  the physical mode should apply that adaptation, or it will look wrong.

## Progress (autonomous session, 2026-10-17, user away)

- Done: `Star` (mass to luminosity, radius, temperature, lifetime, colour, habitable zone, frost line, flare level),
  the colour tint of the light (step 2, see 054), insolation into the seasons (step 3), plant leaf colours by star
  (`StarLight`, step 6: cool stars give dark, rust and purple leaves, hot stars paler and yellower; `star_readability`
  blends back). Pictures at `--star-mass=0.15|1.0|1.6 --seed=1337 --view-alt=3 --view-pitch=8 --hour=12`: a red dwarf's
  forest is rust brown and near black, the Sun's is as before, an F star's is a little paler.
- **The user has not judged these colours.** The ground grass is still green under every star (step 7: the ground and
  sea colour have not been tied to the light yet). Not done: tidal locking (5), PAR and plant size (6, partly), UV
  and flares (8), the look table (9).
