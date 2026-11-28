shader_type spatial;
// Plain villager clothes (tools/blender/make_clothes.py): a woven fabric (linen shirt, wool trousers) with its colour varying a little, worn lighter
// and dirtier toward the hems, stitched hems and cuffs, and a leather belt over the trousers' waistband. Vertex colour (from the builder): green =
// how close to a hem (1 at the edge), red = the waistband (the belt). The weave and the noise are laid in the mesh's own space (no UVs needed).
// Drawn from both sides: a look into a sleeve, a cuff or the neckline sees the inside of the cloth (darker: in its own shadow), not the gap to the skin.
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec3 cloth_color : source_color = vec3(0.72, 0.66, 0.55);
uniform vec3 belt_color : source_color = vec3(0.24, 0.15, 0.08);
uniform float threads_per_metre = 900.0;   // the weave (a coarse homespun cloth is ~10 threads a centimetre)
uniform float weave_depth = 0.6;           // how much the weave shades (and how deep it is: thread_height)
uniform float thread_height = 0.00045;     // metres: how far a thread crossing over stands above the gaps between threads
uniform float yarn_mix = 0.6;             // two-tone yarn: how much the light and dark fibres of a thread differ (0 = one colour)
uniform vec3 sun_dir_world = vec3(0.35, 0.8, 0.45);   // toward the main light (the labs set it): the close-up weave's own shadows
uniform float pom_near = 0.18;             // the close-up depth (parallax) fades in below this many threads a pixel and is full at half of it
// the weave's look (all of it here, so a material can set any: garments/materials.json "look")
uniform float gap_shade : hint_range(0.0, 1.0) = 0.12;        // how light the gaps between threads are (0 black)
uniform float thread_roundness : hint_range(0.2, 2.0) = 0.7;  // the shade across a thread (below 1: flatter tops, sharper edges)
uniform float thread_shadow : hint_range(0.0, 1.0) = 0.75;    // how dark the threads' own shadows are up close
uniform float thread_width = 0.72;         // a thread's width as a share of its spacing (the thinnest)
uniform float thread_width_spread = 0.2;   // how much thicker some threads are (hand-spun yarn is uneven)
uniform float thread_wander = 0.06;        // how far a thread wanders sideways
uniform float yarn_twist = 0.1;            // the twisted yarn's diagonal ridges along a thread
uniform float fibre_scale = 2.7;           // how long the light and dark stretches of a two-tone thread are (threads per stretch, inverse)
uniform float weave_bump = 2.2;            // the weave's slopes in the light
uniform float pom_depth = 1.6;             // the close-up depth's strength
uniform int pom_steps : hint_range(4, 64) = 16;         // the steps along the view ray up close
uniform int pom_shadow_steps : hint_range(2, 32) = 8;   // the steps toward the sun for the threads' shadows
uniform float roughness_base : hint_range(0.0, 1.0) = 0.88;
uniform float wear = 0.5;                  // 0 new .. 1 old: faded, dirtier toward the hems
uniform float folds = 0.6;                 // the soft creases of hanging cloth (a normal, no geometry)
uniform float sheen = 0.25;
// imperfections, all placed by `flaw_seed` (every character's clothes have their own): stains, worn and thinned cloth at the elbows and knees, small
// ragged holes (mostly where it is worn) and frayed hems (no mended patches: the user did not want them). `imperfection` 0 = a new garment.
uniform float flaw_seed = 0.0;
uniform float imperfection : hint_range(0.0, 1.0) = 0.5;
uniform vec3 elbow_l;   // the joints in the body's (and the cloth's) own space, from the lab (the skin shader gets the same)
uniform vec3 elbow_r;
uniform vec3 knee_l;
uniform vec3 knee_r;
uniform bool has_joints = false;
// bend wrinkles: creases round the limb where cloth bunches at a bent joint, deepest on the inside of the bend (the front of the elbow, the back
// of the knee). The joints above; per joint the limb's direction through it (upper arm to forearm, thigh to shin), the side the joint bends toward,
// and how bent it is now (0 straight .. 1 fully: the labs set it, the rig lab every frame of a walk)
uniform vec3 elbow_axis_l = vec3(0.0, -1.0, 0.0);
uniform vec3 elbow_axis_r = vec3(0.0, -1.0, 0.0);
uniform vec3 knee_axis_l = vec3(0.0, -1.0, 0.0);
uniform vec3 knee_axis_r = vec3(0.0, -1.0, 0.0);
uniform vec3 elbow_inside = vec3(0.0, 0.0, 1.0);   // (the side the elbow bends toward: the front)
uniform vec3 knee_inside = vec3(0.0, 0.0, -1.0);   // (the back)
uniform float elbow_bend_l : hint_range(0.0, 1.0) = 0.0;
uniform float elbow_bend_r : hint_range(0.0, 1.0) = 0.0;
uniform float knee_bend_l : hint_range(0.0, 1.0) = 0.0;
uniform float knee_bend_r : hint_range(0.0, 1.0) = 0.0;
uniform float wrinkles : hint_range(0.0, 2.0) = 0.7;          // how strong the bend wrinkles are
uniform float wrinkle_rest : hint_range(0.0, 1.0) = 0.45;     // how much of them a straight joint keeps (cloth never lies quite flat there)
uniform float wrinkles_per_metre = 40.0;   // the creases' spacing along the limb (40: one every 2.5 cm)
uniform float wrinkle_reach = 0.11;        // metres from the joint along the limb that the creases reach
uniform float wrinkle_wave = 0.35;         // how much a crease wanders round the limb (0: straight rings)
uniform float wrinkle_shade = 0.18;        // how much darker the folds' valleys are

