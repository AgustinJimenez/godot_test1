#!/bin/bash
# Bakes the boulder in the square scene and prints how its height compares with the photograph's (tools/bark/measure_boulder.py).
cd "$(dirname "$0")/../.."
S=${TMPDIR:-/tmp}/boulder_bake.png
"/e/Godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe" --path . res://tests/manual/world/square_compare.tscn -- --surface=9 --shot="${S%.png}_shot.png" --save-bake="$S" > /dev/null 2>&1
/e/anaconda3/python.exe tools/bark/measure_boulder.py tools/bark/bark_downloads/rock_boulder_dry_disp.png "$S" 180 2>&1 | grep -v -i warn
