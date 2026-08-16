# Foot IK: how our implementation compares to real-world systems

Written 2026-08-15 after many sessions of stair foot-IK work with persistent, hard-to-kill
bugs (swing-phase tread penetration, toe clipping while turning in place on stairs, a long
history of fix-one-thing/break-another cycles). The project owner asked for an honest,
researched comparison against how other engines, libraries, and shipped games actually solve
this problem — not more iteration on the current design without stepping back first. This
document is that comparison. Nothing in this document was implemented; it's a research
writeup only.

## What we built, in one paragraph

`PlayerFootIKModifier` (a `SkeletonModifier3D`) runs every physics tick and, for each leg:
raycasts straight down from the animated foot to find the ground, closed-form-solves a
two-bone hip/knee/ankle IK toward that point, and blends the corrected pose against the raw
animated pose using a weight computed from the *animated* foot's own measured vertical
velocity (a proxy for "is this foot mid-swing or planted"). A `foot_ik_gait_tracker.gd`
owns that velocity/weight state machine (rising/falling streaks, idle-freeze, landing
events). A `foot_ik_stair_predictor.gd` adds stair-specific behavior on top: it
forward-raycasts ahead of a swinging foot to predict which tread it's about to land on and
adds a lift height to clear the riser, and it runs a "support leg" state machine that locks
one foot's target while the other swings. When a leg's target is farther than its physical
reach allows, a shared `shared_drop` value sinks the *whole pelvis* (both legs' common
ancestor bone) so the constrained leg can still reach — asymmetric engage/release rates were
added later to stop that sink from popping visibly. There is exactly one authored walk cycle
and one idle cycle; stairs are not represented in animation data at all, only in the IK
correction layered on top of them. Across `player_foot_ik_modifier.gd` (~1000 lines, at the
configured lint ceiling), `foot_ik_gait_tracker.gd` (~570 lines), `foot_ik_stair_predictor.gd`
(~510 lines), and `foot_ik_ground_sampler.gd`/`foot_ik_leg_solver.gd`, this is roughly
3,000+ lines dedicated entirely to foot placement.

## What real implementations actually do

### 1. Reference open-source samples

**ozz-animation's foot IK sample** ([guillaumeblanc.github.io/ozz-animation/samples/foot_ik](https://guillaumeblanc.github.io/ozz-animation/samples/foot_ik/))
is the closest thing to a canonical, engine-agnostic reference implementation (ozz-animation
is a well-regarded open-source C++ runtime animation library). Its technique matches our
foundation closely: raycast down from the ankle, closed-form two-bone IK with the original
knee-forward vector as the pole (same idea as our explicit "down + forward reference"
basis), and aim-IK to align the foot to the surface normal. For the pelvis, it does the
simplest possible thing: shift the whole character down until "the lowest ankle reaches its
targeted position," letting IK bend the other leg to compensate — no reach-limit trig, no
asymmetric rates. Critically, **the sample's own documentation admits it is incomplete**:
it explicitly does not handle "not reachable foot positions: too high, too low, too steep"
or blending when a foot leaves the ground. In other words, even the reference
implementation punts on exactly the two hardest problems we've spent the most effort on
(reachability, swing/stance blending) — this is a genuinely hard problem, not a sign we're
uniquely incompetent at it, but it also means we picked the least-precedented, least-battle-tested part of the problem to build the most machinery around.

