shader_type spatial;
// Plain villager clothes (tools/blender/make_clothes.py): a woven fabric (linen shirt, wool trousers) with its colour varying a little, worn lighter
// and dirtier toward the hems, stitched hems and cuffs, and a leather belt over the trousers' waistband. Vertex colour (from the builder): green =
// how close to a hem (1 at the edge), red = the waistband (the belt). The weave and the noise are laid in the mesh's own space (no UVs needed).
// Drawn from both sides: a look into a sleeve, a cuff or the neckline sees the inside of the cloth (darker: in its own shadow), not the gap to the skin.
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec3 cloth_color : source_color = vec3(0.72, 0.66, 0.55);
uniform vec3 belt_color : source_color = vec3(0.24, 0.15, 0.08);
uniform float threads_per_metre = 900.0;   // the weave (a coarse homespun cloth is ~10 threads a centimetre)
uniform float weave_depth = 0.6;           // how much the weave shades
uniform float roughness_base : hint_range(0.0, 1.0) = 0.88;
uniform float wear = 0.5;                  // 0 new .. 1 old: faded, dirtier toward the hems
uniform float folds = 0.6;                 // the soft creases of hanging cloth (a normal, no geometry)
uniform float sheen = 0.25;
// imperfections, all placed by `flaw_seed` (every character's clothes have their own): stains, worn and thinned cloth at the elbows and knees, small
// ragged holes (mostly where it is worn), mended patches of another cloth, and frayed hems. `imperfection` 0 = a new garment.
uniform float flaw_seed = 0.0;
uniform float imperfection : hint_range(0.0, 1.0) = 0.5;
uniform vec3 patch_color : source_color = vec3(0.42, 0.36, 0.3);
uniform vec3 elbow_l;   // the joints in the body's (and the cloth's) own space, from the lab (the skin shader gets the same)
uniform vec3 elbow_r;
uniform vec3 knee_l;
uniform vec3 knee_r;
uniform bool has_joints = false;

varying vec3 local_pos;
varying vec3 local_normal;

// The GPU cloth solver (addons/godot_gpu_cloth, task 103): when it drives this mesh it sets these, and the simulated positions and normals come from its
// storage textures (the same lookup as the add-on's cloth_surface.gdshader). The pattern stays on the cloth's rest place (local_pos above), so the weave,
// the stains and the patches move with the fabric.
uniform bool gpu_driven = false;
uniform sampler2D positions_tex : filter_nearest;
uniform sampler2D normals_tex : filter_nearest;
uniform sampler2D welded_index_tex : filter_nearest;
uniform int tex_width = 4096;
uniform int render_tex_width = 4096;
uniform mat4 skel_to_mesh_transform;
uniform float render_offset = 0.0;

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float sum = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		sum += amp * noise3(p);
		p *= 2.03;
		amp *= 0.5;
	}
	return sum;
}

void vertex() {
	local_pos = VERTEX;
	local_normal = NORMAL;
	if (gpu_driven) {
		ivec2 r_coord = ivec2(int(VERTEX_ID) % render_tex_width, int(VERTEX_ID) / render_tex_width);
		int welded_idx = int(texelFetch(welded_index_tex, r_coord, 0).r);
		ivec2 p_coord = ivec2(welded_idx % tex_width, welded_idx / tex_width);
		VERTEX = (skel_to_mesh_transform * vec4(texelFetch(positions_tex, p_coord, 0).xyz, 1.0)).xyz;
		NORMAL = normalize(mat3(skel_to_mesh_transform) * texelFetch(normals_tex, p_coord, 0).xyz);
		VERTEX += NORMAL * render_offset;
	}
}

// a random number per cell of a 3D grid
float cell_rand(vec3 cell, float salt) {
	return hash3(cell + vec3(salt * 13.7, salt * 5.3, salt * 9.1));
}

