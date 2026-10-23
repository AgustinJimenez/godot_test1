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
global uniform vec3 cloud_sun_world; // toward the star, world space (the planet sets it)
uniform float sway_speed = 1.3;
uniform float bark_debug = 0.0; // 1: the bark's height as grey, 2: the cells (a tool)
uniform float bark_force = -1.0; // >= 0: every bark gets this look (a tool)
uniform vec2 bark_style_force = vec2(-1.0); // x >= 0: every tree gets this bark_style (a tool: a fair side-by-side)
uniform bool planks = false; // wood boards (a cabin) instead of tree bark
// A tree near the walker, bent branch by branch (PlantSway): row 0 of the texture holds each branch's foot and its parent's id, row 1
// its turn (a rotation vector about the foot, relative to the parent). A vertex's branch is CUSTOM0.x (0: the trunk, never moves).
uniform bool bendable = false;
uniform sampler2D bend_data : filter_nearest, repeat_disable;
uniform vec4 live_tint : source_color = vec4(1.0); // (the colour a tree has in a MultiMesh comes with each instance, not the mesh)

varying float face_up;
varying vec3 world_pos;
varying float sway;
varying vec3 obj_pos;
varying float obj_up;
varying vec2 bark_style; // from the tree's own place: which bark it has
varying float bark_kind; // 0 oak, 1 birch, 2 pine, 3 ash, 4 maple, 5 rings (palm), 6 cedar (the grower writes it in UV2.y of a trunk)
varying float view_dist; // metres from the eye (the photo's mip level)
varying vec3 obj_normal; // the surface normal in the mesh's own space (a rock's triplanar picture)
varying float obj_scale; // metres per mesh unit (a rock's size: the picture keeps its real size)
uniform sampler2DArray rock_photo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float rock_photo_on = 1.0; // 0: only the procedural stone
uniform sampler2DArray bark_photo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float bark_photo_on = 1.0; // 0: only the procedural bark
uniform float bark_pom = 1.0; // 0: no parallax march and no bump shadow (a tool: what they cost)

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
// The bark of a tube as plates (the native grower writes UV.x = -(1 + the way round, 0..1), UV.y = metres along the branch,
// UV2.x = the tube's radius): a staggered field of cells stretched along the trunk (a Voronoi diagram, the number of cells round
// a whole one so the pattern closes), each cell a plate with its own height, the gaps between them deep cracks. `style` (from the
// tree's own place) makes one tree's plates broad and short, another's narrow and long. Returns the height (1 the top of a
// plate, 0 the bottom of a crack); crack: 0 in a crack .. 1 on a plate; tone: the plate's own shade (0..1).
float bark_height_cells(vec2 aa, float radius, vec2 style, out float crack, out float tone) {
	int kind = int(bark_kind + 0.5);
	float spread = 1.0;
	float stretch_lo = 2.0;
	float stretch_hi = 5.5;
	float blockiness = 0.55;
	float crack_edge = 0.2;
	if (kind == 0) { // oak: long, interrupted ridges with deep furrows between
		spread = 0.65;
		stretch_lo = 4.0;
		stretch_hi = 9.0;
		blockiness = 0.85;
	} else if (kind == 4) { // maple: wide smooth plates, thin cracks
		spread = 1.7;
		stretch_lo = 7.0;
		stretch_hi = 15.0;
		blockiness = 0.9;
		crack_edge = 0.1;
	}
	float width = clamp(radius * 0.45, 0.04, 0.9) * mix(0.7, 1.5, style.x) * spread;
	float count = max(3.0, floor(6.2831853 * radius / width + 0.5));
	float length_m = width * mix(stretch_lo, stretch_hi, style.y);
	if (kind == 1) { // birch: nearly smooth, dark horizontal dashes (lenticels), the odd curl of peeling
		float dash_zone = noise3(vec3(aa.x * count * 1.2, aa.y * 1.4, 2.0));
		float dashes = noise3(vec3(aa.x * count * 2.2, aa.y * 55.0, 9.0));
		float mark = smoothstep(0.7, 0.8, dashes) * smoothstep(0.35, 0.6, dash_zone);
		float band = smoothstep(0.82, 0.9, noise3(vec3(aa.x * count * 0.4, aa.y * 7.0, 4.0)));
		crack = 1.0 - max(mark * 0.85, band * 0.7);
		tone = noise3(vec3(aa.x * count, aa.y * 3.0, 6.0));
		return 0.78 + 0.1 * (tone - 0.5) - band * 0.25;
	}
	if (kind == 3) { // ash: a lattice of diamond-shaped ridges
		float cells = max(3.0, floor(count * 1.1));
		float u = aa.x * cells * 2.0;
		float v = aa.y / (width * 0.75);
		float warp = (noise3(vec3(aa.x * count * 0.8, aa.y * 2.0, 1.0)) - 0.5) * 1.5;
		float f1 = fract((u + v) * 0.5 + warp);
		float f2 = fract((u - v) * 0.5 - warp);
		float g = min(min(f1, 1.0 - f1), min(f2, 1.0 - f2));
		tone = cell_hash(vec2(floor((u + v) * 0.5), floor((u - v) * 0.5)) + 3.3);
		crack = smoothstep(0.02, 0.16, g);
		return 0.25 + 0.5 * smoothstep(0.0, 0.3, g) * (0.7 + 0.3 * tone);
	}
	if (kind == 6 || kind == 5) { // cedar: stringy strands running along the trunk, breaking here and there; 5: bands (palm rings)
		if (kind == 5) {
			float band = aa.y / max(radius * 0.7, 0.05);
			float g = abs(fract(band) - 0.5) * 2.0;
			tone = noise3(vec3(aa.x * count, band, 2.0));
			crack = smoothstep(0.0, 0.5, 1.0 - g * g) * 0.7 + 0.3;
			return 0.35 + 0.5 * smoothstep(0.1, 0.8, g);
		}
		float u = aa.x * count * 2.6 + (noise3(vec3(aa.x * count * 0.6, aa.y * 0.5, 5.0)) - 0.5) * 1.4; // (broad ropes, a slow sway: finer ones read as reeds up close)
		float strand = floor(u);
		float f = fract(u);
		float broken = noise3(vec3(strand * 0.7, aa.y * 1.8, 8.0)); // (long fibres, broken far apart)
		float furrow = 0.7 + 0.5 * noise3(vec3(aa.x * count * 0.45, aa.y * 0.35, 3.0)); // (wide shallow furrows across the ropes)
		tone = cell_hash(vec2(strand, floor(aa.y * 3.0 + cell_hash(vec2(strand, 1.0)) * 4.0)));
		float ridge = smoothstep(0.0, 0.35, f) * smoothstep(1.0, 0.65, f);
		crack = mix(0.5, 1.0, ridge) * smoothstep(0.1, 0.4, broken + 0.2);
		return 0.3 + 0.35 * ridge * furrow * (0.55 + 0.45 * tone) * smoothstep(0.1, 0.45, broken + 0.2);
	}
	float edge_sharp = crack_edge;
	float shift = cell_hash(vec2(floor(aa.x * count), 3.7 + style.x)) * (kind == 0 ? 3.0 : 0.0);
	vec2 p = vec2(aa.x * count, aa.y / length_m + shift);
	p += (vec2(smooth_noise(p * 0.8 + 5.0), smooth_noise(p * 0.8 + 17.0)) - 0.5) * vec2(0.5, 0.9);
	vec2 cell = floor(p);
	float f1 = 9.0;
	float f2 = 9.0;
	vec2 id = vec2(0.0);
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 c = cell + vec2(float(i), float(j));
			vec2 wrapped = vec2(mod(c.x, count), c.y);
			vec2 h = hash22(wrapped + style * 31.0);
			vec2 d = p - (c + 0.5 + (h - 0.5) * 0.75);
			float dist = mix(length(d), max(abs(d.x), abs(d.y)), blockiness); // (rounded blocks, not diamonds)
			if (dist < f1) {
				f2 = f1;
				f1 = dist;
				id = wrapped;
			} else if (dist < f2) {
				f2 = dist;
			}
		}
	}
	float edge = f2 - f1;
	tone = cell_hash(id + 9.1);
	crack = smoothstep(edge_sharp * 0.15, edge_sharp, edge);
	float flakes = noise3(vec3(aa.x * count * 2.5, aa.y / length_m * 2.0, tone * 10.0));
	float strands = noise3(vec3(aa.x * count * 9.0, aa.y / length_m * 0.7, tone * 5.0 + 3.0)); // (grain running along the trunk)
	float top = 0.55 + 0.4 * tone;
	float plate = kind == 4 ? 0.35 : 0.5;
	return clamp(smoothstep(0.0, plate, edge) * top + (0.04 * (flakes - 0.5) + 0.035 * (strands - 0.5)) * smoothstep(0.0, 0.4, edge), 0.0, 1.0);
}