varying vec3 local_pos;
varying vec3 local_normal;

// The GPU cloth solver (addons/godot_gpu_cloth, task 103): when it drives this mesh it sets these, and the simulated positions and normals come from its
// storage textures (the same lookup as the add-on's cloth_surface.gdshader). The pattern stays on the cloth's rest place (local_pos above), so the weave,
// the stains and the holes move with the fabric.
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

// a random number per cell of a 3D grid
float cell_rand(vec3 cell, float salt) {
	return hash3(cell + vec3(salt * 13.7, salt * 5.3, salt * 9.1));
}

float hash1(float n) {
	return fract(sin(n * 91.3458) * 47453.5453);
}

// The woven surface at `t` (thread units: warp threads run along t.y at whole t.x, weft threads along t.x at whole t.y), plain weave (over one,
// under one). x: height 0..1 (1 = a thread at its highest where it crosses over), y: which yarn shows (0 warp, 1 weft), z: the fibre shade along
// the thread (two-tone yarn), w: 1 on a thread, 0 in the gap between threads.
vec4 weave_at(vec2 t) {
	vec2 cell = floor(t);
	vec2 f = fract(t);
	// every thread its own thickness and a slow wander (hand-spun yarn is uneven)
	float warp_id = cell.x;
	float weft_id = cell.y;
	float warp_width = thread_width + thread_width_spread * hash1(warp_id * 3.1 + 0.7);
	float weft_width = thread_width + thread_width_spread * hash1(weft_id * 5.3 + 1.9);
	float warp_wander = thread_wander * sin(t.y * 0.37 + hash1(warp_id) * 6.28);
	float weft_wander = thread_wander * sin(t.x * 0.41 + hash1(weft_id + 11.0) * 6.28);
	float warp_c = (f.x - 0.5 - warp_wander) / (0.5 * warp_width);   // (across the warp thread: -1 .. 1)
	float weft_c = (f.y - 0.5 - weft_wander) / (0.5 * weft_width);
	float warp_round = sqrt(max(1.0 - warp_c * warp_c, 0.0));   // (a round yarn's profile)
	float weft_round = sqrt(max(1.0 - weft_c * weft_c, 0.0));
	// over or under: the warp is on top in half the cells; a thread rises to its top in the middle of a crossing and dips under the next
	bool warp_over = mod(cell.x + cell.y, 2.0) < 0.5;
	float rise_warp = sin(3.14159 * f.y);   // (along the warp)
	float rise_weft = sin(3.14159 * f.x);
	float warp_h = warp_round * (warp_over ? 0.55 + 0.45 * rise_warp : 0.55 - 0.3 * rise_warp);
	float weft_h = weft_round * (warp_over ? 0.55 - 0.3 * rise_weft : 0.55 + 0.45 * rise_weft);
	// the yarn's twist: fine diagonal ridges along each thread
	warp_h *= 1.0 - yarn_twist + yarn_twist * sin((t.y * 5.0 + f.x * 2.0) * 6.2831);
	weft_h *= 1.0 - yarn_twist + yarn_twist * sin((t.x * 5.0 + f.y * 2.0) * 6.2831);
	bool weft_shows = weft_h > warp_h;
	float h = max(warp_h, weft_h);
	// two-tone yarn: the fibres' shade changes along the thread (stretched noise), each thread its own
	float along = weft_shows ? t.x : t.y;
	float id = weft_shows ? weft_id + 503.0 : warp_id;
	float fibre = noise3(vec3(along * fibre_scale, id * 1.7, id * 0.31));
	fibre = smoothstep(0.25, 0.75, fibre + 0.25 * noise3(vec3(along * 9.0, id * 3.3, 7.0)));
	return vec4(h, weft_shows ? 1.0 : 0.0, fibre, step(0.001, h));
}

