# 052 - Graphics options for the planet

Status: **planned (2026-10-17)**. Follows [043](043_planet.md). Branch: `main` (it was `godot-4.7-upgrade` until 2026-10-20).
Read `docs/planet_lessons.md` first (how to measure, the traps).

## Goal

Let the player trade look for speed in the menu: render scale, shadow quality, tree and plant distance,
cloud quality, plant density, and presets that mean something on the planet.

## Where we are

- `components/graphics_settings.gd` is a project-wide service with presets (Low, Medium, High, Ultra,
  Custom): render scale, anti-aliasing (off, FXAA, SMAA, TAA, MSAA), shadow quality (off to high; sets the
  atlas size and the sun's shadow distance), SSAO, SSIL, glow, vsync, max fps; saved in `user://settings.cfg`.
- Project defaults set anisotropic filtering 8x, soft shadow filter 3 and debanding.
- The planet's distance constants are fixed in code: `TREE_FULL` 100 m, `TREE_LIGHT` 220 m,
  `SMALL_VISIBLE` 220 m, `GRASS_VISIBLE` 110 m, full plants within 256 m, `plant_density`, rock density;
  the planet sets its own sun shadow distance (220 m) and shadow mode, which can fight the service.
- The clouds march 6-16 steps; the sky radiance is 128 and realtime.

## Plan

1. **Make the constants settings.** A `PlanetQuality` resource (distance scale, plant density scale, tree
   detail on/off, cloud steps, sky radiance size, shadow distance) read by `PlanetScatter`, `PlanetSurface`,
   the cloud shaders (uniform) and `PlanetAtmosphere`.
2. **Presets.** Map the existing presets to planet values (Low: shorter ranges, no shadows beyond 60 m,
   fewer cloud steps; Ultra: longer ranges, all shadows). Show the numbers in the menu's "Custom".
3. **Planet page.** A "Graphics" block in the Planet page of the Esc menu with the planet-specific
   sliders; apply live where cheap, on reload where tiles must be rebuilt (the planet reloads the scene
   today for a new planet; a "rebuild plants" action may be enough).
4. **Auto-detect.** A first-run benchmark (a short fixed flythrough in the lab's way) that picks a preset
   from the measured fps; always overridable.
5. **Document** what each setting costs (use the measured numbers from 044 and 046).

## Done when

- Changing the preset changes draw calls and fps in the lab by the amounts written in the doc.
- The settings persist and survive the planet reload; nothing fights between the service and the planet.

## Risks and open questions

- Some settings change generated content (plant density) and must not change the planet itself (the
  same seed makes the same planet): density should only change what is drawn, not the dice.