// Real bark (Poly Haven, CC0; assets/textures/bark/bark_atlas.png, built by tools/build_bark_atlas.gd): one 1024 px slot a bark
// kind, the photo's colour in rgb and its height in alpha. BARK_TILE is the metres one picture covers (width, height).
const vec2 BARK_TILE[6] = vec2[6](vec2(2.15, 2.15), vec2(2.0, 2.0), vec2(1.0, 1.0), vec2(1.8, 1.8), vec2(1.3, 1.3), vec2(1.0, 2.0));

// The slot of a bark kind: oak 0, pine 1, ash 2, maple 3, palm 4, cedar 5; -1 (birch) keeps the procedural bark.
int photo_layer(int kind) {
	if (bark_photo_on < 0.5) {
		return -1;
	}
	return kind == 0 ? 0 : (kind == 2 ? 1 : (kind == 3 ? 2 : (kind == 4 ? 3 : (kind == 5 ? 4 : (kind == 6 ? 5 : -1)))));
}

// The photo at a place on the trunk (aa: the way round 0..1, metres along). It tiles a whole number of times round the trunk,
// each tree shifted its own way, and is cut to the pixel's size by the mip level.
vec4 photo_sample(vec2 aa, float radius, vec2 style, int layer) {
	vec2 tile = BARK_TILE[layer];
	float circ = 6.2832 * max(radius, 0.02);
	float count = max(floor(circ / tile.x + 0.5), 1.0);
	float stretch = circ / (count * tile.x);
	vec2 uv = vec2(aa.x * count + style.x * 7.0, aa.y / (tile.y * stretch) + style.y * 13.0);
	float texel = tile.x * stretch / 1024.0;
	float lod = clamp(log2(max(view_dist * 0.0012 / texel, 1.0)), 0.0, 9.0);
	return textureLod(bark_photo, vec3(uv, float(layer)), lod);
}

