shader_type spatial;
// Leather footwear (and later leather garments) for the parametric humans (garment recipes: tools/blender/build_outfit.py). Not simulated: the mesh
// follows the skeleton. Vertex colour from the builder: R = the height above the ground as a ramp (1 on the ground .. 0 at 3 cm, fit.SOLE_RAMP),
// G = how close to the top's edge (1 at the edge), B = a cord wound round the ankle, A = draw the inside. Everything is in the mesh's own space (no UVs): the grain, the creases, the wear and the scuffs move with the shoe.
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec3 cloth_color : source_color = vec3(0.36, 0.27, 0.21);   // the leather (the labs set every garment's colour under this name)
uniform vec3 sole_color : source_color = vec3(0.16, 0.12, 0.09);
uniform vec3 cord_color : source_color = vec3(0.3, 0.22, 0.16);
uniform float grain_scale = 330.0;         // the crease network's cells per metre
uniform float grain_depth = 0.25;          // how much the grain shows in the light (its slopes)
uniform float grain_height = 0.0005;       // the creases' depth (m): the close-up depth
uniform float grain_shade = 0.18;          // the creases this much darker in shade (light: crease_light)
uniform vec3 sun_dir_world = vec3(0.35, 0.8, 0.45);   // toward the main light (the labs set it): the close-up grain's own shadows
uniform float pom_near = 0.25;             // the close-up depth (parallax) fades in below this many grain cells a pixel and is full at half of it
uniform float pom_depth = 1.0;             // the close-up depth's strength
uniform int pom_steps : hint_range(4, 64) = 8;           // the steps along the view ray up close
uniform int pom_shadow_steps : hint_range(2, 32) = 4;    // the steps toward the sun for the surface's own shadows
uniform float grain_shadow = 0.55;         // how dark the surface's own shadows are
uniform float crease_width = 0.09;         // the creases' width, in grain cells
uniform float crease_warp = 0.9;           // how far the crease network wanders from a regular cell pattern
uniform float fine_creases = 0.6;          // the finer, second network of creases (0 none)
uniform float crease_light = 0.45;         // the creases this much paler (pull-up leather lightens where it folds)
uniform float fold_scale = 0.09;           // the long folds: their noise's frequency in grain cells (0.09 at 110 cells a metre: ~10 cm waves)
uniform float fold_stretch = 0.5;          // ... how much longer than wide the folds run (1: round loops)
uniform float fold_width = 0.18;           // ... how wide a fold line is (in grain cells)
uniform float fold_depth = 0.0;            // ... how deep, against the fine creases (1); 0: no long folds, only the fine creases (the user:
// "we don't need the big waves, just small ones"), and their cost skipped
uniform float creases = 0.5;               // soft creases and wrinkles of worn leather (a normal, no geometry)
uniform float crease_scale = 35.0;
uniform float roughness_base : hint_range(0.0, 1.0) = 0.62;
uniform float wear = 0.35;                 // 0 new .. 1 old: lighter, scuffed edges and toes, dust toward the sole
uniform float mottle = 0.6;                // the hide's uneven colour (darker and lighter patches)
uniform vec3 crease_tint : source_color = vec3(1.25, 1.05, 0.8);   // the creases' paler colour, warm (the references' lit crease edges)
uniform vec3 dark_patch : source_color = vec3(0.45, 0.33, 0.28);  // the dark patches' colour, as a share of the leather's
uniform float sheen = 0.15;
uniform float footwear = 0.0;              // 1: R is the height above the ground (a shoe: the sole and its seam); 0: a garment (R is its belt band)
uniform float sole_height = 0.008;         // the sole's edge above the ground (m)
uniform float seam_height = 0.0025;        // the stitched seam's band just above the sole (m)
uniform float stitch_spacing = 180.0;      // the seam's stitches per metre
uniform float stitch_length : hint_range(0.0, 1.0) = 0.55;   // each stitch's share of its spacing
uniform float lace_grain = 2.0;            // a leather lace's crackle this much finer than the shoe's
uniform float cord_groove_shade = 0.7;     // the cord's grooves between strands this much darker
uniform float flaw_seed = 0.0;
uniform float imperfection : hint_range(0.0, 1.0) = 0.5;

