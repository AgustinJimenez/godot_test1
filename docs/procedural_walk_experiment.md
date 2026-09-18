# Procedural walk experiment: findings and next steps

This is the focused record for the independent MotusMan walk prototype in
[`tests/manual/procedural_walk/procedural_walk_lab.tscn`](../tests/manual/procedural_walk/procedural_walk_lab.tscn).
For the broader Godot animation survey, see
[`PROCEDURAL_ANIMATION_RESEARCH.md`](PROCEDURAL_ANIMATION_RESEARCH.md). For the stair locomotion
decision and gameplay integration context, see
[`AGENT_TASKS/031_stair_locomotion_strategy.md`](../AGENT_TASKS/031_stair_locomotion_strategy.md).

## What exists now

The scene runs the MotusMan model with its imported relaxed-idle pose frozen as a base. A separate
`SkeletonModifier3D` generates the leg gait and small pelvis, spine, and arm motions. It does **not**
spawn `Player`, use gameplay Foot IK, or alter the other agent's stair work. It has two modes on
a visual flat plane: the original in-place pose study and a short forward walk with world-space
ankle planting. Neither is a gameplay locomotion controller.

The controls are: mouse drag to orbit, wheel to zoom, Space to pause, Left/Right to step frames,
and a 120-frame timeline to scrub two in-place cycles. The **Move forward + lock planted feet**
checkbox starts an eight-cycle forward walk; Reset walk replays it. The camera follows the moving
character over fixed floor grid lines. Moving mode can pause and step forward, but cannot scrub
backward because foot-plant history is stateful; switch back to in-place mode for arbitrary frame
scrubbing. Colored hip/knee/ankle/toe markers and a knee-angle readout make individual poses
inspectable. Step rate, foot travel, lift, blend, and arm swing have temporary sliders. Their
settings are not saved.

Current default parameters are approximately:

| Parameter | Value | Meaning |
| --- | ---: | --- |
| Step rate | 1 cycle/s | Two complete cycles in the 120-frame timeline at 60 fps |
| Foot travel | ±0.20 m | Front/back target relative to the body; moving stance uses a fixed world target |
| Maximum foot lift | 0.13 m | Swing-foot vertical arc |
| Swing fraction | 40% | Remaining 60% is the support/stance phase |
| Pelvis drop | 0.04 m | Keeps knees flexed at contact |
| Arm swing | 0.22 rad | Small opposing arm motion |

If we create many procedural gaits, these parameters and curves should become separate, editable
Godot `Resource` profiles (for example walk, sprint, crouch-walk), read by one shared gait system.
That profile system does **not** exist yet. Exact replay of a real animation remains an `Animation`
resource; extracting its foot/pelvis/arm trajectories into a gait profile would be a separate tool.

## What the iterations taught us

1. **Direction depends on the source rig.** MotusMan's native forward is `+Z`; the scene rotates
   its visual root by 180 degrees, making its world forward `-Z`. The first foot trajectory ran
   backward until the swing travel was reversed. The lab check now verifies frontward travel.
2. **A knee can flip even when the ankle target is continuous.** The first solver projected the
   nearly straight idle knee onto the hip-to-ankle line to choose a bend direction. That projection
   crossed zero during the cycle, flipping the knee plane. The repeatable one-frame jump was about
   48–52 degrees. A stable anatomical forward bend direction removed it; the subsequent maximum
   was about 8.4 degrees/frame.
3. **Reach and landing timing are coupled.** The long initial stride and high pelvis drove the
   landing leg almost straight before the foot settled. A shorter default stride, a small pelvis
   drop, a swing arc with zero vertical speed at the endpoints, and a reachable ankle target brought
   the measured maximum down to about 3.3 degrees/frame. Reducing the jump alone was not enough:
   visually, the foot still seemed to arrive after the knee had extended.