float photo_height(vec2 aa, float radius, vec2 style, int layer, out float crack, out float tone) {
	vec4 p = photo_sample(aa, radius, style, layer);
	crack = smoothstep(0.08, 0.4, p.a);
	tone = clamp(dot(p.rgb, vec3(0.33)) * 3.0, 0.0, 1.0);
	return p.a;
}

// Real rock (Poly Haven, CC0; assets/textures/rock/rock_atlas.png, tools/build_bark_atlas.gd): six slots, the colour in rgb and
// the height in alpha. ROCK_TILE is the metres a picture covers. A rock has no UV: the picture is projected along the three axes
// of the rock's own space and blended by the way the surface faces.
const float ROCK_TILE[6] = float[6](1.8, 2.0, 1.5, 1.5, 1.0, 2.0);

// Which slot a rock is, from the colour its mesh gives it (pale grey, brown, grey-tan, sandstone, red, dark) and a hash of its place.
int rock_slot(vec3 paint, float hash) {
	float lum = dot(paint, vec3(0.3, 0.6, 0.1));
	float warm = paint.r / (paint.b + 0.01);
	if (lum < 0.05) {
		return 5;
	}
	if (warm > 2.2) {
		return hash > 0.5 ? 3 : 4;
	}
	if (lum > 0.2) {
		return 0;
	}
	return warm > 1.5 ? 1 : 2;
}

vec4 rock_sample(vec3 p, vec3 n, int slot, vec2 style) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= max(w.x + w.y + w.z, 0.001);
	float tile = ROCK_TILE[slot];
	vec3 q = p / tile + vec3(style.x * 7.0, style.y * 5.0, style.x * 3.0);
	float layer = float(slot);
	return texture(rock_photo, vec3(q.yz, layer)) * w.x + texture(rock_photo, vec3(q.xz, layer)) * w.y
			+ texture(rock_photo, vec3(q.xy, layer)) * w.z;
}

// The plates, with the fine relief real bark has (measured on nine photographed barks: low contrast, features 1 to 4 cm,
// stretched along the trunk 2 to 3 times in most, far more in a stringy one, across in a palm). The plates' own edges are
// softened a little, so a plate is a swelling and not a tile.
float bark_height(vec2 aa, float radius, vec2 style, out float crack, out float tone) {
	int kind = int(bark_kind + 0.5);
	int photo = photo_layer(kind);
	if (photo >= 0) {
		return photo_height(aa, radius, style, photo, crack, tone);
	}
	float cells = bark_height_cells(aa, radius, style, crack, tone);
	float along = kind == 6 ? 8.0 : (kind == 4 || kind == 3 || kind == 2 ? 3.0 : (kind == 5 ? 0.3 : (kind == 1 ? 0.6 : 2.0)));
	float across_m = aa.x * 6.2832 * max(radius, 0.05); // (metres round the trunk)
	vec2 p = vec2(across_m, aa.y);
	float fine = 0.65 * smooth_noise(vec2(p.x * 50.0, p.y * 50.0 / along) + style * 17.0)
			+ 0.35 * smooth_noise(vec2(p.x * 0.8 + p.y * 0.6 / along, p.y * 0.8 / along - p.x * 0.6) * 130.0 + style * 31.0 + 7.0); // (turned, so no square grid shows)
	float height = clamp(mix(cells, 0.5, 0.22) + (fine - 0.5) * 0.4, 0.0, 1.0);
	if (kind == 0) {
		// oak: a few deep furrows running mostly along the trunk, wandering, with long smooth bark between them
		float lane_u = p.x * 6.0 + 1.3 * smooth_noise(vec2(p.x * 3.0, p.y * 0.9) + style * 23.0) + style.x * 7.0;
		float lane = floor(lane_u + 0.5);
		float line = 1.0 - smoothstep(0.0, 0.07, abs(lane_u - lane));
		float where = smoothstep(0.52, 0.7, smooth_noise(vec2(lane * 3.7, p.y * 0.55) + style * 9.0)); // (a lane has a furrow for a stretch, then none)
		float furrow = line * where;
		height = mix(height, 0.0, furrow * 0.85);
		crack = min(crack, 1.0 - furrow);
	}
	return height;
}

