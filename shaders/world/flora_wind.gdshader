shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;
// Low-poly plants and rocks, in two looks that blend with `realism`. The vertex colour is the
// paint; its alpha says how much that vertex sways in the wind (0: trunk, rock; 1: leaf tips,
// grass blades). The wind is global, so a gust crosses the whole forest the same way.
// Low-poly: flat shading. Realistic: the mesh's smooth normals, leaf-scale colour variation, light
// shining through the leaves and a soft rim.

global uniform float wind_strength;
global uniform float snow_cover;
global uniform float autumn;
global uniform float realism;
global uniform vec2 wind_direction;
uniform float sway_speed = 1.3;
uniform bool planks = false; // wood boards (a cabin) instead of tree bark

varying float face_up;
varying vec3 world_pos;
varying float sway;
varying vec3 obj_pos;
varying float obj_up;

float cell_hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

// smooth 0..1 noise: the cell corners blended, so colours drift instead of jumping
float smooth_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = smoothstep(0.0, 1.0, fract(p));
	return mix(mix(cell_hash(cell), cell_hash(cell + vec2(1.0, 0.0)), f.x),
			mix(cell_hash(cell + vec2(0.0, 1.0)), cell_hash(cell + vec2(1.0, 1.0)), f.x), f.y);
}

float hash13(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = smoothstep(0.0, 1.0, fract(p));
	return mix(mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x),
			mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x),
			mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

// The bark of a tube (the native grower writes UV.x = -(1 + the way round, 0..1), UV.y = metres along the
// branch, UV2.x = the tube's radius): furrows running along it, deep cracks between the ridges, fine grain.
// Returns x: the shade, y: the height of the surface (for the bump), z: how deep a crack is.
vec3 bark_at(vec2 around_along, float radius, float trunk) {
	float angle = around_along.x * 6.2831853;
	float spacing = clamp(radius * 0.4, 0.012, 0.11); // the furrows are wider on a thicker trunk
	vec3 p = vec3(cos(angle) * radius / spacing, sin(angle) * radius / spacing, around_along.y / (spacing * 4.5));
	float broad = noise3(p * 0.5 + 3.0); // where the bark is rougher
	float furrow = noise3(p + broad * 1.4);
	float fine = noise3(p * 2.7 + vec3(7.0, 1.0, 3.0));
	float grain = noise3(p * 7.0 + vec3(1.0, 9.0, 5.0));
	float crack = 1.0 - smoothstep(0.0, 0.1 + 0.08 * broad, abs(furrow - 0.5));
	float ridge = smoothstep(0.25, 0.75, furrow);
	float height = ridge * 0.7 + fine * 0.2 + grain * 0.1 - crack * 0.5;
	float shade = mix(0.5, 1.15, ridge) * (1.0 - 0.45 * crack) * (0.85 + 0.3 * grain) * (0.9 + 0.2 * fine);
	return vec3(shade, height * mix(0.35, 1.0, trunk), crack);
}

vec2 hash22(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

// A cluster of small leaves on a card (UV 0..1, the stalk at the bottom): leaves in a 5 x 5 grid, each
// with its own size, turn (mostly pointing out from the stalk), shade and veins; the one drawn on top
// where two overlap is the one with the larger dice. Returns x: 1 inside a leaf (0 outside), y: the shade.
vec2 leaf_cluster(vec2 uv, float id) {
	const float N = 5.0;
	vec2 p = uv * N;
	vec2 cell = floor(p);
	float best = -1.0;
	float inside_leaf = 0.0;
	float shade = 1.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 c = cell + vec2(float(i), float(j));
			vec2 h = hash22(c + id * 13.7);
			vec2 h2 = hash22(c * 1.7 + 5.3 + id * 7.1);
			vec2 centre = c + 0.5 + (h - 0.5) * 0.7;
			vec2 at = centre / N;
			if (at.x < 0.14 || at.x > 0.86 || at.y < 0.08 || at.y > 0.86) {
				continue; // a leaf must lie whole on the card
			}
			vec2 outward = normalize(centre - vec2(0.5 * N, -0.5 * N));
			float angle = atan(outward.x, outward.y) + (h2.x - 0.5) * 1.5;
			float cs = cos(angle);
			float sn = sin(angle);
			vec2 d = p - centre;
			vec2 q = vec2(d.x * cs - d.y * sn, d.x * sn + d.y * cs);
			float length_cells = 0.85 + h2.y * 0.45;
			float width_cells = 0.34 + h.x * 0.14;
			float t = q.y / length_cells + 0.5;
			if (t > 0.0 && t < 1.0) {
				float half_width = width_cells * 0.5 * sin(3.14159 * pow(t, 0.8));
				if (abs(q.x) < half_width && h.y > best) {
					best = h.y;
					inside_leaf = 1.0;
					float across = abs(q.x) / max(half_width, 0.001);
					float rib = 1.0 - smoothstep(0.0, 0.07, abs(q.x) / width_cells);
					float run = fract(t * 5.0 - across * 1.6 + h.x);
					float side_vein = (1.0 - smoothstep(0.0, 0.16, min(run, 1.0 - run))) * (1.0 - across) * 0.7;
					shade = (0.72 + 0.5 * h2.x) * (1.0 - 0.22 * across * across) + max(rib, side_vein) * 0.28;
				}
			}
		}
	}
	return vec2(inside_leaf, shade);
}

