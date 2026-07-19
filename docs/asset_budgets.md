# 3D Asset Budgets

Practical reference values for generated and downloaded assets. These are
starting points, not acceptance criteria: inspect the exported file and test it
at its closest expected in-game camera distance before accepting it.

## Verify The Export

Do not assume an asset generator honored its triangle or texture settings. The
rusty knife experiments produced several exports near 500,000 triangles even
after requesting a lower value. Read the resulting GLB's indexed triangle count
and embedded texture dimensions directly.

Also verify:

- real-world dimensions and local axis orientation;
- pivot placement, especially for held objects;
- material count and PBR texture channels;
- whether normals, UVs, tangents, a rig, or animations are present;
- license/source information, which may not be embedded in the GLB;
- appearance in first person, third person, and as a world pickup.

## Held Props

| Use | Triangle target | Texture target |
| --- | ---: | ---: |
| Distant or repeated world prop | 2,000-8,000 | 512-1024 |
| Normal pickup / third-person prop | 5,000-15,000 | 1024 |
| First-person held prop | 15,000-25,000 | 1024-2048 |
| Sustained close-up inspection | 20,000-40,000 | 2048 |

Prefer 1024 textures by default. Use 2048 when a first-person object stays close
to the camera or its surface detail is important. A 4096 texture is rarely
justified for an ordinary held prop.

### Rusty Knife Reference

The accepted optimization reference from `rusty_knife.glb` was:

- 19,080 indexed triangles;
- 12,055 vertices;
- two 1024 x 1024 embedded WebP textures;
- one mesh primitive and one PBR material;
- 892 KB GLB file size.

The original export was about 498,000 triangles with two 4096 textures and a
21 MB file size. Reducing it demonstrates that generated props need explicit
budgets and post-export inspection. The optimized file is only a technical
reference until its silhouette, texture sharpness, and hand contact are checked
interactively in both camera modes.

## Faces And Characters

| Use | Triangle target | Texture target |
| --- | ---: | ---: |
| Background NPC head | 10,000-20,000 | 1024 |
| Normal close NPC head | 25,000-40,000 | 2048 |
| Important hero face | 40,000-70,000 | 2048 |
| Cinematic close-up face | 70,000-100,000 | 4096 |
| Complete gameplay character | 50,000-80,000 | 2048 |

For an important NPC in this project, start around 30,000-40,000 triangles and
2048 textures for the head, or 50,000-80,000 triangles and 2048 textures for a
complete character.

Triangle count and texture resolution do not determine animation quality. A
face intended for expressions needs deformation-friendly edge flow around the
eyes, mouth, cheeks, and jaw, plus a suitable facial rig or blend shapes. A
clean 40,000-triangle face can deform better than a randomly triangulated
100,000-triangle scan.