// The same height for the steps of the parallax march and the shadow march (about thirty lookups a pixel): the plates and
// one layer of the fine relief, without the second layer and the furrows (the hit point is then shaded with `bark_height`).
float bark_height_march(vec2 aa, float radius, vec2 style, out float crack, out float tone) {
	int kind = int(bark_kind + 0.5);
	int photo = photo_layer(kind);
	if (photo >= 0) {
		return photo_height(aa, radius, style, photo, crack, tone);
	}
	float cells = bark_height_cells(aa, radius, style, crack, tone);
	float along = kind == 6 ? 8.0 : (kind == 4 || kind == 3 || kind == 2 ? 3.0 : (kind == 5 ? 0.3 : (kind == 1 ? 0.6 : 2.0)));
	vec2 p = vec2(aa.x * 6.2832 * max(radius, 0.05), aa.y);
	float fine = 0.65 * smooth_noise(vec2(p.x * 50.0, p.y * 50.0 / along) + style * 17.0) + 0.175;
	return clamp(mix(cells, 0.5, 0.22) + (fine - 0.5) * 0.4, 0.0, 1.0);
}


// A cluster of small leaves on a card (UV 0..1, the stalk at the bottom): leaves in a 5 x 5 grid, each
// with its own size, turn (mostly pointing out from the stalk), shade, curve, wavy margin, veins and
// wear (holes, dry brown edges); the one drawn on top where two overlap is the one with the larger dice.
// Returns x: 1 inside a leaf (0 outside), y: the shade, z: how worn and dry it is there (0..1), w: how
// the surface leans across the leaf (-1 .. 1: round across the midrib, rippled along it); `across_uv` is
// the direction across the leaf in the card's UV.
vec4 leaf_cluster(vec2 uv, float id, out vec2 across_uv) {
	const float N = 5.0;
	vec2 p = uv * N;
	vec2 cell = floor(p);
	float best = -1.0;
	vec4 result = vec4(0.0, 1.0, 0.0, 0.0);
	across_uv = vec2(1.0, 0.0);
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 c = cell + vec2(float(i), float(j));
			vec2 h = hash22(c + id * 13.7);
			vec2 h2 = hash22(c * 1.7 + 5.3 + id * 7.1);
			vec2 h3 = hash22(c * 2.3 + 1.9 + id * 3.3);
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
			// the midrib is not straight: the leaf curves to one side and the tip droops sideways
			q.x -= (h3.x - 0.5) * 0.3 * width_cells * sin(3.14159 * t) + (h3.y - 0.5) * 0.35 * width_cells * t * t;
			if (t > 0.0 && t < 1.0) {
				// the margin is not a clean curve: slow waves, some leaves broader at the base, some at the tip
				float skew = mix(0.8, 1.15, h3.y) + (h3.x - 0.5) * 0.5 * t;
				float wavy = 1.0 + 0.1 * sin(t * (9.0 + 8.0 * h3.x) + h.y * 20.0) + 0.05 * sin(t * 31.0 + h2.x * 9.0);
				float half_width = width_cells * 0.5 * sin(3.14159 * pow(t, mix(0.6, 1.0, h3.y))) * wavy * skew;
				float across_raw = q.x / max(half_width, 0.001);
				float across = abs(across_raw);
				// wear: a few holes bitten out, brown dry tips and edges
				float hole = 0.0;
				if (h2.x > 0.8) {
					vec2 spot = vec2((h3.x - 0.5) * 0.5 * width_cells, (0.3 + 0.4 * h3.y) * length_cells - 0.5 * length_cells);
					hole = 1.0 - smoothstep(0.02, 0.03 + 0.05 * h2.y, length(q - spot));
				}
				float dry = smoothstep(0.55, 1.0, across * (0.7 + 0.5 * h3.x) + t * t * h2.x * 0.5) * step(0.82, h.y);
				if (across < 1.0 && h.y > best && hole < 0.5) {
					best = h.y;
					float rib = 1.0 - smoothstep(0.0, 0.07, abs(q.x) / width_cells);
					float run = fract(t * 5.0 - across * 1.6 + h.x);
					float side_vein = (1.0 - smoothstep(0.0, 0.16, min(run, 1.0 - run))) * (1.0 - across) * 0.7;
					// the fine net of small veins between the big ones
					float net = abs(sin(q.x * 70.0 + q.y * 55.0)) * abs(sin(q.x * 55.0 - q.y * 70.0));
					float fine = 1.0 - 0.09 * smoothstep(0.35, 0.0, net);
					float shade = (0.72 + 0.5 * h2.x) * (1.0 - 0.22 * across * across) * fine + max(rib, side_vein) * 0.28;
					// between the side veins the blade puffs up a little: a ripple along the leaf
					float ripple = sin(t * 14.0 + h.x * 6.0) * 0.5;
					float lean = clamp(across_raw * 0.85 + ripple * across, -1.0, 1.0);
					result = vec4(1.0, shade * mix(1.0, 0.82, dry), dry, lean);
					across_uv = vec2(cs, -sn); // (q.x runs along this in the card)
				}
			}
		}
	}
	return result;
}