varying vec3 local_pos;
varying vec3 local_normal;

// The GPU cloth solver (addons/godot_gpu_cloth) drives a simulated leather garment (a jerkin) through these, as in human_clothes.gdshader: the
// positions and normals from its storage textures, the grain and the wear stay on the leather's rest place (local_pos). Shoes are not simulated.
uniform bool gpu_driven = false;
uniform sampler2D positions_tex : filter_nearest;
uniform sampler2D normals_tex : filter_nearest;
uniform sampler2D welded_index_tex : filter_nearest;
uniform int tex_width = 4096;
uniform int render_tex_width = 4096;
uniform mat4 skel_to_mesh_transform;
uniform float render_offset = 0.0;

// Drawn in where a higher layer covers this garment (ClothSetup.apply_covered: by vertex index, 1 under the middle of the higher garment, 0 at its
// edges and where nothing covers it): a shirt under mail or a jerkin cannot show through it in a quick turn.
uniform sampler2D covered_tex : filter_nearest;
uniform int covered_tex_width = 1024;
uniform float covered_inset = 0.0;

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);   // (quintic: smooth slopes; the cubic left steps along the noise grid in the creases' light)
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

// the pebbled grain: smooth noise bumps, sharpened a little (0 low .. 1 high). A cellular pattern (distance to the nearest random point) gave
// every junction of cells a point the bump turned into a black dot.
float grain(vec3 p) {
	float n = noise3(p) * 0.65 + noise3(p * 2.1 + 7.3) * 0.35;
	return smoothstep(0.25, 0.75, n);
}

