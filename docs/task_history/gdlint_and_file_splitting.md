# gdlint setup and splitting the two oversized files

## Background

`character_editor.gd` had grown to 3293 lines over several sessions of
feature work (see `character_editor_import_feature.md`). The user asked
whether a linter should be added, then asked to fix every finding it
reported - including the two `max-file-lines` (1000) violations
(`character_editor.gd` at 3293, `player_body.gd` at ~1016), which meant
actually splitting both files, not just reformatting.

## gdlint setup

Installed `gdtoolkit` (`pip3 install gdtoolkit --break-system-packages`),
added `.gdlintrc` at the repo root. The default config's
`class-definitions-order` rule was disabled immediately: it wants a rigid
pub/private/`@onready` ordering this codebase doesn't follow (vars are
grouped by feature, not by that taxonomy), and it accounted for 155 of 212
initial findings - retrofitting it would have been pure churn with zero
bug-catching value. Also hit a real self-inflicted bug during setup: `gdlint
-d` dumps its default config to a file literally named `gdlintrc` (no
leading dot), which silently took precedence over the intended `.gdlintrc`
for a while (gdlint's lookup checks the undotted name first) - deleted the
stray file once found via `gdlint -v`'s config-path log line.

Baseline after disabling that one rule: 57 real findings (50 long lines, 3
trailing-whitespace, 2 over-6-return-statements, 2 over-1000-lines).

## Long lines, trailing whitespace, return-count fixes

Mechanical, low-risk, done via direct `Edit` calls (not scripted) so each
change could be verified individually via `gdlint` + `godot --headless
--check-only --script` immediately after. `@onready var x = $Long/Node/Path`
lines were converted to `get_node(^"Long/Node/Path")` wrapped across two
lines - functionally identical (`$Path` is sugar for
`get_node(NodePath("Path"))`), verified via a live import (Ch28) after the
change to confirm the tool still worked end-to-end, not just that it parsed.

The two over-6-return functions (`_get_bone_section`,
`_on_mcp_debugger_message` in `character_editor.gd`) were restructured to a
single accumulator variable / `match` fallthrough pattern respectively,
preserving exact branching behavior - verified live via the MCP bridge
(multiple different dispatch cases exercised) rather than trusting the
read-through alone.

## Splitting character_editor.gd: two real dead ends before the working approach

### Attempt 1: mechanical function-chunking script had a boundary bug that lost content

First cut: parse the file into per-function chunks (each function's own
`##` doc comment + body) via regex, redistribute into 9 files grouped by
concern (import, MCP/automation, pose I/O, UI setup, bone controls, camera,
gizmo interaction, a pure-geometry utility, and a leaf file), joined by an
inheritance chain (`extends "res://.../parent.gd"`).

The chunk-boundary formula was wrong: chunk N's end was computed as chunk
N+1's `func` line position, which _included_ chunk N+1's own leading doc
comment as chunk N's trailing content - while chunk N+1 also captured that
same comment as its own leading content (comment-walk logic, correct in
isolation). Every function's doc comment ended up duplicated across two
files. A same-file "collapse adjacent duplicate blocks" patch fixed the
easy, same-file cases; a second "trim trailing blank/comment-only lines"
patch, applied on top without re-deriving correct boundaries, **actually
deleted** several functions' real doc comments outright (not just
duplicates) - confirmed by diffing specific functions against the original
and finding comments simply gone, not just doubled.

**Recovered via full revert** (`git checkout` back to the last commit,
delete every new split file, redo the small number of edits made since that
commit - documented above - by hand from the conversation's own record of
what those edits were), not by trying to patch the corruption further. A
scratch copy of the known-good pre-split file was saved before the second
split attempt specifically so this recovery path would be available without
redoing manual edits from scratch again.

**Lesson**: a "does the round-trip reconstruct the original exactly"
verification (concatenate all output chunks in order, diff against the
input) should have been the very first check run, before writing anything
to the real file - it would have caught the boundary bug in seconds. It was
added only for the second attempt (see below) and worked immediately.

### Attempt 2: inheritance chain is structurally impossible for this file

Re-derived chunk boundaries correctly this time (`chunk_i = [cstart_i,
cstart_{i+1})`, verified via an exact round-trip reconstruction test before
any file was written) and rebuilt the same 9-file inheritance-chain split.
It parsed and lint-passed, but systematically checking every function's
body for calls to functions assigned to a *later* file in the chain (a
"forward reference" a base class cannot make to a derived class) found 76
violations - and critically, several are **circular**: `_setup_controls`
(assigned to a "UI setup" base file) calls `_load_character` (assigned to
the leaf file), but `_load_character` itself calls back into UI setup, bone
controls, camera, and pose I/O code. There is no linear ordering of these
groups that satisfies every dependency - the function call graph is a
genuinely interconnected web, not a layered hierarchy, which is exactly why
this was one file in the first place.