// One blade of grass on a narrow card (UV.x across, UV.y from the root to the tip; UV2.y of 8 marks it): tapering to a point, its
// own bend to one side, darker at the root and with a lighter midrib. Returns x: 1 inside the blade (0 outside), y: the shade.
vec2 grass_blades(vec2 uv, float id) {
	float t = uv.y;
	float centre = 0.5 + (fract(id * 7.3) - 0.5) * 0.3 * t * t; // the blade curves a little to one side
	float half_width = 0.5 * pow(max(1.0 - t, 0.0), 0.75) * smoothstep(0.0, 0.04, 1.0 - t);
	float d = abs(uv.x - centre);
	float inside_blade = d < half_width ? 1.0 : 0.0;
	float rib = 1.0 - smoothstep(0.0, 0.18, d);
	float shade = mix(0.5, 1.15, t) * (0.82 + 0.36 * fract(id * 3.7)) * (0.9 + 0.2 * rib);
	return vec2(inside_blade, shade);
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

vec3 turn_by(vec3 rotation, vec3 v) {
	float angle = length(rotation);
	if (angle < 0.00001) {
		return v;
	}
	vec3 axis = rotation / angle;
	return v * cos(angle) + cross(axis, v) * sin(angle) + axis * dot(axis, v) * (1.0 - cos(angle));
}

void vertex() {
	if (bendable) {
		float branch = CUSTOM0.x;
		vec3 point = VERTEX;
		vec3 normal = NORMAL;
		for (int level = 0; level < 7; level++) { // the branch's own turn, then its parent's, up to the trunk
			int id = int(branch + 0.5);
			if (id <= 0) {
				break;
			}
			vec4 foot = texelFetch(bend_data, ivec2(id, 0), 0);
			vec3 turn = texelFetch(bend_data, ivec2(id, 1), 0).xyz;
			point = foot.xyz + turn_by(turn, point - foot.xyz);
			normal = turn_by(turn, normal);
			branch = foot.w;
		}
		VERTEX = point;
		NORMAL = normal;
		COLOR = vec4(COLOR.rgb * live_tint.rgb, COLOR.a * live_tint.a);
	}
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_pos = world;
	sway = COLOR.a;
	obj_pos = VERTEX;
	obj_up = NORMAL.y;
	obj_normal = NORMAL;
	obj_scale = length(MODEL_MATRIX[0].xyz);
	bark_kind = UV.x < -0.5 ? floor(UV2.y * 10.0 + 0.5) : 2.0;
	view_dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	if (bark_force >= 0.0) {
		bark_kind = bark_force;
	}
	bark_style = vec2(hash13(MODEL_MATRIX[3].xyz * 0.37), hash13(MODEL_MATRIX[3].zyx * 0.53 + 3.0));
	if (bark_style_force.x >= 0.0) {
		bark_style = bark_style_force;
	}
	float weight = COLOR.a * smoothstep(0.0, 0.35, VERTEX.y); // (the foot of a plant stays where it grows: the sway grows with the height above the ground)
	float gust = sin(TIME * sway_speed + dot(world.xz, vec2(0.11, 0.08))) * 0.5 + 0.5;
	float flutter = sin(TIME * sway_speed * 3.3 + dot(world.xz, vec2(0.9, 0.7)) + VERTEX.y * 2.0);
	float amount = weight * (0.03 + wind_strength * 0.5) * (gust * 0.8 + flutter * 0.2);
	vec3 push = vec3(wind_direction.x, 0.0, wind_direction.y) * amount;
	if (UV2.y > 7.5) { // a tuft of turf: the blades ripple, the tips most, in swells that roll across the field
		float tip = UV.y * UV.y;
		float swell = sin(TIME * 1.1 + dot(world.xz, vec2(0.35, 0.27)));
		float ripple = sin(TIME * 3.1 + dot(world.xz, vec2(1.7, 1.3)) + UV.x * 4.0);
		float strength = tip * (0.07 + wind_strength * 0.45);
		push = vec3(wind_direction.x, 0.0, wind_direction.y) * strength * (0.55 + 0.45 * swell + 0.18 * ripple)
				+ vec3(-wind_direction.y, 0.0, wind_direction.x) * strength * 0.3 * ripple;
	}
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
	vec2 card_across = vec2(1.0, 0.0);
	float card_lean = 0.0;
	if (is_card) {
		bool is_grass = UV2.y > 7.5;
		bool is_pin = UV2.y > 3.5 && !is_grass;
		float needles = (UV2.y > 5.5 && !is_grass) ? 1.0 : 0.0;
		float rows = (UV2.y - mix(4.0, 6.0, needles)) * 100.0;
		vec4 cluster = vec4(0.0, 1.0, 0.0, 0.0);
		if (is_grass) {
			cluster.xy = grass_blades(UV, UV2.x);
		} else if (is_pin) {
			cluster.xy = pinnate(UV, rows, UV2.x, needles);
		} else {
			cluster = leaf_cluster(UV, UV2.x, card_across);
		}
		// far away the leaves are under a pixel and would shimmer: the card fills in toward a solid mass
		float far_fill = smoothstep(0.35, 0.8, is_grass ? fwidth(UV.x) * 2.0 : (is_pin ? fwidth(UV.y) * rows : fwidth(UV.x) * 5.0));
		far_fill *= smoothstep(5.0, 18.0, length(VERTEX)); // (a card seen edge on near the eye is not a distant one)
		far_fill *= is_grass ? 0.0 : 1.0; // (a tuft is only drawn near: its blades stay blades, not a solid card)
		card_alpha = mix(cluster.x, 0.62, far_fill);
		paint *= mix(cluster.y, 0.9, far_fill);
		// dry brown tips and edges, and the lean of the leaf's surface for the normal
		paint = mix(paint, vec3(paint.g * 0.95, paint.g * 0.6, paint.g * 0.22), cluster.z * 0.7 * (1.0 - far_fill));
		card_lean = cluster.w * (1.0 - far_fill);
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
	vec3 pom_a = vec3(1.0, 0.0, 0.0); // the bark's directions and normal in view space (parallax occlusion)
	vec3 pom_l = vec3(0.0, 1.0, 0.0);
	vec3 pom_normal = vec3(0.0, 0.0, 1.0);
	bool has_pom = false;
	float cavity = 1.0; // how open to the sky the bark is here: 1 on a plate top, low deep in a crack
	vec2 bump = vec2(0.0);
	float bump_amount = 0.0;
	float surface_height = 0.0;
	float surface_bump = 0.0;
	bool is_bark = UV.x < -0.5;
	bool is_rock = UV.x < -0.1 && !is_bark; // add_rock marks its stones
	if (realism > 0.001 && is_bark && !planks) {
		float trunk = 1.0 - smoothstep(0.1, 0.3, sway);
		float radius = max(UV2.x, 0.01);
		vec2 aa = vec2(-UV.x - 1.0, UV.y); // (the way round 0..1, metres along)
		float plate_depth = clamp(radius * 0.22, 0.01, 0.045) * mix(0.75, 1.3, bark_style.y);
		float near = smoothstep(20.0, 8.0, length(VERTEX)); // the depth is only worth working out up close
		// the surface's own directions (per unit way round, per metre along) from the derivatives of the position and the UV
		vec3 dq1 = dFdx(VERTEX);
		vec3 dq2 = dFdy(VERTEX);
		vec2 dv1 = dFdx(UV);
		vec2 dv2 = dFdy(UV);
		float dt = dv1.x * dv2.y - dv1.y * dv2.x;
		if (abs(dt) > 1e-12) {
			vec3 around_p = -(dq1 * dv2.y - dq2 * dv1.y) / dt;
			vec3 along_p = (dq2 * dv1.x - dq1 * dv2.x) / dt;
			float len_a = max(length(around_p), 1e-4);
			float len_l = max(length(along_p), 1e-4);
			pom_a = around_p / len_a;
			pom_l = along_p / len_l;
			vec3 n0 = normalize(NORMAL);
			if (!FRONT_FACING) {
				n0 = -n0;
			}
			vec3 to_eye = normalize(-VERTEX);
			float vz = max(dot(to_eye, n0), 0.28);
			vec2 slide = vec2(-dot(to_eye, pom_a), -dot(to_eye, pom_l)) / vz * plate_depth;
			// (fewer steps when the eye looks straight at the bark, more when it grazes: the ray crosses
			// the depth over a longer way, and a coarse march would skip the thin cracks)
			float steps = mix(9.0, 24.0, smoothstep(0.9, 0.3, vz));
			steps = (near < 0.02 || bark_pom < 0.5) ? 1.0 : steps; // (beyond the fade range the march moves nothing: do one step, not twenty)
			float step_size = 1.0 / steps;
			vec2 per_layer = vec2(slide.x / len_a, slide.y / len_l) * step_size * near;
			// parallax occlusion: step down through the bark until the ray meets a plate
			vec2 here = aa;
			float crack_here;
			float tone_here;
			float h_here = bark_height_march(here, radius, bark_style, crack_here, tone_here);
			float layer = 0.0;
			vec2 last = here;
			for (int i = 0; i < 24; i++) {
				if (layer >= 1.0 - h_here || float(i) >= steps) {
					break;
				}
				last = here;
				here += per_layer;
				layer += step_size;
				h_here = bark_height_march(here, radius, bark_style, crack_here, tone_here);
			}
			// the ray crossed the surface between `last` and `here`: halve that gap twice, so the
			// edge of a plate is sharp and not a staircase of steps
			float lo = max(layer - step_size, 0.0);
			float hi = layer;
			for (int j = 0; j < 2; j++) {
				float mid = 0.5 * (lo + hi);
				vec2 at = last + per_layer * ((mid - lo) / step_size);
				float h_mid = bark_height_march(at, radius, bark_style, crack_here, tone_here);
				if (mid >= 1.0 - h_mid) {
					hi = mid;
					here = at;
				} else {
					lo = mid;
					last = at;
				}
			}
			aa = here;
			float crack;
			float tone;
			float h0 = bark_height(aa, radius, bark_style, crack, tone);
			cavity = mix(1.0, mix(0.3, 1.0, smoothstep(0.05, 0.7, h0)), smoothstep(40.0, 12.0, length(VERTEX)));
			// the plates shade each other: from the point the eye hit, walk a few steps toward the sun
			// across the bark's own height; where the surface stands higher than the ray, a plate is in the way
			float sun_len_b = length(cloud_sun_world);
			if (near > 0.05 && sun_len_b > 0.5 && bark_pom > 0.5) {
				vec3 sun_b = (VIEW_MATRIX * vec4(cloud_sun_world / sun_len_b, 0.0)).xyz;
				float up_b = dot(sun_b, n0);
				if (up_b > 0.05) {
					vec2 toward = vec2(dot(sun_b, pom_a), dot(sun_b, pom_l)) / max(up_b, 0.25) * plate_depth;
					vec2 per_unit = vec2(toward.x / len_a, toward.y / len_l);
					float lit = 1.0;
					for (int s = 0; s < 4; s++) {
						float t = 0.12 + 0.27 * float(s);
						float c2, t2;
						float h_s = bark_height_march(aa + per_unit * t, radius, bark_style, c2, t2);
						lit = min(lit, 1.0 - smoothstep(0.0, 0.12, h_s - (h0 + t)));
					}
					cavity *= mix(0.55, 1.0, mix(1.0, lit, near));
				}
			}
			float ea = 0.004 / len_a;
			float c1, t1;
			float ha = bark_height(aa + vec2(ea, 0.0), radius, bark_style, c1, t1);
			float hl = bark_height(aa + vec2(0.0, 0.004 / len_l), radius, bark_style, c1, t1);
			vec2 slope = vec2(ha - h0, hl - h0) / 0.004 * plate_depth;
			pom_normal = normalize(vec3(-slope.x, -slope.y, 1.0));
			pom_normal = normalize(mix(vec3(0.0, 0.0, 1.0), pom_normal, 0.85 * near + 0.15));
			has_pom = true;
			// the colour: plates lighter, cracks and the low ground between them dark, each plate its own tone
			float shade = mix(0.4, 1.5, smoothstep(0.1, 0.9, h0)) * mix(0.35, 1.0, crack) * (0.78 + 0.4 * tone);
			shade *= 0.85 + 0.3 * noise3(vec3(aa.x * 40.0, aa.y * 9.0, tone * 7.0));
			paint = mix(paint, vec3(0.34, 0.3, 0.26) * (0.55 + 0.9 * tone), smoothstep(0.4, 0.85, h0) * 0.55 * trunk * realism); // (the weathered tops of the plates)
			paint *= mix(1.0, shade * 1.4, realism); // (lighter: the vertex brown alone made every trunk near black)
			// (as in photographed bark: the crevices are warmer and redder, and the trunk is mottled in patches a
			// hand to a forearm across, on top of the plates' own tones)
			paint *= mix(vec3(1.0), vec3(1.28, 0.94, 0.78), (1.0 - crack) * 0.55 * realism * trunk);
			float mottle = noise3(vec3(aa.x * radius * 6.0, aa.y * 2.2, bark_style.y * 13.0 + 3.0));
			paint *= mix(1.0, 0.8 + 0.4 * mottle, realism * trunk);
			if (bark_debug > 0.5) {
				paint = bark_debug > 1.5 ? vec3(tone, crack, h0) : vec3(h0);
			}
			// lichen and moss on the plates (grey-green crusts, on some trees orange ones), moss low on the damp foot
			float lichen_noise = noise3(vec3(aa.x * 9.0, aa.y * 2.2, bark_style.x * 20.0) + 11.0);
			float crust = smoothstep(0.58, 0.7, lichen_noise) * smoothstep(0.35, 0.7, h0) * trunk;
			paint = mix(paint, vec3(0.2, 0.24, 0.17) * (0.8 + 0.5 * tone), crust * 0.7 * realism);
			float orange = smoothstep(0.62, 0.74, noise3(vec3(aa.x * 14.0, aa.y * 3.5, 4.0 + bark_style.y * 9.0))) * smoothstep(0.55, 0.8, bark_style.x);
			paint = mix(paint, vec3(0.5, 0.17, 0.03) * (0.7 + 0.5 * tone), orange * smoothstep(0.3, 0.8, h0) * 0.8 * realism * trunk);
			float damp = noise3(vec3(world_pos.xz * 0.6, world_pos.y * 0.3));
			float moss = smoothstep(0.5, 0.72, damp + (1.6 - obj_pos.y) * 0.18) * smoothstep(2.4, 0.2, obj_pos.y) * trunk;
			paint = mix(paint, vec3(0.1, 0.2, 0.05) * (0.7 + 0.6 * shade), moss * realism * (0.4 + 0.5 * crack));
		}
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
			if (rock_photo_on > 0.5) {
				// the photographed rock: its own colour, tinted a little by the mesh's, and its height as the bump
				int slot = rock_slot(paint, bark_style.x);
				vec4 photo = rock_sample(obj_pos * obj_scale, normalize(obj_normal), slot, bark_style);
				paint = photo.rgb * (0.85 + 0.3 * bark_style.y);
				surface_height = (photo.a - 0.5) * 0.5;
				surface_bump = realism * 2.0;
			} else {
			paint *= mix(1.0, shade * 1.4, realism); // (lighter: the vertex brown alone made every trunk near black)
			paint = mix(paint, paint * vec3(0.7, 1.0, 0.55), realism * smoothstep(0.62, 0.8, patch) * 0.45 * smoothstep(0.2, 0.9, obj_up));
			surface_height = broad * 0.4 + bands * 0.15 + grain * 0.15 + speck * 0.1 - crack * 0.5;
			surface_bump = realism * 1.3;
			}
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
	if (has_pom) {
		NORMAL = normalize(pom_a * pom_normal.x + pom_l * pom_normal.y + NORMAL * pom_normal.z);
	}
	if (is_card && UV2.y < 3.5 && abs(card_lean) > 0.001) {
		// a leaf of a cluster is round across its midrib and rippled along it: tip the normal across the leaf (the card's
		// UV directions from the derivatives of the position and the UV)
		vec3 dq1 = dFdx(VERTEX);
		vec3 dq2 = dFdy(VERTEX);
		vec2 dv1 = dFdx(UV);
		vec2 dv2 = dFdy(UV);
		float dt = dv1.x * dv2.y - dv1.y * dv2.x;
		float sgn = dt < 0.0 ? -1.0 : 1.0;
		vec3 along_u = normalize(dq1 * dv2.y - dq2 * dv1.y) * sgn;
		vec3 along_v = normalize(dq2 * dv1.x - dq1 * dv2.x) * sgn;
		vec3 across_dir3 = normalize(along_u * card_across.x + along_v * card_across.y);
		NORMAL = normalize(NORMAL + across_dir3 * card_lean * 0.6);
	}
	if (is_card && UV2.y > 7.5) {
		// a blade of grass is a flat card but is round across: tilt the normal one way on one side of the midrib and the other way on the
		// other (the direction of the card's across from the derivatives of its UV), and lean it toward the sky as the ground's light does
		vec3 dp1 = dFdx(VERTEX);
		vec3 dp2 = dFdy(VERTEX);
		vec2 du1 = dFdx(UV);
		vec2 du2 = dFdy(UV);
		float det = du1.x * du2.y - du1.y * du2.x;
		vec3 across_dir = normalize(dp1 * du2.y - dp2 * du1.y) * (det < 0.0 ? -1.0 : 1.0);
		float round_across = (UV.x - 0.5) * 2.0;
		vec3 sky = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
		NORMAL = normalize(NORMAL + across_dir * round_across * 0.75 + sky * 0.45);
	}
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
	// the cracks of the bark: less ambient light and less shine (the sky does not reach into them), and a
	// little less of the sun too, as if the plates shaded each other
	AO = mix(1.0, cavity, realism);
	AO_LIGHT_AFFECT = is_bark ? 0.5 * realism : 0.0;
	float leafy_part = is_bark ? 0.0 : 1.0;
	// light through the leaves: a steady glow, and more of it when the eye looks along the sun's ray
	// through the leaf (the sun behind the canopy): a lobe on how opposed the view and the sun are
	float sun_len = length(cloud_sun_world);
	vec3 sun_view = (VIEW_MATRIX * vec4(cloud_sun_world / max(sun_len, 0.001), 0.0)).xyz;
	float against_sun = sun_len > 0.5 ? clamp(dot(sun_view, -VIEW), 0.0, 1.0) : 0.0;
	float glow = 0.3 + 2.5 * pow(against_sun, 4.0);
	BACKLIGHT = paint * glow * realism * smoothstep(0.1, 0.5, sway) * leafy_part;
	RIM = 0.25 * realism * smoothstep(0.1, 0.5, sway) * leafy_part;
	RIM_TINT = 0.5;
}