void fragment() {
	float hem = COLOR.g;
	float belt = COLOR.r;
	if (!FRONT_FACING && hem < 0.03 && COLOR.a < 0.5) {
		discard;   // (the torso's inside is only seen near an opening: elsewhere a back face is where the sleeve and the body's shell overlap at the armpit;
		// the sleeves (vertex alpha 1) show their whole inside: a look up a loose sleeve sees cloth, not the sky through it)
	}
	vec3 seed_shift = vec3(flaw_seed * 17.31, flaw_seed * 5.17, flaw_seed * 9.73);
	// --- where cloth wears: the elbows and the knees (bent and rubbed every day), the hems a little
	float worn_zone = 0.0;
	if (has_joints) {
		for (int i = 0; i < 4; i++) {
			vec3 joint = i == 0 ? elbow_l : (i == 1 ? elbow_r : (i == 2 ? knee_l : knee_r));
			worn_zone = max(worn_zone, 1.0 - smoothstep(0.025, 0.09, distance(local_pos, joint)));
		}
	}
	worn_zone *= 0.5 + 0.5 * noise3(local_pos * 30.0 + seed_shift);   // (an irregular edge, not a circle)
	// --- mended patches: a few squares of another cloth sewn on, more often over a worn place (a patch hides what is under it)
	vec3 patch_cell = floor(local_pos / 0.11 + seed_shift * 0.1);
	vec3 in_cell = fract(local_pos / 0.11 + seed_shift * 0.1);
	float patch_chance = imperfection * (0.06 + 0.5 * worn_zone);
	float patch_here = 0.0;
	float patch_edge = 0.0;
	if (belt < 0.5 && cell_rand(patch_cell, 1.0) < patch_chance) {
		vec3 centre = vec3(0.5) + (vec3(cell_rand(patch_cell, 2.0), cell_rand(patch_cell, 3.0), cell_rand(patch_cell, 4.0)) - 0.5) * 0.3;
		vec3 half_size = vec3(0.22 + 0.15 * cell_rand(patch_cell, 5.0), 0.25 + 0.15 * cell_rand(patch_cell, 6.0), 0.22 + 0.15 * cell_rand(patch_cell, 7.0));
		vec3 d = abs(in_cell - centre) / half_size;
		float box = max(d.x, max(d.y, d.z)) + (noise3(local_pos * 140.0 + seed_shift) - 0.5) * 0.12;   // (cut by hand: the edge wanders a little)
		patch_here = 1.0 - step(1.0, box);
		patch_edge = patch_here * smoothstep(0.82, 0.95, box);   // (the stitched border)
	}
	// --- holes: small and ragged, mostly in the worn places, a few anywhere; not through a patch or the belt
	float hole_field = noise3(local_pos * 28.0 + seed_shift) * 0.7 + noise3(local_pos * 90.0 + seed_shift * 2.0) * 0.3;
	float hole_chance = imperfection * (0.04 + 0.9 * worn_zone + 0.25 * hem);
	float hole_level = 1.0 - 0.32 * hole_chance;   // (the field is above this where there is a hole)
	if (belt < 0.5 && patch_here < 0.5 && hole_field > hole_level) {
		discard;
	}
	float fray = smoothstep(hole_level - 0.06, hole_level, hole_field) * (1.0 - patch_here) * smoothstep(0.0, 0.05, hole_chance);   // (the frayed ring round a hole:
	// loose light threads; none without holes: with no imperfection the noise's rare peaks still drew pale marks with no hole in them)
	// --- frayed hems: the very edge is ragged
	if (belt < 0.5 && hem > 0.9 && noise3(local_pos * 420.0 + seed_shift) > 1.25 - 0.4 * imperfection) {
		discard;
	}
	vec3 n_abs = abs(normalize(local_normal));
	// the weave and the slubs, laid on the three axis planes and blended by how much the surface faces each (a hard switch between the planes left
	// rectangles of another pattern where the surface turned, dark patches on the trouser legs)
	vec3 plane_weight = pow(n_abs, vec3(4.0));
	plane_weight /= plane_weight.x + plane_weight.y + plane_weight.z;
	float weave = 0.0;
	float slub = 0.0;
	float fade = 0.0;
	for (int axis = 0; axis < 3; axis++) {
		float w = axis == 0 ? plane_weight.x : (axis == 1 ? plane_weight.y : plane_weight.z);
		if (w < 0.01) {
			continue;
		}
		vec2 cloth_uv = axis == 0 ? local_pos.zy : (axis == 1 ? local_pos.xz : local_pos.xy);
		vec2 threads = cloth_uv * threads_per_metre;
		float plane_fade = 1.0 - smoothstep(0.4, 1.2, length(fwidth(threads)));   // (finer than a pixel: no weave, it would only shimmer)
		float warp = 0.5 + 0.5 * sin(threads.x * 6.2831);
		float weft = 0.5 + 0.5 * sin(threads.y * 6.2831);
		float over = step(0.5, fract(floor(threads.x) * 0.5 + floor(threads.y) * 0.5));   // (plain weave: over one, under one)
		weave += w * mix(warp, weft, over);
		slub += w * smoothstep(0.62, 0.9, noise3(vec3(cloth_uv.x * 40.0, cloth_uv.y * 900.0, 3.0 + float(axis))));
		fade += w * plane_fade;
	}
	// the cloth's colour: a slow mottle (an uneven dye), slubs (thicker threads), faded and dirty toward the hems with wear
	float mottle = fbm(local_pos * 6.0);
	vec3 base = cloth_color * (0.86 + 0.28 * mottle) * (1.0 - 0.06 * slub);
	base *= 1.0 - weave_depth * 0.18 * (1.0 - weave) * fade;
	float low = smoothstep(0.55, 0.05, local_pos.y);   // (the lower legs get the mud)
	base = mix(base, base * vec3(0.78, 0.72, 0.62), wear * (0.35 * low + 0.25 * hem) * (0.6 + 0.4 * fbm(local_pos * 20.0)));
	// stitched hems: a fold line and a row of stitches a little in from the edge
	float stitch_line = smoothstep(0.35, 0.45, hem) * (1.0 - smoothstep(0.5, 0.6, hem));
	float stitches = step(0.5, fract((local_pos.x + local_pos.z + local_pos.y) * 220.0));
	base *= 1.0 - 0.18 * stitch_line * (0.6 + 0.4 * stitches) * fade;
	base *= 1.0 - 0.1 * smoothstep(0.7, 1.0, hem);   // (the folded edge is a double layer: a little darker)
	// stains: soft blotches of dirt and grease with a darker rim (where it dried), their own for every seed
	float stain_field = fbm(local_pos * 5.0 + seed_shift * 0.37);
	float stain = smoothstep(0.66 - 0.06 * imperfection, 0.7 - 0.06 * imperfection, stain_field) * imperfection * (1.0 - belt);
	float stain_rim = stain * (1.0 - smoothstep(0.7, 0.74, stain_field));
	base = mix(base, base * vec3(0.72, 0.64, 0.55), stain * 0.6);
	base *= 1.0 - 0.12 * stain_rim;
	// worn cloth: faded, the weave thinned and lighter
	float worn = worn_zone * imperfection * (1.0 - patch_here);
	base = mix(base, base * vec3(1.12, 1.1, 1.05), worn * 0.6);
	base = mix(base, vec3(0.85, 0.8, 0.72) * cloth_color * 1.3, fray * 0.6);
	// the patch: another cloth, its own weave, a row of stitches round its edge
	if (patch_here > 0.5) {
		base = patch_color * (0.85 + 0.3 * fbm(local_pos * 40.0 + seed_shift)) * (1.0 - weave_depth * 0.15 * (1.0 - weave) * fade);
		float stitch = step(0.5, fract((local_pos.x + local_pos.y + local_pos.z) * 260.0));
		base *= 1.0 - 0.35 * patch_edge * stitch;
	}
	float rough = roughness_base;
	// the belt: leather over the waistband, with a buckle at the front middle
	if (belt > 0.5) {
		float leather = fbm(local_pos * 60.0);
		base = belt_color * (0.75 + 0.5 * leather);
		rough = 0.55 + 0.2 * leather;
		vec2 buckle = vec2(abs(local_pos.x), local_pos.z);
		if (buckle.x < 0.028 && local_normal.z > 0.5) {
			float frame = step(0.018, buckle.x);
			base = mix(base, vec3(0.45, 0.42, 0.38), frame);
			rough = mix(rough, 0.35, frame);
			METALLIC = frame * 0.8;
		}
	}
	if (!FRONT_FACING) {
		base *= 0.5;   // (the inside of the garment: little light gets in)
	}
	ALBEDO = base;
	ROUGHNESS = rough;
	SPECULAR = 0.3;
	// the creases of hanging cloth: a soft, mostly vertical wave in the normal (folds run down a hanging sleeve and leg), and the weave's bump
	vec3 fold_p = local_pos * vec3(18.0, 3.0, 18.0);
	float fx = fbm(fold_p + vec3(0.13, 0.0, 0.0)) - fbm(fold_p - vec3(0.13, 0.0, 0.0));
	float fz = fbm(fold_p + vec3(0.0, 0.0, 0.13)) - fbm(fold_p - vec3(0.0, 0.0, 0.13));
	vec3 bend = vec3(fx, 0.0, fz) * folds * 1.4 * (1.0 - belt);
	vec3 weave_bend = vec3((weave - 0.5) * 0.25 * fade * weave_depth);
	if (gpu_driven) {
		// the simulated normals (the solver sums the face normals round each particle) go wrong in a few specks where the shell's triangles are tiny
		// (over the nipples, the navel, the rolled hems) and lit them as bright dots: where a normal turns far from its triangle's own facing, the facing
		vec3 face_n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
		face_n = face_n.z < 0.0 ? -face_n : face_n;   // (toward the camera: the side being drawn)
		NORMAL = normalize(mix(face_n, NORMAL, smoothstep(0.55, 0.85, dot(NORMAL, face_n))));
	}
	NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(bend, 0.0)).xyz + weave_bend * 0.2);
	RIM = sheen * (1.0 - belt);
	RIM_TINT = 0.6;
}
