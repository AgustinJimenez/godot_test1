# 056 - Saves v3, menus and the way back in

Status: **planned (2026-10-17)**. Follows [043](043_planet.md). Branch: `main` (it was `godot-4.7-upgrade` until 2026-10-20).

**Part parked (user, 2026-10-17):** the player is not the focus now. Only the universe part (save the universe
settings, migrate v2) goes with [054](054_universe_foundation.md); the comfort items wait.
Read `docs/planet_lessons.md` first (how to measure, the traps).

## Goal

Make saving and opening comfortable: save from anywhere, continue where you were, see what a save is,
and keep old saves working.

## Where we are

- `UniverseSave`: JSON files in `user://universes/` (v2: planets list, current planet, moment: place,
  heading in the planet's frame, clock, time speed, forced weather); v1 saves (`user://planets/`) are
  still read. The player is put on the ground at the saved place (height is not saved).
- `UniverseStartMenu` (saved universes with Open and Delete, new universe by seed and radius, quick
  start) shows when the lab starts with no arguments or from "Main menu"; the Planet page has Save here,
  a list, Open, Delete.
- There is no auto-save, no "Continue", no rename, no confirm on delete, no thumbnail, no version
  check beyond reading the fields it knows.

## Plan

1. **Continue.** A top button "Continue" opens the newest save (it exists as `--continue` in the lab);
   remember the last one even if there are no saves (a quick start).
2. **Auto-save.** Every N minutes and when leaving to the menu or quitting, into a rotating `autosave`
   slot (never over a named save), with the time written; keep the last 3.
3. **Thumbnails.** A small screenshot saved next to each save (a PNG in the same folder) and shown in the
   list with the date, play time, the planet's name, the place's biome and the hour.
4. **Rename, duplicate, confirm delete.**
5. **Fidelity.** Save the height and whether the player was flying or swimming; restore them (a short
   hold at the place; see [045](045_landing_and_fast_descent.md)); save the inventory and health when the
   game has them (the player scene has them).
6. **Format.** Version the file; write a migration list (v1 to v2 exists); refuse a newer version with a
   clear message instead of misreading it; store as a text file so it can be read and diffed.
7. **Universe.** When [054](054_universe_foundation.md) lands: universe settings and a per-planet state
   (each planet keeps its own clock state and weather; the universe keeps the time).
8. **Check.** Extend `SAVE_CHECK`: a rename, a duplicate, a v1 file, a corrupt file (must not crash).

## Done when

- Quit and reopen: "Continue" puts the player back where they were, within a few metres, same hour and
  weather; a corrupt save shows an error and does not break the menu.

## Risks and open questions

- Where saves live: `user://` is per project name (`SurvivalHorrorFps`); say so in the menu ("Open folder").