4. **Contact needs its own phase, not just a sine wave.** The current gait reaches the front plant
   earlier (frame 24 for the left foot, frame 54 for the right), then holds the toe at the same
   vertical level during stance while the foot moves backward relative to the in-place body.
   At those frames the measured knee flex is about 27.8 degrees left and 21.6 degrees right;
   the largest joint rotation is about 4.3 degrees/frame and the largest knee-flex change about
   6.5 degrees/frame. Before touchdown the toe is measurably above its planted level.
5. **A flat local stance height is not a foot plant.** In moving mode, each foot captures a
   world-space ankle position at touchdown and retains it through stance. The next swing starts
   from that exact world point and aims ahead of the predicted root at the next touchdown. At the
   default settings, a three-second headless walk traveled 2.00 m, took 144 planted-foot samples,
   and measured zero ankle-to-plant drift at its printed precision; the worst joint change was
   4.58 degrees/frame. This shows the planted **ankle target** is stable, not that the rendered
   shoe is visually perfect or free of floor penetration.

Run the bounded headless check with:

```sh
godot --headless --path . res://tests/manual/procedural_walk/procedural_walk_lab.tscn -- --lab-check
godot --headless --path . res://tests/manual/procedural_walk/procedural_walk_lab.tscn -- --moving-check
```

The in-place check covers direction, joint movement, the complete cycle including its seam, knee
bend at contact, contact target error, and toe height before/after contact. The moving check covers
forward root travel, planted-ankle world error, and joint continuity. `--contact-report` prints a
short per-frame toe/ankle/knee trace for diagnosis. `scripts/check.sh` also passes. These are
**headless measurements, not a confirmed visual verdict**. In particular, the reported `ToeBase`
position is a bone origin, not the lowest skinned shoe vertex; it cannot by itself prove that the
rendered sole touches or does not penetrate the plane. The plane is visual-only in this lab.

## Outside research and what it implies here

- [Kovar, Schreiner, and Gleicher, *Footskate Cleanup for Motion Capture Editing* (2002)](https://graphics.cs.wisc.edu/Papers/2002/KSG02/)
  treats a planted foot as a contact constraint, not a free-running periodic foot target. It also
  discusses avoiding knee pops while enforcing that contact. **Inference for this prototype:**
  merely keeping local foot height flat during stance will still look like sliding while the root
  is stationary; a real moving test needs a world-space foot plant.
- [Redfern and Schumann, *A model of foot placement during gait* (1994)](https://pubmed.ncbi.nlm.nih.gov/7798284/)
  reports that swing-foot velocity is near zero at heel contact and relates foot placement to the
  pelvis and opposite support foot. **Inference:** landing timing, pelvis travel, and support-foot
  position should be coordinated instead of tuned as unrelated sine curves.
- [Epic's Foot Placement plant settings](https://dev.epicgames.com/documentation/unreal-engine/API/Plugins/AnimationWarpingRuntime/FFootPlacementPlantSettings)
  expose separate controls for locking, ground distance, heel adjustment, and leg extension;
  [Epic's Game Animation Sample documentation](https://dev.epicgames.com/documentation/unreal-engine/game-animation-sample-project-in-unreal-engine)
  describes leg IK and offset-root/pelvis presentation. These are architectural references, **not
  permission to import Epic's UE-only sample assets into this Godot project** (see
  [the GASP asset review](../AGENT_TASKS/027_gasp_animation_assets_and_architecture_reference.md)).

## Recommended next experiment

First get a live visual verdict on the new moving mode. Then add a real support-foot-driven pelvis
weight shift and heel-to-toe foot rotation, comparing the results against one of this project's
legally usable walk clips. Add a floor collider and measure the skinned shoe's lowest points,
not only ankle/toe bone origins; also measure planted toe and sole world displacement and knee
motion at contact. Only after flat movement looks convincing should this lab gain turning, stairs,
or any connection to the gameplay Foot IK coordinator.

The scene still cannot validate terrain adaptation, turning, or actual rendered-shoe/floor contact.
The moving root is a scripted constant-speed path, not `Player` movement. Do not mistake a clean
headless ankle/joint result for a finished walk animation.