// the grain on one axis plane (in grain cells), a third coordinate per plane so the planes do not repeat each other
// how close t is to a cell wall of a cellular pattern (the second nearest point's distance less the nearest's: 0 on a wall), 1 on a wall .. 0 away
float crease_line(vec2 t, float plane, float width) {
	vec2 cell = floor(t);
	vec2 f = fract(t);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 o = vec2(float(x), float(y));
			vec3 key = vec3(cell + o, plane * 13.7);
			vec2 point = o + vec2(hash3(key), hash3(key + 17.1));
			float d = length(point - f);
			if (d < d1) {
				d2 = d1;
				d1 = d;
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	return 1.0 - smoothstep(0.0, width, d2 - d1);
}

// distressed (pull-up) leather, as in the reference photo: a fine, irregular network of creases at two scales, the walls of a warped cellular
// pattern; the surface is 1, a crease dips toward 0. (Round pebbles were the wrong leather; value noise made them square.)
float fold_field(vec2 slow, float plane) {
	vec2 bend = vec2(noise3(vec3(slow * 0.5, plane * 3.1 + 1.0)), noise3(vec3(slow * 0.5 + 9.7, plane * 3.1 + 2.0))) - 0.5;
	return noise3(vec3(slow + bend * 1.5, plane * 5.3)) * 0.7 + noise3(vec3(slow * 2.1 + bend, plane * 5.3 + 4.0)) * 0.3;
}

// the long folds (the references: wavy lines across the hide a few cm apart): isolines of a slow, warped noise, 1 on a fold .. 0 away
float folds2(vec2 t, float plane) {
	// stretched (long, roughly parallel waves; round noise closed into loops) along a direction turned off the noise's grid (stretched along
	// the grid itself, value noise came out in straight lines and rectangles)
	float turn = 0.6 + plane * 0.9;
	mat2 rot = mat2(vec2(cos(turn), sin(turn)), vec2(-sin(turn), cos(turn)));
	vec2 slow = rot * t * fold_scale;
	slow.x *= fold_stretch;
	slow = transpose(rot) * slow;
	// the line's distance in grain cells: the field's distance from the level over its slope (a fixed width in the field's values made wide
	// bands with straight edges wherever the noise was flat)
	float e = 0.35;
	float field = fold_field(slow, plane);
	vec2 grad = vec2(fold_field(slow + vec2(e * fold_scale, 0.0), plane) - field, fold_field(slow + vec2(0.0, e * fold_scale), plane) - field) / e;
	float slope = max(length(grad), 1e-3);
	float fold = 1.0 - smoothstep(0.0, fold_width, abs(field - 0.5) / slope);
	return max(fold, 0.6 * (1.0 - smoothstep(0.0, fold_width * 0.8, abs(field - 0.32) / slope)));
}

// the fine crackle between the folds: the walls of a warped cellular pattern at two scales, strong in patches and fading out in others, broken
// into segments (a closed cell wall everywhere read as dried mud); 1 on a crack .. 0 away
float crackle2(vec2 t, float plane) {
	vec2 warp = vec2(noise3(vec3(t * 0.3, plane * 7.1)), noise3(vec3(t * 0.3 + 5.2, plane * 7.1 + 3.3))) - 0.5;
	vec2 tw = t + warp * crease_warp;
	float patch = smoothstep(0.3, 0.7, noise3(vec3(t * 0.07, plane * 2.3 + 8.0)));
	float broken = smoothstep(0.38, 0.62, noise3(vec3(tw * 1.3, plane * 4.7 + 6.0)));
	float broken_fine = smoothstep(0.4, 0.6, noise3(vec3(tw * 2.9, plane * 4.7 + 9.0)));
	float lines = crease_line(tw, plane, crease_width) * mix(0.35, 1.0, patch) * broken;
	return max(lines, fine_creases * patch * broken_fine * crease_line(tw * 2.3 + 3.1, plane + 0.5, crease_width * 1.3));
}

// distressed (pull-up) leather, as in the reference photos: the surface is 1, a fold or a crack dips toward 0. (Round pebbles were the wrong
// leather; value noise made them square.)
float grain2(vec2 t, float plane) {
	return 1.0 - max(fold_depth > 0.0 ? folds2(t, plane) * fold_depth : 0.0, crackle2(t, plane));
}

// The view-space tangent frame of a 2D parameter on the surface (Schüler's cotangent frame), as in human_clothes.gdshader: works on simulated
// leather too. The screen derivatives are taken by the caller, outside any branch.
mat3 cotangent_frame(vec3 n, vec3 dp1, vec3 dp2, vec2 duv1, vec2 duv2) {
	vec3 dp2perp = cross(dp2, n);
	vec3 dp1perp = cross(n, dp1);
	vec3 t = dp2perp * duv1.x + dp1perp * duv2.x;
	vec3 b = dp2perp * duv1.y + dp1perp * duv2.y;
	float invmax = inversesqrt(max(max(dot(t, t), dot(b, b)), 1e-20));
	return mat3(t * invmax, b * invmax, n);
}

// Debug: a bump heatmap (the body lab's "Bumps heatmap"): each vertex's distance from a heavily smoothed copy of the garment, along its normal
// (ClothSetup.bump_texture, by vertex index): red sticks out, blue sinks in, white follows the smooth shape; bump_debug_range is full colour.
uniform float bump_debug = 0.0;
uniform sampler2D bump_debug_tex : filter_nearest;
uniform int bump_debug_width = 1024;
uniform float bump_debug_range = 0.001;
varying float bump_off;

vec3 bump_heat(float off) {
	float x = clamp(off / bump_debug_range, -1.0, 1.0);
	return x > 0.0 ? mix(vec3(0.9), vec3(1.0, 0.08, 0.04), x) : mix(vec3(0.9), vec3(0.05, 0.25, 1.0), -x);
}

void vertex() {
	bump_off = 0.0;
	if (bump_debug > 0.5) {
		bump_off = texelFetch(bump_debug_tex, ivec2(int(VERTEX_ID) % bump_debug_width, int(VERTEX_ID) / bump_debug_width), 0).r;
	}
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
	if (covered_inset > 0.0) {
		ivec2 c_coord = ivec2(int(VERTEX_ID) % covered_tex_width, int(VERTEX_ID) / covered_tex_width);
		VERTEX -= NORMAL * covered_inset * texelFetch(covered_tex, c_coord, 0).r;
	}
}

void fragment() {
	if (!FRONT_FACING && COLOR.a < 0.5) {
		discard;
	}
	float sole = COLOR.r;
	float edge = COLOR.g;
	float cord = COLOR.b;
	float rope = step(0.75, cord);   // (B 1: a twisted rope, real strands; B 0.5: a leather lace - leather with the grain's depth, never plain)
	float lace = step(0.25, cord) * (1.0 - rope);
	vec3 seed_shift = vec3(flaw_seed * 17.31, flaw_seed * 5.17, flaw_seed * 9.73);
	vec3 n_view = NORMAL;
	// the leather's creases (grain2), laid on the three axis planes of the rest shape and blended by how much the surface faces each: its slopes lit through a
	// cotangent frame, and close up real depth (SPOM: parallax occlusion along the view ray, its own shadows toward the sun), as the
	// cloth's weave in human_clothes.gdshader. A flat bump alone looked blotchy and pixelated up close. Finer than a pixel it fades out.
	vec3 view_dir = normalize(-VERTEX);
	vec3 sun_view = normalize((VIEW_MATRIX * vec4(sun_dir_world, 0.0)).xyz);
	vec3 dp1 = dFdx(VERTEX);   // (every screen derivative here, before any branch)
	vec3 dp2 = dFdy(VERTEX);
	float scale_here = grain_scale * mix(1.0, lace_grain, lace);   // (a 3 mm thong: the crackle finer to fit it)
	vec2 plane_uv[3] = vec2[3](local_pos.zy * scale_here, local_pos.xz * scale_here, local_pos.xy * scale_here);
	vec2 duv1[3];
	vec2 duv2[3];
	for (int axis = 0; axis < 3; axis++) {
		duv1[axis] = dFdx(plane_uv[axis]);
		duv2[axis] = dFdy(plane_uv[axis]);
	}
	vec3 plane_weight = pow(abs(normalize(local_normal)), vec3(4.0));
	plane_weight /= plane_weight.x + plane_weight.y + plane_weight.z;
	float g0 = 0.0;   // (the grain's height, 0 valley .. 1 top)
	float grain_lit = 0.0;
	float grain_fade = 0.0;
	vec3 grain_bump = vec3(0.0);   // (view space)
	for (int axis = 0; axis < 3; axis++) {
		float w = axis == 0 ? plane_weight.x : (axis == 1 ? plane_weight.y : plane_weight.z);
		if (w < 0.01) {
			continue;
		}
		float per_pixel = length(abs(duv1[axis]) + abs(duv2[axis]));   // (grain cells a pixel)
		float plane_fade = 1.0 - smoothstep(0.5, 1.5, per_pixel);
		if (plane_fade <= 0.0) {
			g0 += w * 0.5;
			grain_lit += w;
			continue;
		}
		// the plane's own axes in view space, laid on the surface: smooth over the mesh (a frame from screen derivatives is constant per
		// triangle, and the parallax offset jumped at every edge: straight cuts and rectangles in the pattern)
		vec3 axis_u = axis == 0 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
		vec3 axis_v = axis == 1 ? vec3(0.0, 0.0, 1.0) : vec3(0.0, 1.0, 0.0);
		vec3 tu = (VIEW_MATRIX * (MODEL_MATRIX * vec4(axis_u, 0.0))).xyz;
		vec3 tv = (VIEW_MATRIX * (MODEL_MATRIX * vec4(axis_v, 0.0))).xyz;
		tu = normalize(tu - n_view * dot(tu, n_view) + vec3(1e-6));
		tv = normalize(tv - n_view * dot(tv, n_view) + vec3(1e-6));
		mat3 frame = mat3(tu, tv, n_view);
		vec2 t = plane_uv[axis];
		float near = 1.0 - smoothstep(pom_near * 0.5, pom_near, per_pixel);
		float lit = 1.0;
		float depth_cells = grain_height * grain_scale * pom_depth;   // (the creases' depth in grain cells)
		if (near > 0.0 && rope < 0.5) {
			vec3 v_ts = vec3(dot(view_dir, frame[0]), dot(view_dir, frame[1]), max(dot(view_dir, n_view), 0.15));
			float steps = float(pom_steps);
			vec2 step_uv = -v_ts.xy / v_ts.z * depth_cells / steps;
			// (the folds once for the pixel: the march moves a fraction of a crease, and the folds' noise at every step cost ~8 ms with
			// leather filling the screen; the crackle is marched)
			float fold_here = fold_depth > 0.0 ? folds2(t, float(axis)) * fold_depth : 0.0;
			vec2 marched = t;
			float layer = 1.0;
			float h = 1.0 - max(fold_here, crackle2(marched, float(axis)));
			for (int i = 0; i < pom_steps; i++) {
				if (h >= layer) {
					break;
				}
				layer -= 1.0 / steps;
				marched += step_uv;
				h = 1.0 - max(fold_here, crackle2(marched, float(axis)));
			}
			t = mix(t, marched, near);
			vec3 l_ts = vec3(dot(sun_view, frame[0]), dot(sun_view, frame[1]), dot(sun_view, n_view));
			if (l_ts.z > 0.05) {
				float shadow_steps = float(pom_shadow_steps);
				vec2 sun_step = l_ts.xy / l_ts.z * depth_cells / shadow_steps;
				float start = 1.0 - max(fold_here, crackle2(t, float(axis)));
				float blocked = 0.0;
				for (int i = 1; i <= pom_shadow_steps; i++) {
					float ray = start + float(i) / shadow_steps;
					blocked = max(blocked, smoothstep(0.0, 0.15, 1.0 - max(fold_here, crackle2(t + sun_step * float(i), float(axis))) - ray));
				}
				lit = mix(1.0, 1.0 - grain_shadow * blocked, near);
			}
		}
		float h0 = grain2(t, float(axis));
		float ge = 0.06;
		float hx = grain2(t + vec2(ge, 0.0), float(axis)) - grain2(t - vec2(ge, 0.0), float(axis));
		float hy = grain2(t + vec2(0.0, ge), float(axis)) - grain2(t - vec2(0.0, ge), float(axis));
		grain_bump += w * plane_fade * (frame[0] * hx + frame[1] * hy) * (grain_depth * 0.5 / (2.0 * ge));
		g0 += w * mix(0.5, h0, plane_fade);
		grain_lit += w * mix(1.0, lit, plane_fade);
		grain_fade += w * plane_fade;
	}
	vec3 crease_p = local_pos * crease_scale + seed_shift;
	vec3 crease_slope = vec3(fbm(crease_p + vec3(0.1, 0.0, 0.0)) - fbm(crease_p - vec3(0.1, 0.0, 0.0)),
			fbm(crease_p + vec3(0.0, 0.1, 0.0)) - fbm(crease_p - vec3(0.0, 0.1, 0.0)),
			fbm(crease_p + vec3(0.0, 0.0, 0.1)) - fbm(crease_p - vec3(0.0, 0.0, 0.1))) * 2.0;
	// the hide's colour: dark and pale patches at two sizes (worn, oiled, darkened with handling, as in the references)
	float patches = fbm(local_pos * 4.0 + seed_shift) * 0.6 + fbm(local_pos * 13.0 + seed_shift * 1.7) * 0.4;
	vec3 base = cloth_color * mix(vec3(1.0), dark_patch, mottle * (1.0 - smoothstep(0.3, 0.7, patches))) * (1.0 + 0.25 * mottle * smoothstep(0.55, 0.85, patches));
	base *= mix(vec3(1.0), mix(vec3(1.0), crease_tint, crease_light * 2.0 * (1.0 - g0)), grain_fade) * mix(1.0, (1.0 - grain_shade) + grain_shade * g0, grain_fade * 0.3) * grain_lit;   // (the
	// creases paler, a little shade in them, the surface's own shadows)
	float rough = roughness_base;
	// wear: the toes and the edges lighter and scuffed, dust toward the sole
	float tip = smoothstep(0.12, 0.24, local_pos.z) * footwear;   // (a shoe's toes: +z is forward, the tip ~0.25 m ahead of the heel's line)
	float scuff = smoothstep(0.6, 0.85, fbm(local_pos * 25.0 + seed_shift)) * (0.15 + 0.85 * max(tip, edge));   // (worn patches: few and soft)
	base = mix(base, base * vec3(1.3, 1.24, 1.16), wear * scuff * 0.6);
	float low = 1.0 - smoothstep(0.0, 0.05, local_pos.y);
	base = mix(base, base * vec3(1.15, 1.1, 1.02) + vec3(0.03, 0.025, 0.02), wear * low * 0.5);   // (dust)
	rough = mix(rough, 0.85, wear * scuff);
	// the sole: darker, smoother, and a row of stitches along its seam
	float height = (1.0 - sole) * 0.03;   // (metres above the ground, from R)
	float aa = max(fwidth(height), 1e-5);
	float on_sole = 1.0 - smoothstep(sole_height - aa, sole_height + aa, height);
	on_sole *= footwear;
	if (rope < 0.5 && lace < 0.5 && footwear > 0.5) {
		base = mix(base, sole_color * (0.85 + 0.3 * fbm(local_pos * 50.0)), on_sole);
		rough = mix(rough, 0.75, on_sole);
		// the seam: a thin band over the sole's edge, short stitches along it (along the ground: x and z)
		float band = smoothstep(sole_height + aa, sole_height + 2.0 * aa, height) * (1.0 - smoothstep(sole_height + seam_height - aa, sole_height + seam_height + aa, height));
		float along = (local_pos.x + local_pos.z) * stitch_spacing;
		float dash = smoothstep(0.0, 0.15, fract(along)) * (1.0 - smoothstep(stitch_length, stitch_length + 0.15, fract(along)));
		base = mix(base, base * 1.6 + vec3(0.03), band * dash * 0.6 * (1.0 - smoothstep(0.3, 0.8, fwidth(along))));   // (a waxed thread a shade lighter)
	}
	// the cord: twisted (diagonal ridges round it), its own shade
	if (lace > 0.5) {
		base *= cord_color / max(cloth_color, vec3(0.01));   // (the lace's own colour; its grain, depth and shadows kept)
	}
	if (rope > 0.5) {
		// the rope's strands are real geometry (garments/fit.py _add_cords); G is how deep a point sits in the groove between them: darker there
		// (little light reaches it), the strands' crowns a little paler and rubbed. A painted twist on a plain tube looked painted.
		float groove = edge;
		base = cord_color * (1.08 - cord_groove_shade * groove) * (0.9 + 0.2 * fbm(local_pos * 400.0));
		rough = mix(0.62, 0.85, groove);
		grain_fade = 0.0;
	}
	// a garment's hems: a row of stitches a little in from the edge (G: 1 at the edge)
	if (footwear < 0.5) {
		float hem_band = smoothstep(0.5, 0.56, edge) * (1.0 - smoothstep(0.64, 0.7, edge));
		float along_hem = (local_pos.x + local_pos.y + local_pos.z) * stitch_spacing;
		float hem_dash = smoothstep(0.0, 0.15, fract(along_hem)) * (1.0 - smoothstep(stitch_length, stitch_length + 0.15, fract(along_hem)));
		base = mix(base, base * 1.6 + vec3(0.03), hem_band * hem_dash * 0.6 * (1.0 - smoothstep(0.3, 0.8, fwidth(along_hem))));
	}
	// the top's edge: the leather turned over (a little darker), a few holes torn with imperfection are left for later
	base *= 1.0 - 0.15 * smoothstep(0.6, 1.0, edge) * (1.0 - rope) * (1.0 - lace);
	if (!FRONT_FACING) {
		base *= 0.45;   // (the inside)
	}
	ALBEDO = base;
	if (bump_debug > 0.5) {
		ALBEDO = bump_heat(bump_off);
	}
	ROUGHNESS = rough;
	SPECULAR = 0.35;
	vec3 slope = crease_slope * creases * 0.6 * (1.0 - rope);
	slope = slope / max(1.0, length(slope) / 0.3);   // (a bump never tilts the surface past ~17 degrees)
	vec3 tilt = (VIEW_MATRIX * (MODEL_MATRIX * vec4(slope, 0.0))).xyz + grain_bump * (1.0 - rope);   // (normal = n - tilt: the grain's slope
	// subtracted as in human_clothes.gdshader, or the creases come out as ridges)
	tilt = tilt / max(1.0, length(tilt) / 0.35);
	NORMAL = normalize(n_view - tilt);
	RIM = sheen;
	RIM_TINT = 0.5;
}