**SeaKrill/Godot-Foot-IK** ([github.com/SeaKrill/Godot-Foot-IK](https://github.com/SeaKrill/Godot-Foot-IK))
is a small Godot-specific sample, read in full (`scripts/player.gd`, `scripts/target.gd`,
~70 lines total for the whole system). It uses Godot's built-in `SkeletonIK3D` node
directly rather than a custom two-bone solver, a `Marker3D` + `RayCast3D` per foot whose Y
position is set to the raycast hit each physics tick, and a *single-line* swing/stance
heuristic: `foot.interpolation = lerp(foot.interpolation, (bone_rotation_snapped ? 1 : 0), 0.15)`.
No pelvis adjustment at all. No reach-limit handling. No stair-specific logic of any kind —
stairs are just "uneven ground" to it, handled (or not) exactly like a rock. This is a toy
sample, not production code, but it's revealing that the most-found Godot-specific foot IK
reference doesn't attempt anything close to what we built.

### 2. A commercial, shipped-in-real-games system: Unity's Final IK

This is the strongest data point. Final IK (RootMotion) is a paid, widely-used Unity asset
shipped in a large number of released commercial games. Its source leaked into a public fan
project repo (`DoYouEven/IceAge-Unity`), letting us read the actual production code rather
than marketing copy:
[`Grounder/Grounding.cs`](https://raw.githubusercontent.com/DoYouEven/IceAge-Unity/master/Assets/RootMotion/FinalIK/Grounder/Grounding.cs),
[`GroundingLeg.cs`](https://raw.githubusercontent.com/DoYouEven/IceAge-Unity/master/Assets/RootMotion/FinalIK/Grounder/GroundingLeg.cs),
[`GroundingPelvis.cs`](https://raw.githubusercontent.com/DoYouEven/IceAge-Unity/master/Assets/RootMotion/FinalIK/Grounder/GroundingPelvis.cs),
[`GrounderIK.cs`](https://raw.githubusercontent.com/DoYouEven/IceAge-Unity/master/Assets/RootMotion/FinalIK/Grounder/GrounderIK.cs).

What it actually does, confirmed by reading the code directly:
- **Pelvis offset is a one-line sum**: `lowestOffset` and `highestOffset` are tracked across
  all legs (just `if (leg.IKOffset > lowestOffset) lowestOffset = leg.IKOffset;` and the
  mirror for highest), and the pelvis target is `lowestOffset + highestOffset`, smoothed
  with a plain `Mathf.Lerp(heightOffset, offsetTarget, deltaTime * pelvisSpeed)`. No
  reach-limit trigonometry. No per-leg horizontal-distance-aware max-vertical-diff
  calculation like ours. No asymmetric engage/release rate — the same lerp speed applies
  both directions, plus a separate velocity-damping term to reduce bob from root motion.
- **No reach-limit / leg-length validation anywhere.** The closest thing is
  `maxStep - legHeight` clamped to `[0, maxStep]` — a flat vertical-displacement budget, not
  a kinematic "can this leg physically reach this point" check.
- **No swing-vs-stance distinction in the leg or pelvis code at all.** `isGrounded` is set
  from `heightFromGround < maxStep` but is never read to change behavior between a planted
  and swinging leg — there is no equivalent of our gait tracker's velocity-based weight
  state machine.
- **No stair-specific logic whatsoever.** Stairs get zero special-case code; they're
  handled by the same per-foot raycast as any other surface, with `maxStep` as the only
  limiter on how big a single correction can be.
- **Total size**: the whole grounding system across all five files is roughly 700-800
  lines, covering bipeds *and* quadrupeds *and* multiple solver-quality tiers (1-2 raycasts
  per foot depending on quality mode). Our biped-only stair system alone is already larger
  than that.

This is the single most important finding in this review: a commercial product used in many
shipped games solves this problem with dramatically less machinery than we built, and
explicitly does **not** attempt reach-limit correctness or swing/stance-aware pelvis
negotiation — the exact two things that have consumed the most engineering effort and
produced the most fragility in our system.

### 3. A blog walkthrough with an explicit warning that matches our exact failure mode

[AnimMotion: Foot Placement Using Foot IK](http://peyman-mass.blogspot.com/2015/06/foot-placement-using-foot-ik.html)
describes a pelvis-offset system very close in spirit to ours (offset proportional to the
gap between detected ground and max leg length, with a min-leg-length floor). But the
author adds an explicit, direct warning:

> pelvis adjustment should only activate in stationary situations like idle animations...
> having a stretched leg in running or in many combat animations is common [and accepted]

This is close to the inverse of what we've been trying to do. Our `shared_drop` mechanism
runs *continuously during active stair walking* — the single hardest case to get right,
per this author's own explicit advice — while this blog's author restricts the same kind
of correction to idle/stationary poses specifically, and simply accepts a visibly stretched
leg during locomotion as a tolerated cosmetic tradeoff rather than something to solve.

### 4. How stairs specifically are handled: authored motion + light IK, not raycast-driven leg reach

Multiple sources converge on the same pipeline, described most concretely in a devlog for
a shipped parkour game (*Tricking*, a real released title, described via a public
[TikTok devlog](https://www.tiktok.com/@tricking.videogame/video/7493202383091092758)):
"I searched for animations for ascending and descending stairs... [then] redesigned my
raycast system so the player could understand their environment... The goal was to
seamlessly blend into the right animation when moving up or down a slope." IK is then
applied as a *secondary* correction pass on top of that already-appropriate stair
animation — locking a grounded foot, releasing it smoothly, and offsetting vertically only
for the residual gap between the animation and the actual geometry, not for the whole
climb.

This "author the base motion for the terrain, use IK only for the last few centimeters"
split is echoed by general summaries of AAA practice: "layering procedural on top of
keyframe is probably the most common setup in AAA games right now" — i.e. procedural IK is
consistently described as a *correction pass*, not the primary mechanism generating the
climbing motion.

Our project has exactly one flat-ground-authored `moves/unarmed_walk` clip and asks IK to
account for the *entire* height of every step, every time, continuously, for the whole
climb — not a residual few centimeters. That is a structurally harder version of the
problem than what any source above describes solving with pure IK.

### 5. When professional teams *did* build something closer to our ambition, they used a different, more general architecture

Ubisoft's "IK Rig: Procedural Pose Animation" (GDC 2016, Alexander Bereznyak — summarized at
[gameanim.com](https://www.gameanim.com/2018/02/03/ik-rig-procedural-pose-animation/) and
[GDC Vault](https://gdcvault.com/play/1022984/IK-Rig-Procedural-Pose)) explicitly names
"walking up the stairs" as a real motivating example for exactly the kind of combinatorial
problem we're fighting (the set of *needed* motion combinations grows exponentially while
authored clips grow linearly). Their answer wasn't a stack of raycast/gait-tracker/
predictor heuristics bolted onto a single walk cycle — it's a general procedural
pose-retargeting layer that treats "adapt this motion to this terrain" as a first-class,
reusable transform, applied uniformly rather than as terrain-specific special-case code.
This suggests that when a studio takes "arbitrary terrain adaptation" as seriously as our
project has ended up needing to, the answer people converge on is a more general, more
disciplined retargeting architecture — not more special cases layered onto a foot-plant
raycast system.

## Where we match common practice, and where we diverge

- **Raycast-down + two-bone IK + pole vector from a rest-pose reference, not the animated
  pose.** Matches ozz-animation's technique almost exactly, including the specific reason
  (avoiding a singularity/instability in the animated forward vector). This part of our
  system is solid and not a likely source of the fragility.
- **Blending IK correction against the raw animated pose with a weight, rather than always
  applying it at full strength.** Matches the general "IK as a post-process/correction
  layer" framing found everywhere in the research. Reasonable.
- **Shared pelvis offset when a leg can't reach.** The *concept* matches Final IK, the UE4
  marketplace "2 Bone IK Foot Placement System," and the AnimMotion blog exactly — this
  part of the architecture is not unusual. **The divergence is in how much more we do with
  it**: reach-limit trigonometry per leg, asymmetric engage/release rates, and — as of
  tonight — swing-lift compensation for the pelvis sink specifically. None of the reference
  implementations found do any of this; Final IK's version is a one-line sum with a single
  symmetric lerp rate. This looks like a likely root cause of fragility: we've been tuning
  an increasingly precise, increasingly special-cased version of a mechanism that
  real, shipped systems deliberately keep simple and imprecise.
- **Swing-vs-stance gait tracking from measured animated velocity.** We found **no
  precedent** for this in any source reviewed. Final IK doesn't do it. The ozz-animation
  sample doesn't do it. The Godot sample doesn't do it. This appears to be a genuinely
  novel piece of machinery specific to this project, built to solve a problem (don't
  correct a foot that's legitimately mid-swing) that other systems either don't solve at
  all (Final IK just always corrects, relying on `maxStep` to bound the damage) or solve
  with something much cruder (the Godot sample's single-line rotation-snap heuristic). This
  is very likely a major source of the "freeze/unfreeze streak," "void-dangle," and
  "twice-per-tick phantom call" classes of bugs documented at length in this project's
  `AGENTS.md` — an entire velocity-based state machine that doesn't have a clear precedent
  to validate against.
- **Stair-specific predictive swing-lift and support-leg transfer state machine.** **No
  precedent found anywhere.** Every source that specifically discusses stairs converges on
  "use a stair-appropriate authored animation, correct residually with IK" rather than
  "predict the next tread and computationally lift a flat-ground swing trajectory over
  it." This is the single most structurally different piece of our system compared to
  everything found in this research, and it's also the part responsible for tonight's
  bugs (swing-phase penetration, the toe-clip-while-turning issue) and the deepest, most
  failure-prone code (`foot_ik_stair_predictor.gd`'s support-transfer/latch logic, which
  has its own long history of "released and instantly re-latched, producing drift" bugs
  documented in `AGENTS.md`).
- **One authored walk cycle asked to cover flat ground and every stair height.** This is
  the deepest divergence from everything found in this research. Every source that
  specifically addresses stairs (the Tricking devlog, the "hybrid AAA" summaries, Ubisoft's
  IK Rig framing of "walking up the stairs" as a hard combinatorial case worth its own
  architecture) treats stair motion as something that needs *some* dedicated authored or
  procedurally-generated base motion, with IK doing only the last-mile correction. Nothing
  found in this research tries to make a single flat-ground clip, corrected purely by
  raycast/IK, carry the *entire* vertical climb of a staircase. This is very plausibly the
  actual root architectural mismatch: everything downstream (the predictor, the freeze
  logic, shared_drop tuning, the swing-lift/pelvis-sink interaction bug found tonight) is
  effort spent making IK do a job that, everywhere else it's been solved well, isn't IK's
  job in the first place.

## Bottom line

**The core two-bone-IK-plus-raycast foundation is sound and matches established practice.**
The fragility is concentrated in the *stair-specific* layer built on top of it, and that
layer is structurally more ambitious than anything found in a real, shipped, or reference
implementation. Specifically:

1. Nothing found in this research asks pure procedural IK to carry a character up an entire
   staircase using only a flat-ground walk cycle as its base. Every real precedent uses
   some form of stair-appropriate base motion (authored clips, blended/retargeted poses, or
   at minimum a slope-aware animation blend) and reserves IK for a small residual
   correction — not for lifting a leg the full height of every step.
2. The parts of our system with no precedent anywhere in this research — the velocity-based
   swing/stance gait tracker, the predictive next-tread swing lift, and the support-leg
   transfer state machine — are also the parts most implicated in this project's own bug
   history (freeze/unfreeze regressions, support-latch drift, tonight's swing-lift/
   pelvis-sink interaction, the turn-in-place clipping that couldn't be fixed without
   breaking a different passing test). That's a strong correlation between "code with no
   external validation to check our intuitions against" and "code that keeps breaking."
3. Even the most sophisticated reference found (a commercial product used in shipped
   games) keeps its reach-limit and pelvis-offset logic dramatically simpler than ours, and
   a blog author with real experience explicitly warns against doing continuous pelvis
   correction during locomotion at all — the opposite of what our system attempts.

This isn't "you've been doing IK wrong" — the fundamentals (raycast, two-bone solve, pole
vector, weighted blend, shared pelvis concept) all check out against real systems. It's
closer to: **the project set out to solve a harder version of the stairs problem than
professional systems typically attempt, using only IK and no stair-specific base motion,
and the resulting complexity (freeze streaks, void-dangle, support transfer, swing
prediction, asymmetric pelvis rates) is the direct, structural cost of that choice** — not
a sign of bad IK technique, but a sign the project picked the hard, uncommon path for this
specific sub-problem.

## A concretely scoped alternative (research only — not implemented)

If a future session wants to act on this finding, the shape suggested by this research is:

1. **Author or generate a dedicated stair-walk base motion** instead of using the flat
   walk cycle. This does not have to be hand-animated from scratch: a simpler procedural
   option consistent with what was found here is a *stride-length/height-aware retarget* of
   the existing walk cycle onto the known, discrete tread height/depth of the current
   staircase (the game already knows tread height/depth exactly, since it's building the
   collision geometry) — closer in spirit to Ubisoft's "IK Rig" framing (adapt a motion to
   new geometry as a first-class transform) than to raycast-and-correct.
2. **Demote the current IK layer to a residual correction pass**, matching Final IK's level
   of ambition: raycast per foot, a single unconditional pelvis offset (sum of extremes,
   symmetric lerp, no reach-limit trig, `maxStep`-style clamp), no swing/stance state
   machine. If the base motion is already roughly right for the stair height, the IK layer
   doesn't need to do more than that — the whole reason ours needs the sophisticated
   version is that it's currently being asked to do 100% of the climbing work instead of
   the last few centimeters.
3. **Retire the predictive swing-lift/support-transfer system** once a stair-aware base
   motion exists — it exists specifically to compensate for the flat walk cycle not
   knowing about the stairs, which won't be true anymore.
4. **Keep the parts validated by this research**: two-bone solve with rest-pose pole
   vector, raycast-down ground sampling, weighted blend against animation. Those don't need
   to change.

This would be a genuine architecture change (new or generated animation data, a much
smaller and simpler `player_foot_ik_modifier.gd`), not a tuning pass — worth scoping as its
own planned milestone rather than another incremental fix, given how much of the current
complexity this research suggests would simply become unnecessary.

## Follow-up: how to actually build stair-aware base motion (2026-08-15)

The first pass established *that* real systems use stair-appropriate base motion instead
of pure IK, but not *how* to actually produce that motion. This pass went deeper
specifically on that question, plus audited Godot 4.6's own brand-new IK framework for
anything purpose-built for terrain adaptation that the first pass didn't check.

### 1. Unreal's Motion Warping / Pose Warping — real, shipped, but not what we thought

[Epic's official docs](https://dev.epicgames.com/documentation/en-us/unreal-engine/motion-warping-in-unreal-engine)
confirm Motion Warping (the older, more mature feature) works by **modifying the root
motion curve itself**: an animation's translation/rotation curves are stored per-frame,
sampled and diffed each tick to drive the character; "Skew Warp" adjusts that curve so
it lands on a runtime-supplied target transform by the end of an authored warp window
(an Anim Notify State marks which stretch of the timeline is warpable). The exact
per-frame skew math isn't published, but the shape is clear: **it needs root motion**,
which this project doesn't use for the walk cycle at all (`HumanoidActor._make_clip_in_place()`
already strips hip translation — see `AGENTS.md`), so Motion Warping's specific technique
doesn't transfer directly without first re-adding root motion to the walk clip.

More interesting: [Unreal 5.7/5.8's newer "Pose Warping"](https://dev.epicgames.com/documentation/unreal-engine/pose-warping-in-unreal-engine)
system has a node literally named **Slope Warping**, whose stated purpose is "warping
feet locations to match the floor normals, to create smoother transitions of locomotion
animations on inclines and **stairs**" — i.e. Epic is building the exact feature this
project needs. Two things temper that: (1) it's IK-based (drives IK foot bones, feeds
back to FK, needs a defined IK Rig — architecturally close to what we already have, not
a fundamentally different technique), and (2) **Epic's own docs mark it "still in
development,"** not recommended for production. A companion node, **Stride Warping**,
needs the full leg bone chain plus the pelvis bone declared, and exposes
`PelvisAdjustmentMaxIter` — an iterative pelvis solver, more sophisticated than our
single-pass reach-limit sink or the new `foot_ik_residual_corrector.gd`'s one-line sum,
but conceptually the same family of problem (converge the pelvis height so all legs stay
in reach), not a different paradigm.
**Takeaway: even Epic, with far more engineering resources, doesn't consider pure
IK-based stair adaptation a solved, shippable problem yet.** That's not license to keep
building more IK machinery — it's confirmation the IK-only approach is inherently hard,
which strengthens (not weakens) the first pass's recommendation to lean on base motion
instead.

### 2. ALS-Refactored (community-scale precedent) — delegates rather than hand-rolls

[ALS-Refactored](https://github.com/Sixze/ALS-Refactored) is a free, open-source,
widely-used Unreal locomotion framework built and maintained by a small community team —
a much closer scale match to this project than Ubisoft or Naughty Dog. Its changelog
explicitly claims "reworked foot and pelvis offset logic for smoother movement...on
stairs and sloped surfaces" with "spring interpolation for foot and pelvis offsets."
Reading the actual `AlsAnimationInstance.cpp` source directly: the C++ layer only handles
**foot locking** (freezing a planted foot's world position via a plain
`FMath::Lerp(TargetLocation, LockLocation, LockAmount)` — no spring, no height sampling).
The actual ground-height IK and pelvis offset math is **not in C++ at all** — it's
implemented in a Control Rig graph (`GetControlRigInput()` just passes foot socket
locations downstream). **Even this respected community project chose not to hand-roll a
custom gait/pelvis state machine** — it composes the engine's own IK tooling instead,
the same lesson as the Final IK finding in the first pass, from an indie-scale project
this time rather than a commercial asset.

### 3. A genuinely different, well-precedented algorithm: Ken Perlin's phase-shift + blurred-height technique

This is the most concrete, actionable find of this pass.
[US Patent 9,978,169](https://patents.google.com/patent/US9978169B2/en) (Ken Perlin —
the Perlin noise creator, a foundational figure in real-time procedural character
animation) describes a technique that solves stairs **without raycasting under a
possibly-swinging foot every frame at all** — sidestepping this project's entire
swing/stance classification problem structurally rather than tuning around it:

- **Feet only sample ground height at touchdown, not continuously.** "The floor height
  at each foot is only evaluated at places where that foot touches down; that is, where
  the phase of the walk cycle is a multiple of 0.5 cycles." There is no swing-vs-stance
  detection to get wrong, because the algorithm never asks the question mid-swing.
- **Footfalls are phase-shifted to land at tread centers, not at whatever point the
  raw cycle would naturally place them.** "The walk-cycle phase at each keyframe is
  adjusted slightly, so that each...touchdown...is shifted to the center of a stair
  step," with "preparation...started for the step up or down two keyframes ahead" and
  the shift kept local — "the original walk cycle phase is restored after a small number
  of additional keyframes," so it can't drift the rest of the animation's timing. This is
  conceptually a lightweight **playback-speed/phase modulation** driven by upcoming tread
  proximity, not a new animation asset.
- **Pelvis height is computed by blurring the terrain height function (a MIPmap in the
  patent's implementation) instead of tracking a hard reach limit.** "The higher the
  pelvis, the blurrier is the effective height function" — i.e. the pelvis smoothly
  averages over nearby tread-height changes rather than snapping to satisfy an instantaneous
  per-leg reach constraint. This directly replaces the entire `shared_drop`/reach-limit-trig/
  asymmetric-rate mechanism with a single smoothing/filtering step over a height field the
  game already has (tread geometry).

This is not vague industry folklore — it's a specific, citable, implementable algorithm
from a credible source, and it structurally eliminates two of the three biggest sources
of this project's bug history (swing/stance misclassification, reach-limit pelvis
fighting between legs) rather than papering over them with more special-casing.

### 4. The low-tech alternative worth trying first: a stair blend space

Separately, and much cheaper to try: [Game Developer's animation-blending piece](https://www.gamedeveloper.com/programming/animation-blending-achieving-inverse-kinematics-and-more)
describes the standard, decades-old technique of authoring a small set of clips (e.g.
walk-flat, walk-uphill, walk-downhill) and blending between them in a 1D/2D blend space
keyed by slope/step angle — no IK at all for the base motion, just interpolated poses.
Godot's `AnimationTree` already has native `BlendSpace1D`/`BlendSpace2D` nodes for exactly
this, unused anywhere in this project currently. For a project with only one authored
walk cycle, the cheapest experiment isn't Perlin's algorithm (which needs a phase-shift
implementation) or a from-scratch generator — it's determining whether even 2-3 additional
hand-posed or lightly-retargeted "on a slope/step" key poses, blended by the already-known
tread rise/run via a small `BlendSpace1D`, gets closer to acceptable than either the current
system or the bare `RESIDUAL_STAIR` corrector, before investing in phase-shift machinery.

### 5. Godot 4.6's new IK framework — audited specifically, no terrain-adaptation node exists

Confirmed directly (not assumed) via the framework's own announcement and documentation:
[Godot 4.6 added `IKModifier3D`](https://godotengine.org/article/inverse-kinematics-returns-to-godot-4-6/)
with seven solver children — `TwoBoneIK3D`, `ChainIK3D`, `SplineIK3D`, `IterateIK3D`,
`FABRIK3D`, `CCDIK3D`, `JacobianIK3D` — plus the earlier `LookAtModifier3D`,
`RetargetModifier3D`, `SpringBoneSimulator3D`, `BoneConstraint3D`. **All of these are
generic solvers** (equivalent to what `foot_ik_leg_solver.gd` already hand-rolls as a
closed-form two-bone solve), not a "warp this pose/animation to this terrain" node —
Godot has nothing resembling Unreal's Motion/Pose/Slope Warping. Two implications: (a)
there is no missed built-in shortcut for the terrain-adaptation problem itself, so
whatever we build (Perlin-style phase-shift, a blend space, or the demoted residual
corrector) has to be authored regardless; but (b) `TwoBoneIK3D` specifically is worth a
follow-up look as a drop-in replacement for `foot_ik_leg_solver.gd`'s hand-written
closed-form solve (a much smaller, separate, low-risk swap unrelated to the stair-motion
question — not pursued in this pass, flagged for later).

### Does this change the first pass's recommendation?

**Sharpens it rather than changing it.** The first pass said "use stair-appropriate base
motion, demote IK to residual correction" without a concrete algorithm for the first half.
This pass found one with real precedent (Perlin's phase-shift + blurred pelvis height)
that's a better fit for this project than either "author N stair-height clips" (impractical
for arbitrary rise/run) or "build a full procedural pose-retargeting layer" (Ubisoft's IK
Rig scale, too large for a solo project) — and confirmed via Unreal's own in-development
Slope/Stride Warping and ALS-Refactored's Control-Rig delegation that no one, at any scale,
considers pure per-frame-raycast IK a solved answer to this problem, which is direct,
independent corroboration of the first pass's core verdict. The single cheapest next
experiment, before any of that: try a small `BlendSpace1D` with 2-3 additional poses,
since Godot already has the node and this project already has the tread-height data to
drive it.

## Follow-up 2: hunting for real Perlin-style footstep IK code (2026-08-15)

**The trail goes cold — no real, working open-source code implementing Perlin's specific
patented technique (phase-locked touchdown sampling + blurred-height pelvis) was found.**
Being direct about this rather than padding it out:

- Searches for "Perlin procedural walking" are dominated entirely by **Perlin noise**
  (terrain/texture generation) results — a different, far more famous piece of Perlin's
  work that has nothing to do with character animation. None of those results (terrain
  generators, noise libraries) are relevant here.
- Perlin's own **Improv** system (NYU Media Research Lab,
  [mrl.cs.nyu.edu/projects/improv](https://mrl.cs.nyu.edu/projects/improv/), Perlin &
  Goldberg, SIGGRAPH 1996) is a real, documented, historically significant system, but
  it's a **behavior-scripting layer** (procedural noise driving *which* motions play and
  how they blend/layer), not specifically a footstep/terrain-height IK technique — the
  patent found in the first follow-up pass (US9978169B2) is the actual source for the
  touchdown-sampling/blurred-pelvis-height idea, and Improv's own materials don't add
  implementation detail for that specific piece. No surviving source code is published
  for Improv itself; it was commercialized (spun off as Improv Technologies in 1999) and
  the trail ends there.
- A different, unrelated patent family surfaced during this search —
  [US6191798B1 "Limb coordination system for interactive computer animation of
  articulated characters"](https://patents.google.com/patent/US6191798B1/en) (Handelman,
  Lane, Gullapalli; assignee Katrix, Inc., not Perlin) — describes a genuinely different
  terrain-adaptation idea worth noting even though it's off this pass's specific target:
  goal-directed "synergies" that transform all body motion relative to a live-designated
  contact point, so uneven terrain is handled by continuously redefining what point of
  the body is "the ground contact" rather than by height-sampling or blurring at all. No
  accessible source code for this one either (patent text only) and it's a different
  enough paradigm that porting it would be its own research question, not something to
  chase further in this pass.
- The one Godot-specific, terrain-adaptive procedural-walk project found (`2D Procedural
  IK Walk Demo`, source linked as
  [github.com/Moynilr/2D-procedural-walk](https://github.com/Moynilr/2D-procedural-walk))
  could not actually be inspected — its GitHub page doesn't render source in a fetchable
  form from here, only a README describing two variants ("full procedural" vs. a
  simpler/more robust "step solver"). It's also a 2D platformer project, so even if
  read, its technique may not transfer cleanly to this project's 3D biped. Worth a manual
  clone-and-read in a future session if this direction is pursued, but not confirmed
  useful here.

**Bottom line for this specific question: we would be implementing Perlin's technique
from the patent's own description (already extracted precisely in the prior "Follow-up"
section — phase-multiple-of-0.5 touchdown sampling, 2-keyframes-ahead local phase shift
to tread centers, blur-width-scales-with-pelvis-height terrain smoothing), not from
reference code, because none exists publicly for this specific technique.** That's
consistent with patents generally — they exist to claim an idea, not to ship a runnable
reference implementation, and Perlin's is a 2016-era patent (priority likely earlier)
describing what were, at the time, non-obvious techniques rather than open tooling. This
doesn't change the recommendation from either prior section: the patent's algorithm
description is precise enough to implement directly (exact phase-trigger condition,
exact keyframe-lookahead count, exact smoothing relationship) without needing source to
copy from, and the cheap `BlendSpace1D` experiment remains the lowest-risk thing to try
before committing to building the phase-shift machinery from scratch.

## Follow-up 3: real Godot 4.6 code found via GitHub's own code search (2026-08-15)

The user asked specifically whether GitHub's code search (as opposed to general web
search, which had gone cold) would surface more real code, the way it surfaced Final
IK's leaked source earlier. It did — two real, working, MIT-licensed Godot foot-IK
implementations, both using the same modern `SkeletonModifier3D` base class this project
uses, found via `gh search code "foot_ik" --language gdscript` and
`gh search code "GroundingLeg"` (which also turned up dozens more leaked Final IK
`GroundingLeg.cs` copies across other Unity game repos, corroborating how common that
leak is - not a one-off).

**[`blugart-dev/kickback`](https://github.com/blugart-dev/kickback)**
(`addons/kickback/foot_ik_solver.gd`, MIT, actively maintained - last updated 2026-08-13,
days before this research) is a physics-reaction character controller ("Euphoria-like
hit reactions") for Godot 4.6+ whose foot-IK component is ~330 lines total, read in
full. Two things stand out as directly relevant, independent confirmations of what the
earlier Final IK read already suggested:

- **Swing/stance weight is height-based, not velocity-based** - and specifically height
  *relative to the character's own root*, not absolute world height:
  ```gdscript
  var far := foot_l.origin.y - root_y
  if far < _tuning.foot_ik_swing_threshold:
      tw_l = clampf(1.0 - (far - plant_threshold) / (swing_threshold - plant_threshold), 0.0, 1.0)
  ```
  This directly contradicts our own code's justification for using velocity instead of
  height (`player_foot_ik_modifier.gd`'s comment: "Velocity-based, not height-based:
  height alone broke static standing on a tall stair tread"). The resolution is that
  *root-relative* height sidesteps that exact failure: standing still on a tall tread,
  the root has already risen to match, so `far` stays small regardless of the tread's
  absolute height - only genuine swing (foot rising away from a root that hasn't
  followed) produces a large `far`. Our velocity-based approach solves the same problem
  a structurally different way and needed the freeze streaks/rising-penalty/
  velocity-noise-floor machinery to handle noise that this height-relative formula
  doesn't appear to need at all.
- **One pelvis offset, not per-leg reach-limit trigonometry**, with an explicit
  "supported vs. not" concept that cleanly separates "this foot needs the pelvis to
  sink" from "this foot is over a void, ignore it" - conceptually the same problem our
  `void_dangle`/`shared_drop` machinery fights, solved in a few lines:
  ```gdscript
  var drop_l: float = (offset_l * _ik_weight_l) if supported_l else INF
  var drop_r: float = (offset_r * _ik_weight_r) if supported_r else INF
  var target_pelvis: float = clampf(minf(drop_l, drop_r), -max_pelvis_drop, 0.0) if minf(drop_l, drop_r) < INF else 0.0
  ```
  `supported_l`/`supported_r` is a one-line check (`raw_offset >= -max_pelvis_drop`) -
  a foot needing more drop than the budget allows is excluded from the pelvis
  calculation entirely (treated as a void, not chased), rather than needing a dedicated
  `void_dangle` code path.

**[`Star2578/godot-foot-ik`](https://github.com/Star2578/godot-foot-ik)** ("easy to use
Godot FootIK for version 4.3+") is a second, independent, non-ragdoll-context
implementation - a standalone `SkeletonModifier3D`-based addon, 696 lines total,
skimmed for its tuning surface. It corroborates the same two patterns from a completely
different author and use case: `foot_lifting_threshold` ("how high feet is off the
ground to disable IK" - height-based again, not velocity) and a single `hip_max_drop` +
`hip_smooth_speed` pair (one rate, not our asymmetric engage/release pair).

**Why this matters more than the Final IK read alone:** Final IK is a general-purpose,
engine-wide commercial product with its own reasons to stay generic and simple. These
two are small, single-purpose, modern (`SkeletonModifier3D`), Godot-native, and written
by people solving exactly our problem in exactly our engine version - and they
independently converged on the same two simplifications (root-relative height instead
of velocity for swing detection, one pelvis rate instead of reach-limit trig) without
citing each other or Final IK. That's a real, in-engine existence proof that our
velocity-based gait tracker and asymmetric shared-pelvis system are not the only way to
solve this in Godot 4.6, and that a *simpler* approach than even the just-built
`RESIDUAL_STAIR` mode (which still uses no swing detection at all) - specifically,
adding root-relative-height swing detection back in, rather than omitting it entirely -
may be a better-targeted middle ground than either extreme.

**`kickback` also ships a written architecture doc** (`docs/FOOT_IK.md`, fetched in
full) that names stairs explicitly, in its "Common Issues" troubleshooting section:

> **Pelvis drops too much on stairs:** Decrease `foot_ik_max_pelvis_drop`.

That is the entirety of their stairs-specific guidance - a single tuning parameter,
not a dedicated subsystem. Their doc also states the swing-detection rationale plainly:
"Using character root avoids false positives on slopes where the ground is at different
heights" - i.e. the root-relative-height trick isn't incidental, it's the documented
reason they don't need velocity tracking at all. Confirmed tuned defaults from the same
doc: `swing_threshold=0.25m`, `plant_threshold=0.17m` (root-relative height band),
`max_pelvis_drop=0.35m`, `pelvis_blend_speed=8.0`, `foot_blend_speed=10.0` - five numbers
covering what our system spends `shared_drop_release_rate`, `shared_drop_idle_engage_rate`,
`ground_weight_rise_time`, `ground_weight_fall_time`, `min_falling_streak`,
`velocity_noise_floor`, `rising_penalty`, `swing_speed_threshold`, `IDLE_FREEZE_STREAK`,
`IDLE_UNFREEZE_ROTATION_DEG`, `step_clearance_margin`, and more, to approximate.

This is the strongest single data point in this whole research pass: a real, modern,
working Godot 4.6 project's *complete* answer to "what about stairs" is one number in a
troubleshooting FAQ, not an architectural layer.
