# GPU cloth outfit trial

This harness exercises the vendored GPU Cloth Sim add-on against the Male
Peasant shirt and pants after the existing 5 mm automatic body fit:

```sh
godot --path . --resolution 1280x720 \
  res://tests/manual/outfit_cloth/gpu_cloth_outfit_test.tscn
```

For a deterministic capture after a chosen number of rendered frames:

```sh
godot --path . --resolution 1280x720 \
  res://tests/manual/outfit_cloth/gpu_cloth_outfit_test.tscn -- \
  capture=/tmp/gpu-cloth.png settle_frames=120
```

Pass `cloth=false` to capture only the contact-fit result without starting the
GPU solver. This is useful when comparing fitting algorithms independently of
simulation:

```sh
godot --path . --resolution 1280x720 \
  res://tests/manual/outfit_cloth/gpu_cloth_outfit_test.tscn -- \
  cloth=false capture=/tmp/contact-fit.png settle_frames=10
```

Use `debug=true` to retain the red-body/blue-cloth clipping diagnostic and
`yaw_degrees=<angle>` to capture an oblique view.

The shirt and pants use mutual peer collision. Cloth influence is generated
procedurally from vertex height for this experiment; it is not an authored
production mask. The static fit and gentle spine twist remain stable, but thigh
motion can destabilize the pants. The add-on also emits invalid
`RenderingDevice` resource errors while the test quits on Godot 4.6.2/Metal.
These are known acceptance failures, so the solver is not enabled in
`project.godot` or integrated into Character Creator.
