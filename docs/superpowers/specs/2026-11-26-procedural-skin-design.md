# Procedural skin detail (task 102) — short design

**Why:** the user wants the skin to look realistic. It was compared with close-up photos of real faces (Bing Images, 2026-11-26), and our face differs in five ways:
1. Its colour is the same everywhere.
2. It has only one soft shine.
3. Its shadows go grey.
4. Its pores are the same everywhere.
5. The coarse mesh shows faint bands.

The user picked approach A, procedural ("let's try A, maybe procedural").

**Approaches considered:**
- **A. Procedural detail in the skin shader (picked):** this works on every skin and adds no new assets.
- **B. Scanned textures:** free ones are rare, and they would have to be re-fitted to the MakeHuman UV layout.
- **C. A plus subdividing the head:** this fixes the bands too, but means mesh and rig work. It is left for later.

**Design:**
- **Face frame:** the lab finds the face's landmarks from the body mesh: the nose tip (the frontmost vertex on the middle line), the top of the head and the chin. It passes them to `human_skin.gdshader` as `face_nose`, `face_top` and `face_chin`. Every zone is placed relative to these, in the mesh's own space, so the zones stay put on the face. The lips keep their own frame from the hair builder.
- **Zones** (soft masks, each a 0..1 shader parameter):
  - **Redness:** nose, cheeks, ears and a little on the chin.
  - **Eye area:** darker and slightly purple under the eyes and on the lids.
  - **Shave shadow:** grey-blue over the jaw, upper lip, chin and lower cheeks, with dots for the follicles. On by default for the male body only.
  - **Oily T-zone and cheekbones:** a second, sharper shine, using Godot's clearcoat as the second highlight.
  - **Pores by area:** larger and deeper on the nose and cheeks, fine on the forehead. Fine criss-cross lines everywhere.
  - **Wrinkles:** crow's feet, forehead lines and the line from the nose to the mouth corner, scaled by an Age setting.
  - **Freckles and spots:** an optional setting.
- **Light through the skin:** stronger subsurface scattering, and red light coming through the ears and the edges of the nose.
- **Skin tab sliders:** Redness, Shave shadow, Oily shine, Pores, Age (wrinkles), Freckles, plus a debug view that tints each zone.

**Left to the builder:** the exact sizes and strengths of the zones, tuned by comparing captures with the reference photos.

**Not in scope:** new textures, and making the ears and nose physically correct. (The forehead bands turned out to be shadow acne from the lab's 0.001 shadow bias, not the mesh: fixed by setting the bias to 0.05.)