**Reverted again** (same scratch-copy restore) rather than attempt to
reorder groups to eliminate cycles, since the cycles are inherent to how
this UI tool's concerns actually collaborate (character loading legitimately
needs to touch every subsystem, and vice versa) - no regrouping removes
them.

### What worked: composition, not inheritance

Same 9-way grouping, but each non-leaf group became a `RefCounted` "handler"
component holding `var editor: CharacterEditor` (a back-reference to the
main node), instantiated in `_ready()` and stored as a field on the main
script (`_mcp_handler`, `_import_handler`, `_pose_io_handler`,
`_ui_setup_handler`, `_bone_controls_handler`, `_camera_handler`,
`_gizmo_handler`). Composition has no ordering constraint - any component
can call back into the owner, and through the owner, into any other
component - so the circular dependencies that killed the inheritance
approach are simply not a problem here.

This required rewriting every internal reference inside each moved
function: bare member-variable access (`camera.position`) becomes
`editor.camera.position`, calls to functions that stayed on a different
component become `editor.<field>.<name>(...)`, calls within the same
component stay bare. Did this safely by:

1. Extracting the complete set of 163 owner member names (`@onready var`/
   `var`/`const`) and the 162 function names.
2. Checking for name collisions between those and every function's own
   local variables/parameters (**zero found** - this is what made blind,
   non-scope-aware text substitution safe at all; a single collision would
   have required real per-scope shadowing logic instead).
3. Building a string/comment-aware text replacer (tracks `"..."`/`'...'`
   literals and `#` comments as protected regions) before doing any
   identifier substitution - a naive whole-file regex replace would have
   corrupted status strings that happen to contain words like "body" or
   "camera" as plain English (`"Full body"`, `"Restore panel"`, `"move the
   camera"` all exist verbatim in this file).
4. Relying on GDScript's own static type-checking as a safety net: with the
   back-reference properly typed as `CharacterEditor` (not `Object`/`Node`),
   any missed or wrongly-targeted reference surfaces as a **parse error**
   (`Identifier not declared`, `Function not found in base self`), not a
   silent bug - `godot --headless --check-only --script` on every generated
   file caught real, fixable mistakes this way: missing `editor.` prefixes
   on `get_viewport()`/`get_tree()`/`get_window()`/`add_child()`/etc.
   (Node-only built-ins, invalid on a `RefCounted` component), and a missed
   `enum ImportMode` (not captured by the "member" scan, which only looked
   for `var`/`const`).

Verified end-to-end via the live MCP bridge, not just parse-checks: imported
Ch28 through the new import handler (screenshot confirmed correct
materials), triggered the exact "Reset Camera View" action that caused Bug
9 (confirmed still fixed), and triggered "Reset All" via a temporary
diagnostic hook on Player (confirmed the Bug 8 fix - no giant flashlight -
still holds). One round of "every live command times out" during testing
turned out to be the same pre-existing stale-debugger-connection flakiness
noted elsewhere in this project's history, not a bug in the split - a fresh
stop/play cycle resolved it, confirmed before spending more effort chasing
a phantom regression.

Result: `character_editor.gd` 3293 -> 813 lines, plus 9 new files (7
handler components + 1 static geometry utility + 1 material-fixup utility
extracted earlier the same session), every one under 1000 lines.

## Splitting player_body.gd

Much smaller scope - only 16 lines over the limit, and this file is real
gameplay code (the hardened UAL retargeting system), not an editor tool, so
the priority was the smallest safe cut rather than a full restructuring.
Extracted 7 genuinely pure functions (only read their parameters, no
`self`/node state) - `_solve_fabrik`, `_manual_global_pose`,
`_swing_between`, `_skeleton_height`, `_skeleton_rest_facing`,
`_set_latest_rotation_key`, `_bake_held_track` - into a new static utility,
`player_body_pose_math.gd`. `_aim_bone_at_direction`, which uses these but
also reads `self.skeleton` directly, stayed in `player_body.gd` with its
internal calls updated to the `PlayerBodyPoseMath.` prefix.

`tools/character_editor/humanoid_retargeter.gd` already has its own
separate copies of several of these same functions, and its doc comment
explicitly says this duplication is intentional ("do not merge back into
player_body.gd") so nothing there can ever regress the gameplay-critical
player rig. Confirmed neither file references the other's copies before
extracting - the new `player_body_pose_math.gd` is a third, independent
file, so this extraction doesn't violate that boundary.

Verified via the live character editor: loading Player exercises
`_ready()`'s eager retarget bake for every gameplay clip through the moved
functions - if any had an error, `set_live_character: player` would have
failed outright, not just for one clip. It succeeded, and walk and deep
crouch-walk poses were screenshotted and visually confirmed correct (natural
arm swing, properly bent knees, no T-pose collapse or flailing limbs - the
exact failure mode this retarget system had during its original
development, see `ual_animation_retargeting.md`).

Result: `player_body.gd` ~1016 -> 922 lines, plus `player_body_pose_math.gd`
(107 lines).

## Final state

`gdlint .` reports zero findings project-wide.
