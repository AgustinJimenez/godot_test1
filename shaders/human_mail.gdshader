shader_type spatial;
// Riveted ring mail (a hauberk) for the parametric humans (garment recipes: tools/blender/build_outfit.py, material "mail"). Simulated as heavy,
// floppy cloth by the GPU cloth solver; the rings are drawn, not modelled: European four-in-one, rows of rings each half a ring from the next and
// shifted half a ring sideways, every ring through four others. The rings lie on the garment's rest place (local_pos, three planes blended by the
// rest normal), so they move with the mail. Steel: metallic, the gaps dark (the cloth under it), grime in the gaps, a little rust, worn bright on
// the high points. Vertex colour from the builder: G = how close to an edge (1 at the edge), A = draw the inside.
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec3 cloth_color : source_color = vec3(0.56, 0.57, 0.6);   // the steel (the labs set every garment's colour under this name)
uniform float rings_per_metre = 95.0;      // ring pitch: 95 = rings ~11 mm across
uniform float ring_radius = 0.43;          // the ring's radius, in pitches (over 0.25: each ring overlaps the rows round it)
uniform float wire = 0.085;                // the wire's half thickness, in pitches
uniform float ring_depth = 0.6;            // how strongly the rings' relief shows in the light
uniform float row_tilt = 0.35;             // every other row lies over the next (the rings lean on each other)
uniform float roughness_steel : hint_range(0.0, 1.0) = 0.38;
uniform float gap_color = 0.04;            // what shows between the rings (the padding under the mail)
uniform float grime = 0.5;                 // dark grime and oil settled in the gaps and toward the hem
uniform float rust = 0.2;                  // rust spots
uniform float polish = 0.4;                // the rings' high points rubbed bright
uniform float flaw_seed = 0.0;

varying vec3 local_pos;
varying vec3 local_normal;

// The GPU cloth solver (addons/godot_gpu_cloth) drives this mesh through these, as in human_clothes.gdshader.
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
}

// The mail on one plane at t (in pitches): x the height (0 in a gap .. ~1 on the top of a wire), y 1 on a wire / 0 in a gap.
vec2 mail_at(vec2 t) {
	float row0 = floor(t.y * 2.0);
	float best = 0.0;
	float on = 0.0;
	for (int dr = -2; dr <= 2; dr++) {
		float row = row0 + float(dr);
		float shift = 0.5 * mod(row, 2.0);
		float cy = row * 0.5;
		float c0 = floor(t.x - shift);
		for (int dc = -1; dc <= 1; dc++) {
			vec2 c = vec2(c0 + float(dc) + shift + 0.5, cy + 0.25);
			vec2 d = t - c;
			float across = (length(d) - ring_radius) / wire;
			if (abs(across) < 1.0) {
				// the wire's round profile, the ring leaning on the row below (every other row on top)
				float h = sqrt(1.0 - across * across);
				h = h * 0.75 + 0.25 * (0.5 + row_tilt * d.y / ring_radius) + 0.12 * mod(row, 2.0);
				if (h > best) {
					best = h;
				}
				on = 1.0;
			}
		}
	}
	return vec2(best, on);
}

// the three planes, blended by the rest normal
vec2 mail3(vec3 p, vec3 w) {
	vec2 a = mail_at(p.zy * rings_per_metre);
	vec2 b = mail_at(p.xz * rings_per_metre);
	vec2 c = mail_at(p.xy * rings_per_metre);
	return a * w.x + b * w.y + c * w.z;
}

void fragment() {
	if (!FRONT_FACING && COLOR.a < 0.5) {
		discard;
	}
	vec3 w = pow(abs(normalize(local_normal)), vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec3 seed_shift = vec3(flaw_seed * 17.31, flaw_seed * 5.17, flaw_seed * 9.73);
	// finer than about two pixels per ring the pattern fades to its average (no shimmer)
	float pitch_px = 1.0 / max(length(fwidth(local_pos * rings_per_metre)), 1e-6);
	float detail = smoothstep(2.0, 5.0, pitch_px);
	vec2 m = mail3(local_pos, w);
	float e = 0.12 / rings_per_metre;
	vec3 slope = vec3(mail3(local_pos + vec3(e, 0.0, 0.0), w).x - m.x, mail3(local_pos + vec3(0.0, e, 0.0), w).x - m.x,
			mail3(local_pos + vec3(0.0, 0.0, e), w).x - m.x) / (e * rings_per_metre);
	float on = mix(0.72, m.y, detail);   // (far off: about 72% of the surface is wire)
	float height = mix(0.5, m.x, detail);
	// steel, grime in the gaps and low on the wire, rust spots, the tops polished
	float dirt = grime * (0.5 + 0.5 * fbm(local_pos * 14.0 + seed_shift)) * (1.0 - height);
	float rust_spot = rust * smoothstep(0.62, 0.8, fbm(local_pos * 30.0 + seed_shift + 3.7));
	vec3 steel = cloth_color * (1.0 - 0.6 * dirt);
	steel = mix(steel, vec3(0.32, 0.16, 0.07), rust_spot);
	steel = mix(steel, cloth_color * 1.25, polish * smoothstep(0.75, 1.0, height) * detail);
	vec3 gap = vec3(gap_color);
	ALBEDO = mix(gap, steel, on);
	if (bump_debug > 0.5) {
		ALBEDO = bump_heat(bump_off);
	}
	METALLIC = bump_debug > 0.5 ? 0.0 : on * (1.0 - rust_spot);
	ROUGHNESS = mix(0.9, mix(roughness_steel, 0.75, max(dirt, rust_spot)), on);
	SPECULAR = 0.5;
	AO = mix(0.35, 1.0, mix(height, 1.0, 1.0 - on));
	AO_LIGHT_AFFECT = 0.6;
	if (!FRONT_FACING) {
		ALBEDO *= 0.3;   // (the inside)
	}
	vec3 bump = slope * ring_depth * 0.15 * detail;
	NORMAL = normalize(NORMAL - (VIEW_MATRIX * (MODEL_MATRIX * vec4(bump, 0.0))).xyz);
}