// The leaflets of a palm or fern frond on a strip along its rib (UV.x 0 at the rib .. 1 at the leaflet tips,
// UV.y 0..1 down the frond): narrow leaflets swept toward the tip, each its own length and width, with a midrib
// and a darker edge. Returns x: 1 inside a leaflet, y: the shade.
vec2 pinnate(vec2 uv, float rows, float id, float needles) {
	float y = uv.y * rows;
	float x = uv.x;
	float slanted = y - x * mix(1.1, 1.5, needles); // needles point more forward than leaflets
	float row = floor(slanted);
	vec2 h = hash22(vec2(row, id * 17.0));
	float cut = 0.78 + 0.22 * h.x; // each leaflet's own length
	float half_width = mix(0.34, 0.24, needles) * (0.75 + 0.5 * h.y) * pow(max(1.0 - x / cut, 0.0), 0.55) * smoothstep(0.0, 0.07, x);
	float across = abs(fract(slanted) - 0.5);
	float inside_leaflet = (across < half_width && x < cut) ? 1.0 : 0.0;
	float rib = 1.0 - smoothstep(0.0, 0.05, across);
	float shade = (0.8 + 0.35 * h.y) * (1.0 - 0.25 * across / max(half_width, 0.01)) + rib * 0.15;
	return vec2(inside_leaflet, shade);
}

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_pos = world;
	sway = COLOR.a;
	obj_pos = VERTEX;
	obj_up = NORMAL.y;
	float weight = COLOR.a;
	float gust = sin(TIME * sway_speed + dot(world.xz, vec2(0.11, 0.08))) * 0.5 + 0.5;
	float flutter = sin(TIME * sway_speed * 3.3 + dot(world.xz, vec2(0.9, 0.7)) + VERTEX.y * 2.0);
	float amount = weight * (0.03 + wind_strength * 0.5) * (gust * 0.8 + flutter * 0.2);
	vec3 push = vec3(wind_direction.x, 0.0, wind_direction.y) * amount;
	face_up = (MODEL_MATRIX * vec4(NORMAL, 0.0)).y;
	VERTEX += inverse(mat3(MODEL_MATRIX)) * push;
}