// The view-space tangent frame of a 2D parameter on the surface (Schüler's cotangent frame): works on the simulated cloth, whatever it does.
// The screen derivatives are taken by the caller, outside any branch (inside one they are undefined: lines along the triangles' edges).
mat3 cotangent_frame(vec3 n, vec3 dp1, vec3 dp2, vec2 duv1, vec2 duv2) {
	vec3 dp2perp = cross(dp2, n);
	vec3 dp1perp = cross(n, dp1);
	vec3 t = dp2perp * duv1.x + dp1perp * duv2.x;
	vec3 b = dp2perp * duv1.y + dp1perp * duv2.y;
	float invmax = inversesqrt(max(max(dot(t, t), dot(b, b)), 1e-20));
	return mat3(t * invmax, b * invmax, n);
}

void fragment() {
	float hem = COLOR.g;
	float belt = COLOR.r;
	if (!FRONT_FACING && hem < 0.03 && COLOR.a < 0.5) {
		discard;   // (vertex alpha 0: the shirt's armpits, where the sleeve and the body's shell overlap and a back face is not the cloth's inside; and
		// the trousers away from their openings. Everywhere else the inside is drawn: a look up a loose sleeve or under the hem sees cloth)
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
	// --- holes: small and ragged, mostly in the worn places, a few anywhere; not through the belt
	float hole_field = noise3(local_pos * 28.0 + seed_shift) * 0.7 + noise3(local_pos * 90.0 + seed_shift * 2.0) * 0.3;
	float hole_chance = imperfection * (0.04 + 0.9 * worn_zone + 0.25 * hem);
	float hole_level = 1.0 - 0.32 * hole_chance;   // (the field is above this where there is a hole)
	if (belt < 0.5 && hole_field > hole_level) {
		discard;
	}
	float fray = smoothstep(hole_level - 0.06, hole_level, hole_field) * smoothstep(0.0, 0.05, hole_chance);   // (the frayed ring round a hole:
	// loose light threads; none without holes: with no imperfection the noise's rare peaks still drew pale marks with no hole in them)
	// --- frayed hems: the very edge is ragged
	if (belt < 0.5 && hem > 0.9 && noise3(local_pos * 420.0 + seed_shift) > 1.25 - 0.4 * imperfection) {
		discard;
	}
	vec3 n_abs = abs(normalize(local_normal));
	// the weave, laid on the three axis planes of the cloth's rest shape and blended by how much the surface faces each (a hard switch between the
	// planes left rectangles of another pattern where the surface turned). Each plane: the woven height field (weave_at) gives the colour (two-tone
	// yarn, the shade in the gaps), the light (its slopes along the surface, a cotangent frame: it follows the simulated cloth) and, close up, real
	// depth: parallax occlusion along the view ray and the threads' own shadows toward the sun (SPOM). Far away it fades to the plain cloth colour.
	vec3 plane_weight = pow(n_abs, vec3(4.0));
	plane_weight /= plane_weight.x + plane_weight.y + plane_weight.z;
	vec3 view_n = normalize(NORMAL);
	vec3 view_dir = normalize(-VERTEX);
	vec3 sun_view = normalize((VIEW_MATRIX * vec4(sun_dir_world, 0.0)).xyz);
	// (every screen derivative here, before any branch)
	vec3 dp1 = dFdx(VERTEX);
	vec3 dp2 = dFdy(VERTEX);
	vec2 plane_uv[3] = vec2[3](local_pos.zy, local_pos.xz, local_pos.xy);
	vec2 duv1[3];
	vec2 duv2[3];
	for (int axis = 0; axis < 3; axis++) {
		duv1[axis] = dFdx(plane_uv[axis] * threads_per_metre);
		duv2[axis] = dFdy(plane_uv[axis] * threads_per_metre);
	}
	float weave_shade = 0.0;   // (0 in the gaps and the threads' own shadows .. 1 on top of a thread)
	float fibre_shade = 0.0;
	float slub = 0.0;
	float fade = 0.0;
	vec3 bump = vec3(0.0);   // (the view-space slope the weave adds to the normal)
	for (int axis = 0; axis < 3; axis++) {
		float w = axis == 0 ? plane_weight.x : (axis == 1 ? plane_weight.y : plane_weight.z);
		if (w < 0.01) {
			continue;
		}
		vec2 cloth_uv = plane_uv[axis];
		vec2 threads = cloth_uv * threads_per_metre;
		float per_pixel = length(abs(duv1[axis]) + abs(duv2[axis]));   // (threads a pixel)
		float plane_fade = 1.0 - smoothstep(0.4, 1.2, per_pixel);   // (finer than a pixel: no weave, it would only shimmer)
		if (plane_fade <= 0.0) {
			weave_shade += w;   // (too fine to draw: the plain cloth)
			fibre_shade += w * 0.5;
			slub += w * smoothstep(0.62, 0.9, noise3(vec3(cloth_uv.x * 40.0, cloth_uv.y * 900.0, 3.0 + float(axis))));
			continue;
		}
		mat3 frame = cotangent_frame(view_n, dp1, dp2, duv1[axis], duv2[axis]);   // (tangent along the threads' x, bitangent along y, in view space)
		// close up: march the height field along the view ray (parallax occlusion), then toward the sun for the threads' own shadows
		float near = 1.0 - smoothstep(pom_near * 0.5, pom_near, per_pixel);
		float lit = 1.0;
		if (near > 0.0) {
			vec3 v_ts = vec3(dot(view_dir, frame[0]), dot(view_dir, frame[1]), max(dot(view_dir, view_n), 0.15));
			float depth_threads = thread_height * threads_per_metre * weave_depth * pom_depth;   // (the weave's depth in thread units)
			float steps = float(pom_steps);
			vec2 step_uv = -v_ts.xy / v_ts.z * depth_threads / steps;
			vec2 t = threads;
			float layer = 1.0;
			float h = weave_at(t).x;
			for (int i = 0; i < pom_steps; i++) {
				if (h >= layer) {
					break;
				}
				layer -= 1.0 / steps;
				t += step_uv;
				h = weave_at(t).x;
			}
			threads = mix(threads, t, near);
			vec3 l_ts = vec3(dot(sun_view, frame[0]), dot(sun_view, frame[1]), dot(sun_view, view_n));
			if (l_ts.z > 0.05) {
				float shadow_steps = float(pom_shadow_steps);
				vec2 sun_step = l_ts.xy / l_ts.z * depth_threads / shadow_steps;
				float start = weave_at(t).x;
				float blocked = 0.0;
				for (int i = 1; i <= pom_shadow_steps; i++) {
					float ray = start + float(i) / shadow_steps;
					blocked = max(blocked, smoothstep(0.0, 0.15, weave_at(t + sun_step * float(i)).x - ray));
				}
				lit = mix(1.0, 1.0 - thread_shadow * blocked, near);
			}
		}
		vec4 wv = weave_at(threads);
		// the slopes of the height field (in thread units), as a view-space slope along the frame
		float e = 0.05;
		float hx = weave_at(threads + vec2(e, 0.0)).x - weave_at(threads - vec2(e, 0.0)).x;
		float hy = weave_at(threads + vec2(0.0, e)).x - weave_at(threads - vec2(0.0, e)).x;
		float slope = thread_height * threads_per_metre * weave_depth * weave_bump / (2.0 * e);
		bump += w * plane_fade * (frame[0] * hx + frame[1] * hy) * slope;
		weave_shade += w * mix(1.0, (gap_shade + (1.0 - gap_shade) * pow(wv.x, thread_roundness)) * lit, plane_fade);   // (the gaps between threads near black, as in a photo of the cloth)
		fibre_shade += w * mix(0.5, wv.z, plane_fade);
		slub += w * smoothstep(0.62, 0.9, noise3(vec3(cloth_uv.x * 40.0, cloth_uv.y * 900.0, 3.0 + float(axis))));
		fade += w * plane_fade;
	}
	// the cloth's colour: a slow mottle (an uneven dye), slubs (thicker threads), the two-tone yarn and the shade between the threads; faded and
	// dirty toward the hems with wear
	float mottle = fbm(local_pos * 6.0);
	vec3 base = cloth_color * (0.86 + 0.28 * mottle) * (1.0 - 0.06 * slub);
	base *= mix(1.0, (1.0 - yarn_mix * 0.5) + yarn_mix * fibre_shade, fade);   // (light and dark fibres)
	base *= mix(1.0 - 0.12 * weave_depth, mix(1.0, weave_shade, weave_depth), fade);   // (far: the gaps' shade averaged in)
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
	float worn = worn_zone * imperfection;
	base = mix(base, base * vec3(1.12, 1.1, 1.05), worn * 0.6);
	base = mix(base, vec3(0.85, 0.8, 0.72) * cloth_color * 1.3, fray * 0.6);
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
	if (bump_debug > 0.5) {
		ALBEDO = bump_heat(bump_off);
	}
	ROUGHNESS = rough;
	SPECULAR = 0.3;
	// the creases of hanging cloth: a soft, mostly vertical wave in the normal (folds run down a hanging sleeve and leg), and the weave's bump
	vec3 fold_p = local_pos * vec3(18.0, 3.0, 18.0);
	float fx = fbm(fold_p + vec3(0.13, 0.0, 0.0)) - fbm(fold_p - vec3(0.13, 0.0, 0.0));
	float fz = fbm(fold_p + vec3(0.0, 0.0, 0.13)) - fbm(fold_p - vec3(0.0, 0.0, 0.13));
	vec3 bend = vec3(fx, 0.0, fz) * folds * 1.4 * (1.0 - belt);
	// bend wrinkles: a fan of creases round the limb at each bent joint (a wave along the limb's axis, wandering round it, fading with the distance
	// from the joint and toward the outside of the bend); the slope goes into the light, the valleys get a little darker
	vec3 wrinkle_slope = vec3(0.0);
	float wrinkle_valley = 0.0;
	if (has_joints && wrinkles > 0.0) {
		vec3 wn = normalize(local_normal);
		for (int i = 0; i < 4; i++) {
			vec3 joint = i == 0 ? elbow_l : (i == 1 ? elbow_r : (i == 2 ? knee_l : knee_r));
			vec3 axis = normalize(i == 0 ? elbow_axis_l : (i == 1 ? elbow_axis_r : (i == 2 ? knee_axis_l : knee_axis_r)));
			float bent = i == 0 ? elbow_bend_l : (i == 1 ? elbow_bend_r : (i == 2 ? knee_bend_l : knee_bend_r));
			vec3 inside = i < 2 ? elbow_inside : knee_inside;
			vec3 d = local_pos - joint;
			float along = dot(d, axis);
			float reach = 1.0 - smoothstep(0.0, wrinkle_reach, abs(along));
			float radial = length(d - axis * along);
			reach *= 1.0 - smoothstep(0.08, 0.14, radial);   // (the limb only, not the body beside it)
			if (reach <= 0.0) {
				continue;
			}
			float side = 0.5 + 0.5 * dot(wn, normalize(inside));   // (1 on the inside of the bend)
			float amount = wrinkles * mix(wrinkle_rest, 1.0, bent) * reach * mix(0.25, 1.0, side * side);
			float wander = wrinkle_wave * (noise3(local_pos * 25.0 + float(i) * 7.0) - 0.5) / wrinkles_per_metre * 6.0;
			float phase = (along + wander) * wrinkles_per_metre * 6.2831;
			float crease = sin(phase);
			// the slope along the axis (the crease's side), into the light
			wrinkle_slope += axis * cos(phase) * amount * 0.6;
			wrinkle_valley = max(wrinkle_valley, amount * max(-crease, 0.0));
		}
	}
	ALBEDO *= 1.0 - wrinkle_shade * wrinkle_valley * (1.0 - belt);
	NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(bend + (MODEL_MATRIX * vec4(wrinkle_slope, 0.0)).xyz, 0.0)).xyz - bump * (1.0 - belt));
	RIM = sheen * (1.0 - belt);
	RIM_TINT = 0.6;
}