void fragment() {
	vec3 paint = pow(COLOR.rgb, vec3(2.2)); // the palette is written in sRGB
	// autumn: whatever is green turns yellow, orange and brown
	float leafy = smoothstep(0.0, 0.08, paint.g - max(paint.r, paint.b));
	vec3 warm = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float which = smooth_noise(warm.xz * 0.035);
	vec3 turned = mix(vec3(paint.g * 1.6, paint.g * 1.0, paint.g * 0.2),
			vec3(paint.g * 1.3, paint.g * 0.38, paint.g * 0.1), which);
	paint = mix(paint, turned, autumn * leafy);
	// the realistic look: leaf-scale variation, lighter tips
	float speckle = smooth_noise(world_pos.xz * 5.0 + world_pos.y * 3.0);
	paint *= mix(1.0, 0.8 + 0.4 * speckle, realism);
	// leaves (they have a UV, nothing else does): a light midrib, side veins running up and out from
	// it, and the blade a little lighter along the middle and darker toward the edge
	bool is_card = UV2.y > 1.5;
	float card_alpha = 1.0;
	if (is_card) {
		bool is_pin = UV2.y > 3.5;
		float needles = UV2.y > 5.5 ? 1.0 : 0.0;
		float rows = (UV2.y - mix(4.0, 6.0, needles)) * 100.0;
		vec2 cluster = is_pin ? pinnate(UV, rows, UV2.x, needles) : leaf_cluster(UV, UV2.x);
		// far away the leaves are under a pixel and would shimmer: the card fills in toward a solid mass
		float far_fill = smoothstep(0.35, 0.8, is_pin ? fwidth(UV.y) * rows : fwidth(UV.x) * 5.0);
		far_fill *= smoothstep(5.0, 18.0, length(VERTEX)); // (a card seen edge on near the eye is not a distant one)
		card_alpha = mix(cluster.x, 0.62, far_fill);
		paint *= mix(cluster.y, 0.9, far_fill);
	}
	if (UV.x > 0.001 && !is_card) {
		// every leaf has its own two random numbers (UV2): how many side veins, how they slope,
		// how thick and how strong they are, whether the two sides line up, how dark the edge is
		float id = UV2.x;
		float k = UV2.y;
		float across = abs(UV.x - 0.5) * 2.0; // 0 on the midrib .. 1 at the edge
		float count = mix(3.5, 9.5, fract(id * 5.7 + 0.3));
		float slope = mix(1.4, 3.8, fract(id * 3.1 + k));
		float thick = mix(0.1, 0.3, fract(k * 7.9));
		float strength = mix(0.3, 1.0, fract(id * 11.3 + k * 2.0));
		float mid_width = mix(0.07, 0.16, fract(k * 4.3 + id));
		float edge_dark = mix(0.1, 0.34, fract(id * 2.3 + k * 5.1));
		float sides = step(UV.x, 0.5) * fract(id * 9.1) * 0.6; // the two sides need not line up
		float midrib = 1.0 - smoothstep(0.02, mid_width, across);
		float run = fract(UV.y * count - across * slope + sides + id * 4.0);
		float side_vein = (1.0 - smoothstep(0.0, thick, min(run, 1.0 - run)))
				* smoothstep(0.06, 0.15, across) * (1.0 - smoothstep(0.6, 0.95, across));
		float vein = max(midrib * mix(0.6, 1.0, strength), side_vein * strength);
		float shade = 1.04 - edge_dark * across * across - 0.1 * UV.y;
		paint = mix(paint * shade, paint * 1.55 + vec3(0.02, 0.03, 0.0), vein * 0.9);
	}
	vec2 bump = vec2(0.0);
	float bump_amount = 0.0;
	float surface_height = 0.0;
	float surface_bump = 0.0;
	bool is_bark = UV.x < -0.5;
	bool is_rock = UV.x < -0.1 && !is_bark; // add_rock marks its stones
	if (realism > 0.001 && is_bark && !planks) {
		float trunk = 1.0 - smoothstep(0.1, 0.3, sway);
		vec3 bark = bark_at(vec2(-UV.x - 1.0, UV.y), UV2.x, trunk);
		paint *= mix(1.0, bark.x, realism);
		// moss at the foot of a trunk, thicker on the damp side, and pale lichen patches higher up
		float damp = noise3(vec3(world_pos.xz * 0.6, world_pos.y * 0.3));
		float moss = smoothstep(0.5, 0.72, damp + (1.6 - obj_pos.y) * 0.18) * smoothstep(2.4, 0.2, obj_pos.y) * trunk;
		paint = mix(paint, vec3(0.1, 0.2, 0.05) * (0.7 + 0.6 * bark.x), moss * realism * (1.0 - bark.z * 0.7));
		float lichen = smoothstep(0.7, 0.85, noise3(vec3(world_pos.xz * 1.7, world_pos.y * 1.3) + 11.0)) * trunk;
		paint = mix(paint, vec3(0.16, 0.19, 0.12), lichen * 0.55 * realism);
		surface_height = bark.y;
		surface_bump = realism * (0.5 + 0.5 * trunk);
	} else if (realism > 0.001 && sway < 0.1 && (UV.x < 0.001)) { // (a fallen leaf has a UV: not stone)
		float brown = smoothstep(0.02, 0.1, paint.r - paint.b);
		if (planks) {
			// boards: lines every 25 cm, a grain along the board and a different tone per board
			float board = floor(obj_pos.y * 4.0 + 0.5);
			float edge = smoothstep(0.0, 0.08, abs(fract(obj_pos.y * 4.0 + 0.5) - 0.5) * 2.0);
			float grain = smooth_noise(vec2((obj_pos.x + obj_pos.z) * 2.0, obj_pos.y * 18.0 + board * 7.0));
			paint *= mix(1.0, (0.78 + 0.3 * cell_hash(vec2(board, 3.0))) * (0.85 + 0.3 * grain) * (0.6 + 0.4 * edge), realism * brown);
			bump = vec2(0.0, (edge - 0.5) * 0.6);
			bump_amount = realism * brown;
		} else if (!is_rock && brown > 0.5 && abs(obj_up) < 0.5) {
			// bark: long furrows around the trunk, bright ridges between them
			float around = atan(obj_pos.x, obj_pos.z) * 4.0;
			float furrow = smooth_noise(vec2(around, obj_pos.y * 0.7));
			float ridge = smoothstep(0.35, 0.65, furrow);
			paint *= mix(1.0, 0.55 + 0.7 * ridge, realism);
			bump = vec2((furrow - 0.5) * 1.4, 0.0);
			bump_amount = realism;
		} else {
			// stone: strata, cracks, grain at three scales and patches of lichen (all in the rock's own space,
			// so each rock has its own pattern), the cracks and grain bumped
			vec3 op = obj_pos;
			float broad = noise3(op * 1.7 + 5.0);
			float bands = 0.5 + 0.5 * sin((op.y + 0.35 * op.x + 0.25 * broad) * 14.0);
			// joints: thin cracks that run mostly across the rock, only in some parts of it
			float crack_n = noise3(op * vec3(2.5, 11.0, 2.5) + broad * 1.5);
			float crack = (1.0 - smoothstep(0.0, 0.03, abs(crack_n - 0.5))) * smoothstep(0.4, 0.65, noise3(op * 1.3 + 17.0));
			float grain = noise3(op * 38.0);
			float speck = noise3(op * 90.0);
			float patch = smooth_noise(world_pos.xz * 1.6 + world_pos.y * 1.3);
			float shade = (0.78 + 0.3 * bands) * (0.82 + 0.3 * grain) * (0.9 + 0.2 * speck) * (1.0 - 0.4 * crack)
					* (0.88 + 0.24 * patch);
			paint *= mix(1.0, shade, realism);
			paint = mix(paint, paint * vec3(0.7, 1.0, 0.55), realism * smoothstep(0.62, 0.8, patch) * 0.45 * smoothstep(0.2, 0.9, obj_up));
			surface_height = broad * 0.4 + bands * 0.15 + grain * 0.15 + speck * 0.1 - crack * 0.5;
			surface_bump = realism * 1.3;
		}
	}
	ALBEDO = mix(paint, vec3(0.8, 0.84, 0.9), snow_cover * smoothstep(0.35, 0.75, face_up) * 0.9);
	if (is_card) {
		ALPHA = card_alpha;
		ALPHA_SCISSOR_THRESHOLD = 0.5;
	}
	// normals: flat facets, or the mesh's smooth ones
	vec3 flat_normal = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	if (dot(flat_normal, VIEW) < 0.0) {
		flat_normal = -flat_normal;
	}
	vec3 smooth_normal = NORMAL;
	if (!FRONT_FACING) {
		smooth_normal = -smooth_normal;
	}
	NORMAL = normalize(mix(flat_normal, smooth_normal, realism));
	if (bump_amount > 0.001) {
		NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(bump.x, 0.0, bump.y, 0.0)).xyz * 0.35 * bump_amount);
	}
	if (surface_bump > 0.001) {
		// a normal tilted by how the height changes across the pixel (screen-space bump mapping)
		vec3 dpdx = dFdx(VERTEX);
		vec3 dpdy = dFdy(VERTEX);
		vec3 r1 = cross(dpdy, NORMAL);
		vec3 r2 = cross(NORMAL, dpdx);
		float det = dot(dpdx, r1);
		float strength = 0.12 * surface_bump * clamp(12.0 / max(length(VERTEX), 1.0), 0.0, 1.0);
		vec3 gradient = sign(det) * (dFdx(surface_height) * r1 + dFdy(surface_height) * r2);
		NORMAL = normalize(abs(det) * NORMAL - strength * gradient);
	}
	ROUGHNESS = mix(0.92, 0.78, realism);
	SPECULAR = 0.2;
	float leafy_part = is_bark ? 0.0 : 1.0;
	BACKLIGHT = paint * 0.35 * realism * smoothstep(0.1, 0.5, sway) * leafy_part; // light through the leaves
	RIM = 0.25 * realism * smoothstep(0.1, 0.5, sway) * leafy_part;
	RIM_TINT = 0.5;
}
