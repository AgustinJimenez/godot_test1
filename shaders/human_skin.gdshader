shader_type spatial;
render_mode sss_mode_skin;
// Skin for the base humans with a darker scalp: under the hair the skin is the colour of the hair roots, so a gap between hairs shows a
// dark scalp, not pale skin. The scalp amount per vertex comes from HumanHair (mesh meta "hair_scalp_weight"), uploaded as a small texture:
// the vertex shader reads it by VERTEX_ID.
// Procedural detail on any skin (flat colour or a MakeHuman texture), placed on the face from three landmarks the lab finds in the mesh
// (face_nose, face_top, face_chin): redness of the nose, cheeks and ears, shadows round the eyes, a shave shadow, an oily second shine on
// the T-zone and cheekbones (clearcoat), pores deeper on the nose and cheeks, fine criss-cross lines, wrinkles that come with age,
// freckles, and light through the ears (skin scattering). The zones are worked out in the mesh's own space so they stay on the face.

uniform vec3 skin_color : source_color = vec3(0.6, 0.4, 0.32);
uniform vec3 scalp_color : source_color = vec3(0.15, 0.09, 0.06);   // the colour of the hair roots
uniform float scalp_amount : hint_range(0.0, 1.0) = 1.0;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.55;
uniform float sss_strength : hint_range(0.0, 1.0) = 0.35;
uniform sampler2D scalp_tex : filter_nearest;
uniform int scalp_width = 1024;
uniform bool has_scalp = false;
uniform sampler2D skin_tex : source_color, filter_linear_mipmap, repeat_disable;   // an optional skin diffuse map (MakeHuman UV layout)
uniform bool has_skin_tex = false;
uniform sampler2D skin_spec : hint_default_white, filter_linear_mipmap, repeat_disable;   // an optional specular map (MakeHuman): bright = shinier skin (oily forehead, lips), dark = matte
uniform bool has_skin_spec = false;
uniform sampler2D skin_normal : hint_normal, filter_linear_mipmap, repeat_disable;       // an optional tangent normal map (pores, wrinkles)
uniform bool has_skin_normal = false;
uniform float normal_strength : hint_range(0.0, 2.0) = 1.0;
// Pores in UV space (the MakeHuman layout), so they do not slide when the body is posed; they fade out with the distance (a pixel covering
// many pores would alias). The low-poly body shows its triangles as faint diagonal bands in a plain colour: the pores and tone break them up.
uniform float pore_strength : hint_range(0.0, 1.0) = 0.5;      // the depth of the pores (deeper on the nose and cheeks, finer on the forehead)
uniform float pore_scale = 2600.0;                              // pores per UV unit (the head is about a quarter of the UV square: ~1 mm pores)
uniform float tone_variation : hint_range(0.0, 0.3) = 0.09;     // slow blotchy variation of the skin colour (redness, shade)

// the face's zones
uniform bool has_face = false;
uniform vec3 face_nose = vec3(0.0, 1.6, 0.17);   // the nose tip (mesh space)
uniform float face_top = 1.75;                    // the top of the head
uniform float face_chin = 1.52;                   // the bottom of the chin
uniform vec3 face_eye = vec3(0.029, 1.639, 0.13);   // the centre of the +x eyeball (from the eye mesh, with the face's blend shapes)
uniform bool has_eye = false;
uniform float redness : hint_range(0.0, 1.0) = 0.5;        // nose, cheeks, ears, a little on the chin
uniform float eye_shadow : hint_range(0.0, 1.0) = 0.65;     // darker, a little violet under the eyes and on the lids
uniform float shave_shadow : hint_range(0.0, 1.0) = 0.0;   // the grey-blue of shaved stubble under the skin (jaw, upper lip, chin, neck)
uniform float oil : hint_range(0.0, 1.0) = 0.5;            // the sharp second shine of the T-zone, nose and cheekbones
uniform float age : hint_range(0.0, 1.0) = 0.25;           // wrinkles: crow's feet, forehead lines, the nose-to-mouth fold, under the eyes
uniform float freckles : hint_range(0.0, 1.0) = 0.0;       // freckles (nose and cheeks most) and a few moles
uniform float spots : hint_range(0.0, 1.0) = 0.35;         // small brown spots and tiny moles anywhere (most skin has some)
uniform float fuzz : hint_range(0.0, 1.0) = 0.35;          // peach fuzz: the fine hair's soft sheen where the skin turns away (Godot's rim light)
// makeup (the face zones above): lipstick on the lips, blush on the cheeks, eyeshadow on the upper lids, a dark line along the upper lash line
uniform vec3 lipstick_color : source_color = vec3(0.6, 0.08, 0.12);
uniform float lipstick : hint_range(0.0, 1.0) = 0.0;
uniform vec3 blush_color : source_color = vec3(0.85, 0.35, 0.35);
uniform float blush : hint_range(0.0, 1.0) = 0.0;
uniform vec3 eyeshadow_color : source_color = vec3(0.35, 0.25, 0.35);
uniform float eyeshadow : hint_range(0.0, 1.0) = 0.0;
uniform float eyeliner : hint_range(0.0, 1.0) = 0.0;
// the body's joints (mesh space, from the rig file, moved with the height/weight/muscle shapes): kneecaps redder, elbow points darker and rougher, knuckles redder
uniform bool has_joints = false;
uniform vec3 knee_l = vec3(0.15, 0.5, 0.03);
uniform vec3 knee_r = vec3(-0.15, 0.5, 0.03);
uniform vec3 elbow_l = vec3(0.45, 1.1, -0.05);
uniform vec3 elbow_r = vec3(-0.45, 1.1, -0.05);
uniform vec3 knuckles[8];   // the bases of the index, middle, ring and little fingers, left hand then right
uniform float joint_tone : hint_range(0.0, 1.0) = 0.5;
// fingernails: the centre of each nail (just behind the fingertip, on its back) and the back-of-hand direction of each hand (left, right)
uniform vec3 nails[10];
uniform vec3 nail_backs[10];   // the direction the back of each fingertip faces (the nail side)
// veins on the backs of the hands and the forearms: each side's wrist and middle knuckle (the elbow is above), blue-green lines under thin skin
uniform vec3 wrists[2];
uniform vec3 hand_mids[2];
uniform float veins : hint_range(0.0, 1.0) = 0.3;
// nipples (the most forward point of each side of the chest, found by the lab): a pinkish-brown areola with a darker centre
uniform vec3 nipples[2];
uniform vec3 armpits[2];      // the hollow under each shoulder joint (the lab: the shoulder from the rig, moved down and in): a little darker skin
uniform bool has_armpits = false;
uniform bool has_nipples = false;
uniform vec3 nail_polish_color : source_color = vec3(0.55, 0.05, 0.1);
uniform float nail_polish : hint_range(0.0, 1.0) = 0.0;
uniform int skin_debug = 0;                                // 2: the normals; 1: the zones as colours (red = redness, blue = shave, green = oil, violet = eyes, white = wrinkles)

varying float scalp;
varying vec3 local_pos;
varying vec3 local_normal;
uniform bool has_lips = false;
uniform vec3 lip_info = vec3(0.0, 0.0, 1.0);   // lip centre height, z in front of which the lips are, face scale (from HumanHair, mesh meta "hair_mouth")
uniform vec3 lip_color : source_color = vec3(0.62, 0.27, 0.25);
uniform float mouth_y = 0.0;      // the mouth line measured on the mesh (the lab: midway between the upper and the lower lip's most forward points); lip_y is the hair builder's estimate
uniform bool has_mouth = false;

float hash21(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

vec2 hash22(vec2 p) {
	return vec2(hash21(p), hash21(p + 19.19));
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x), mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}

// distance to the nearest of a jittered grid of points (pores, follicles, freckles), and that point's random value
vec2 cells(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float best = 9.0;
	float id = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 o = vec2(float(x), float(y));
			vec2 c = o + 0.15 + 0.7 * hash22(i + o);
			float d = length(c - f);
			if (d < best) {
				best = d;
				id = hash21(i + o + 7.7);
			}
		}
	}
	return vec2(best, id);
}

// the skin's relief at a UV point: pits (pores) in a soft value noise, with fine criss-cross lines (the skin's own grid of creases)
float pore_height(vec2 p, float pit_depth) {
	vec2 c = cells(p * 0.55);
	float pit = smoothstep(0.32, 0.0, c.x) * (0.5 + 0.5 * c.y);
	float soft = value_noise(p) * 0.6 + value_noise(p * 2.3 + 17.0) * 0.4;
	vec2 r1 = vec2(0.94, 0.34);
	vec2 r2 = vec2(-0.42, 0.91);
	float lines = (1.0 - abs(sin(dot(p, r1) * 0.9 + 3.0 * value_noise(p * 0.3)))) * (1.0 - abs(sin(dot(p, r2) * 0.75 + 3.0 * value_noise(p * 0.27 + 4.0))));
	return soft * 0.55 - pit * pit_depth - pow(lines, 6.0) * 0.25 + 0.3;
}

// soft ellipsoid: 1 inside, 0 outside (q and centre in the face frame, radii in metres at the reference head)
float blob(vec3 q, vec3 centre, vec3 radii) {
	return 1.0 - smoothstep(0.25, 1.0, length((q - centre) / radii));   // (a wide soft edge: a narrow one showed the zone's outline on pale skin)
}

// a groove along the segment a-b (x, y in the face frame): 0..1 at the line, width w
float groove(vec2 p, vec2 a, vec2 b, float w) {
	vec2 ab = b - a;
	float t = clamp(dot(p - a, ab) / dot(ab, ab), 0.0, 1.0);
	float d = length(p - a - ab * t);
	float ends = smoothstep(0.0, 0.2, t) * smoothstep(1.0, 0.75, t);
	return exp(-d * d / (w * w)) * ends;
}

void vertex() {
	local_pos = VERTEX;
	local_normal = NORMAL;
	scalp = 0.0;
	if (has_scalp) {
		scalp = texelFetch(scalp_tex, ivec2(VERTEX_ID % scalp_width, VERTEX_ID / scalp_width), 0).r;
	}
}

void fragment() {
	float lip_y = has_mouth ? mouth_y : lip_info.x;   // (the estimate from the eye height was 9 mm low on the female face)
	vec3 base = skin_color;
	if (has_skin_tex) {
		base = texture(skin_tex, UV).rgb;
	}
	// ---- the face frame: q is the point relative to the nose tip, in metres at the reference (male) head, x mirrored ----
	float red_zone = 0.0;
	float eye_zone = 0.0;
	float shave_zone = 0.0;
	float oil_zone = 0.0;
	float pore_zone = 1.0;
	float ear_zone = 0.0;
	float freckle_zone = 0.0;
	float nostril_zone = 0.0;   // the crease and opening under the nose (less scattering: it bled an orange outline round the dark opening)
	float blush_zone = 0.0;      // the apples of the cheeks
	float shadow_zone = 0.0;     // the upper lid up to the crease
	float liner_zone = 0.0;      // the upper lash line
	float wrinkle_h = 0.0;   // height of the wrinkles (negative = a groove), metres
	if (has_face) {
		float s = max((face_top - face_chin) / 0.2247, 0.5);
		vec3 q = (local_pos - face_nose) / s;
		q.x = abs(q.x);
		float front = smoothstep(-0.13, -0.09, q.z);   // the face, not the back of the head
		float nose = blob(q, vec3(0.0, -0.004, -0.010), vec3(0.020, 0.020, 0.030));
		float nose_bridge = blob(q, vec3(0.0, 0.030, -0.025), vec3(0.010, 0.030, 0.030));
		float cheek = blob(q, vec3(0.046, -0.004, -0.045), vec3(0.024, 0.024, 0.035));
		float cheekbone = blob(q, vec3(0.048, 0.014, -0.052), vec3(0.016, 0.010, 0.030));
		float chin = blob(q, vec3(0.0, -0.068, -0.020), vec3(0.020, 0.014, 0.030));
		float forehead = smoothstep(0.050, 0.070, q.y) * (1.0 - smoothstep(0.115, 0.135, q.y)) * (1.0 - smoothstep(0.030, 0.050, q.x)) * front;
		ear_zone = smoothstep(0.066, 0.074, q.x) * (1.0 - smoothstep(0.025, 0.045, abs(q.y - 0.002))) * (1.0 - smoothstep(0.07, 0.09, abs(q.z + 0.165)));
		red_zone = max(max(nose, cheek * 0.8), max(ear_zone * 0.9, chin * 0.35));
		nostril_zone = blob(q, vec3(0.010, -0.020, -0.018), vec3(0.016, 0.012, 0.022));
		// round the eyes: under the eye (the tear trough) and the lid, darker toward the inner corner
		// the real eyeball centre (face frame), and the point the eye zones below were tuned from on the male body (5 mm below and 3 mm out from it):
		// the zones now sit at the same place on every face, the female's 1 cm lower than with a fixed point
		vec3 eye_real = has_eye ? (vec3(abs(face_eye.x - face_nose.x), face_eye.y, face_eye.z) - vec3(0.0, face_nose.y, face_nose.z)) / s : vec3(0.0293, 0.0411, -0.0456);
		vec3 eye = eye_real + vec3(0.0027, -0.0051, 0.0006);
		float under = blob(q, eye + vec3(0.0, -0.009, 0.006), vec3(0.018, 0.0075, 0.020)) * (1.0 - 0.4 * smoothstep(0.02, 0.045, q.x));
		float lid = blob(q, eye + vec3(0.0, 0.009, 0.004), vec3(0.016, 0.007, 0.020));
		// (the upper lid, from the lash line, about 8 mm above the eyeball's centre with the eye open, up toward the crease and the brow bone)
		shadow_zone = blob(q, eye_real + vec3(0.002, 0.0125, 0.006), vec3(0.018, 0.0075, 0.022)) * front;
		// (the lash line: a thin band at the top of the eye opening, a little wider and higher toward the outer corner)
		float outer = smoothstep(eye_real.x, eye_real.x + 0.014, q.x);
		float liner_y = abs(q.y - (eye_real.y + 0.0058 + 0.0012 * (1.0 - smoothstep(0.0, 0.013, abs(q.x - eye_real.x))) + 0.0012 * outer));   // (the lid edge arches: highest over the pupil)
		liner_zone = (1.0 - smoothstep(0.0009, 0.0021 + 0.001 * outer, liner_y)) * (1.0 - smoothstep(0.013, 0.018, abs(q.x - eye_real.x - 0.001))) * front;
		blush_zone = blob(q, vec3(0.046, 0.002, -0.042), vec3(0.022, 0.018, 0.035)) * front;
		eye_zone = max(under, lid * 0.7) * front;
		float eyelid_skin = blob(q, eye + vec3(0.0, 0.008, 0.004), vec3(0.03, 0.026, 0.03)) * front;   // (the thin skin from the brow to under the eye: almost no pores)
		// the beard area: under a line from the nose to the sideburn, down to the throat, not on the lips or ears
		float line_y = mix(-0.012, -0.032, smoothstep(0.012, 0.042, q.x)) + 0.045 * smoothstep(0.050, 0.072, q.x);
		float below = 1.0 - smoothstep(line_y - 0.008, line_y + 0.004, q.y);
		float throat = smoothstep(-0.130, -0.100, q.y);
		float jaw_side = 1.0 - smoothstep(0.066, 0.076, q.x);
		float in_front = smoothstep(-0.175, -0.150, q.z);
		shave_zone = below * throat * jaw_side * in_front;
		oil_zone = max(max(forehead * 0.9, nose), max(nose_bridge * 0.8, max(cheekbone * 0.6, chin * 0.5)));
		pore_zone = mix(0.75, 1.0, max(nose, cheek)) * mix(1.0, 0.85, forehead) * (1.0 - 0.85 * eyelid_skin);   // (pores on the shaded eyelid caught the light as white specks)
		freckle_zone = (0.12 + 0.88 * max(max(nose, nose_bridge), max(cheek, cheekbone))) * front;
		// wrinkles (with age): crow's feet fanning from the outer eye corner, forehead lines, the nose-to-mouth fold, a line under the eye
		vec2 p = q.xy;
		vec2 corner = eye.xy + vec2(0.011, -0.001);   // (the outer corner of the eye)
		float crows = 0.0;
		for (int i = 0; i < 4; i++) {
			float a = -0.6 + 0.4 * float(i) + 0.15 * sin(float(i) * 2.3);
			float len = 0.008 + 0.003 * fract(float(i) * 0.618);
			crows += groove(p, corner + vec2(0.003, 0.0), corner + vec2(0.003 + len * cos(a), len * sin(a)), 0.0009);
		}
		float lines = 0.0;
		for (int i = 0; i < 3; i++) {
			float y = 0.066 + 0.010 * float(i) + 0.002 * sin(q.x * 90.0 + float(i));
			lines += exp(-pow((q.y - y) / 0.0016, 2.0)) * (1.0 - smoothstep(0.025, 0.050, q.x)) * front;
		}
		float fold = groove(p, vec2(0.017, -0.006), vec2(0.030, -0.042), 0.0028);
		float trough = groove(p, eye.xy + vec2(-0.010, -0.012), eye.xy + vec2(0.014, -0.016), 0.0022) * front;
		float aged = age * age;   // (few lines when young, they deepen late)
		wrinkle_h = -(crows * 0.00030 + lines * 0.00025 + fold * 0.0006 + trough * 0.00035) * aged * front;
		wrinkle_h -= fold * 0.00015 * front;   // (everyone has the fold a little; on the face only: q.x is mirrored and the groove tests x and y, so it also landed on the nape)
		// the lips are not beard, not oily skin and not red skin
		if (has_lips && local_pos.z > lip_info.y) {
			vec2 lq = vec2(abs(local_pos.x) / (0.034 * lip_info.z), (local_pos.y - lip_y) / ((local_pos.y > lip_y ? 0.0135 : 0.0105) * lip_info.z));
			float on_lip = 1.0 - smoothstep(0.6, 0.85, length(lq));
			shave_zone *= 1.0 - on_lip;
			red_zone *= 1.0 - on_lip;
			pore_zone *= 1.0 - 0.8 * on_lip;   // (lips have fine lines, not pores)
			// the lips' fine vertical creases: about 1.3 mm apart, a little wavy, fading toward the lip's edge and its corners
			float t = local_pos.x * 760.0 + 0.6 * value_noise(vec2(local_pos.x * 300.0, local_pos.y * 900.0));
			float crease = pow(1.0 - abs(fract(t) - 0.5) * 2.0, 6.0);
			float lip_core = (1.0 - smoothstep(0.3, 0.8, length(lq))) * (1.0 - smoothstep(0.6, 0.95, abs(lq.x)));
			wrinkle_h -= crease * lip_core * 0.00006;
		}
	}
	// ---- the body's joints ----
	float knee_zone = 0.0;
	float elbow_zone = 0.0;
	float knuckle_zone = 0.0;
	float nail_zone = 0.0;
	float vein_line = 0.0;
	float palm_zone = 0.0;   // palms and soles: little pigment (much lighter on dark skin, a little pinker on light skin)
	if (has_joints && joint_tone > 0.0) {
		vec3 n = normalize(local_normal);
		for (int side = 0; side < 2; side++) {
			vec3 knee = side == 0 ? knee_l : knee_r;
			vec3 elbow = side == 0 ? elbow_l : elbow_r;
			// (the kneecap: in front of the knee joint and a little below it; the front of the leg only)
			float kd = length((local_pos - knee - vec3(0.0, -0.01, 0.0)) / vec3(0.055, 0.06, 0.08));
			knee_zone = max(knee_zone, (1.0 - smoothstep(0.35, 1.0, kd)) * smoothstep(0.1, 0.6, n.z));
			// (the point of the elbow: behind the joint)
			float ed = length((local_pos - elbow) / vec3(0.05, 0.05, 0.06));
			elbow_zone = max(elbow_zone, (1.0 - smoothstep(0.3, 1.0, ed)) * smoothstep(0.0, 0.6, -n.z));
		}
		for (int i = 0; i < 8; i++) {
			knuckle_zone = max(knuckle_zone, 1.0 - smoothstep(0.011, 0.024, length(local_pos - knuckles[i])));   // (the joint centre is about a centimetre under the skin)
		}
		for (int i = 0; i < 10; i++) {
			float facing = smoothstep(0.25, 0.65, dot(n, nail_backs[i]));
			nail_zone = max(nail_zone, (1.0 - smoothstep(0.0055, 0.0085, length(local_pos - nails[i]))) * facing);
		}
		// veins: a branching line pattern stretched along the hand (wrist to middle knuckle) and the forearm (elbow to wrist), on thin skin only
		if (veins > 0.0) {
			for (int side = 0; side < 2; side++) {
				vec3 elbow = side == 0 ? elbow_l : elbow_r;
				vec3 a[2] = vec3[2](wrists[side], elbow);
				vec3 b[2] = vec3[2](hand_mids[side], wrists[side]);
				for (int part = 0; part < 2; part++) {
					vec3 axis = b[part] - a[part];
					float len = length(axis);
					if (len < 0.01) {
						continue;
					}
					axis /= len;
					vec3 d = local_pos - a[part];
					float along = dot(d, axis);
					vec3 radial = d - axis * along;
					float reach = part == 0 ? 0.05 : 0.075;   // (beyond the skin of the hand and the forearm: the surface is 3-4 cm from the bone line)
					float inside = smoothstep(-0.01, 0.01, along) * (1.0 - smoothstep(len - 0.01, len + 0.005, along)) * (1.0 - smoothstep(reach * 0.85, reach, length(radial)));
					if (inside <= 0.0) {
						continue;
					}
					// (round the limb: the angle; along it: stretched, so the noise makes long, gently wandering lines)
					vec3 ref = abs(axis.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
					vec3 u = normalize(cross(axis, ref));
					float angle = atan(dot(radial, cross(axis, u)), dot(radial, u));
					vec2 vp = vec2(angle * 2.2 + 0.6 * value_noise(vec2(along * 40.0, float(side * 3 + part))), along * 9.0);
					float n = value_noise(vp * vec2(1.0, 1.0) + float(side) * 7.0 + float(part) * 3.0);
					float ridge = 1.0 - abs(n * 2.0 - 1.0);
					vein_line = max(vein_line, smoothstep(0.62, 0.9, ridge) * inside * (part == 0 ? 1.0 : 0.7));
				}
			}
			vein_line *= veins;
		}
		// palms: the side of the hand away from its back (wrist to past the middle knuckle, the fingers' pads too)
		for (int side = 0; side < 2; side++) {
			vec3 a = wrists[side];
			vec3 axis = hand_mids[side] - a;
			float len = length(axis);
			if (len < 0.01) {
				continue;
			}
			axis /= len;
			vec3 d = local_pos - a;
			float along = dot(d, axis);
			float near_hand = smoothstep(-0.01, 0.01, along) * (1.0 - smoothstep(len * 1.9, len * 2.1, along)) * (1.0 - smoothstep(0.045, 0.06, length(d - axis * along)));
			vec3 back = nail_backs[side == 0 ? 1 : 6];   // (the index finger's back: the back of that hand)
			palm_zone = max(palm_zone, near_hand * smoothstep(0.1, 0.5, -dot(n, back)));
		}
		knee_zone *= joint_tone;
		elbow_zone *= joint_tone;
		knuckle_zone *= joint_tone;
	}
	// ---- colour ----
	// mottling at three sizes (patches of a couple of centimetres, of a few millimetres, and a fine grain), each faded out once it is smaller than a pixel;
	// two kinds: blood (redder, a little darker) and pigment (browner, yellower), which do not line up (real skin is never one even colour)
	vec2 tone_p = UV * 140.0;
	float tone_fade = 1.0 - smoothstep(0.5, 2.0, length(fwidth(tone_p)));
	float tone = (value_noise(tone_p) * 0.6 + value_noise(tone_p * 2.7 + 5.0) * 0.4) - 0.5;
	float big = value_noise(UV * 38.0 + 3.0) - 0.5;
	float blood = (value_noise(UV * 52.0 + 11.0) * 0.6 + value_noise(UV * 150.0 + 7.0) * 0.4 * tone_fade) - 0.5;
	float pigment = (value_noise(UV * 44.0 + 23.0) * 0.55 + value_noise(UV * 170.0 + 31.0) * 0.45 * tone_fade) - 0.5;
	vec2 grain_p = UV * pore_scale * 0.22;
	float grain = (value_noise(grain_p) - 0.5) * (1.0 - smoothstep(0.5, 1.6, length(fwidth(grain_p))));
	base *= 1.0 + tone_variation * (tone * 2.0 * tone_fade + big * 2.2 + grain * 2.4);
	base.r *= 1.0 + tone_variation * 0.8 * tone * tone_fade;   // (a little more red where it is darker: blood under the skin)
	base = mix(base, base * vec3(1.05, 0.9, 0.88), clamp(blood * tone_variation * 14.0, 0.0, 1.0));
	base = mix(base, base * vec3(0.93, 0.9, 0.8), clamp(pigment * tone_variation * 12.0, 0.0, 1.0));
	// the joints: kneecaps and knuckles redder, elbow points darker (thicker, drier skin)
	float joint_blotch = 0.75 + 0.5 * value_noise(UV * 220.0);
	base = mix(base, base * vec3(1.06, 0.84, 0.82), clamp((knee_zone * 0.8 + knuckle_zone * 0.7) * joint_blotch, 0.0, 1.0));
	base = mix(base, base * vec3(0.8, 0.72, 0.7), clamp(elbow_zone * 0.7 * joint_blotch, 0.0, 1.0));
	// nipples: the areola about 13 mm across, a soft edge, darker and redder toward the middle
	if (has_nipples) {
		for (int i = 0; i < 2; i++) {
			float r = length(local_pos - nipples[i]);
			float areola = 1.0 - smoothstep(0.009, 0.014, r);
			float teat = 1.0 - smoothstep(0.002, 0.0045, r);
			base = mix(base, base * vec3(0.78, 0.58, 0.54), areola * 0.75);
			base = mix(base, base * vec3(0.85, 0.7, 0.68), teat * 0.5);
		}
	}
	float armpit_zone = 0.0;
	if (has_armpits) {
		for (int i = 0; i < 2; i++) {
			armpit_zone = max(armpit_zone, 1.0 - smoothstep(0.02, 0.05, length(local_pos - armpits[i])));
		}
		base = mix(base, base * vec3(0.8, 0.76, 0.74), armpit_zone * 0.6);
	}
	// palms and soles: the lighter of the skin and a pale pinkish beige, a little pinker (soles: facing down within a few centimetres of the ground)
	float sole_zone = has_joints ? smoothstep(0.3, 0.7, -normalize(local_normal).y) * (1.0 - smoothstep(0.025, 0.05, local_pos.y)) : 0.0;
	float palms = max(palm_zone, sole_zone);
	base = mix(base, max(base, vec3(0.5, 0.31, 0.26)) * vec3(1.04, 0.94, 0.92), palms * 0.85);
	// veins: blue-green under the skin (shows more on light skin: the multiply keeps dark skin nearly unchanged)
	base = mix(base, base * vec3(0.66, 0.78, 0.92), vein_line * 0.75);
	// fingernails: a lighter, pinker plate (the nail bed under a clear nail), or the polish
	base = mix(base, mix(base * vec3(1.15, 0.95, 0.95) + vec3(0.06, 0.04, 0.04), nail_polish_color, nail_polish), nail_zone * 0.9);
	// redness: blood close under thin skin (blotchy, not a flat stain)
	float painted = has_skin_tex ? 0.5 : 1.0;   // (a photo skin already has its own redness and shade round the eyes: ours on top doubled them, dark rings on the darker skins)
	float red_amount = redness * red_zone * painted * (0.75 + 0.5 * value_noise(UV * 260.0));
	base = mix(base, base * vec3(1.06, 0.86, 0.84), clamp(red_amount, 0.0, 1.0));   // (a stronger tint read as a pink blob on pale skin)
	// a few tiny red spots and broken capillaries anywhere (more where the skin is red)
	vec2 spot = cells(UV * 320.0);
	float spot_amount = smoothstep(0.22, 0.08, spot.x) * step(0.965 - 0.03 * red_zone, spot.y) * redness;
	base = mix(base, base * vec3(1.05, 0.70, 0.68), spot_amount * 0.7);
	// round the eyes: thinner skin over the veins, darker and violet
	base = mix(base, base * vec3(0.78, 0.70, 0.78), eye_shadow * eye_zone * 0.8 * painted);
	// shave shadow: the hairs under the skin, dots that merge into a grey-blue cast at a distance
	vec2 follicle_p = UV * pore_scale * 0.6;
	float follicle_fade = 1.0 - smoothstep(0.5, 1.4, length(fwidth(follicle_p)));
	float dots = smoothstep(0.30, 0.12, cells(follicle_p).x);
	// (the stubble under the skin is the hair's colour: dark hair shows a strong shadow, blond or light red hair hardly any; scalp_color is the hair colour x0.55)
	float hair_dark = clamp(1.0 - dot(scalp_color, vec3(0.3, 0.59, 0.11)) / 0.09, 0.15, 1.0);
	float shave = shave_shadow * shave_zone * hair_dark;
	base = mix(base, base * vec3(0.50, 0.54, 0.62), clamp(shave * mix(0.85, 0.45 + 0.9 * dots, follicle_fade), 0.0, 1.0));
	// freckles and a few moles
	if (spots > 0.0) {
		vec2 sc = cells(UV * 110.0 + 4.0);
		float spot = smoothstep(0.26, 0.1, sc.x) * step(1.0 - 0.08 * spots, sc.y);
		base = mix(base, base * vec3(0.7, 0.58, 0.5), spot * mix(0.35, 0.8, fract(sc.y * 41.0)));
	}
	if (freckles > 0.0) {
		// in clusters (sun on the nose and cheeks), each a different size and darkness
		float cluster = smoothstep(0.25, 0.75, value_noise(UV * 45.0)) * 0.7 + 0.3;
		vec2 fc = cells(UV * 380.0);
		float size = mix(0.12, 0.34, fract(fc.y * 7.13));
		float freckle = smoothstep(size, size * 0.45, fc.x) * step(1.0 - min(freckles * freckle_zone * cluster * 1.4, 0.9), fc.y);
		base = mix(base, base * vec3(0.62, 0.46, 0.36), freckle * mix(0.55, 0.9, fract(fc.y * 3.7)));
		vec2 mc = cells(UV * 60.0);
		float mole = smoothstep(0.08, 0.05, mc.x) * step(0.985, mc.y) * freckles;
		base = mix(base, base * vec3(0.45, 0.32, 0.25), mole);
	}
	if (has_lips && local_pos.z > lip_info.y) {
		// the lips: an ellipse around the mouth, a soft edge, redder and a little darker than the skin (the body has no lip colour of its own)
		vec2 lq = vec2(abs(local_pos.x) / (0.034 * lip_info.z), (local_pos.y - lip_y) / ((local_pos.y > lip_y ? 0.0135 : 0.0105) * lip_info.z));
		float lip = 1.0 - smoothstep(0.7, 1.0, length(lq));
		float skin_light = clamp(dot(base, vec3(0.3, 0.55, 0.15)) / 0.35, 0.25, 1.0);
		vec3 lip_tone = mix(base * vec3(0.92, 0.58, 0.58), lip_color * skin_light, 0.45);   // (lips follow the skin: darker skin, darker brown-pink lips)
		base = mix(base, lip_tone * mix(0.8, 1.15, value_noise(UV * 900.0)), lip * 0.8);
		base = mix(base, lipstick_color * mix(0.9, 1.08, value_noise(UV * 900.0)), lip * lipstick * 0.92);
	}
	// makeup over the skin (after the lips: the blush and the shadow are on the skin around them)
	base = mix(base, base * mix(vec3(1.0), blush_color * 1.6, 0.6), blush * blush_zone * 0.55);
	base = mix(base, eyeshadow_color, eyeshadow * shadow_zone * 0.75);
	base = mix(base, vec3(0.025, 0.02, 0.02), eyeliner * liner_zone * 0.95);
	// ---- relief: wrinkles bend the normal (bump from the height's screen derivatives), pores go in the normal map ----
	if (has_face && abs(wrinkle_h) > 0.0) {
		vec3 dpdx = dFdx(VERTEX);
		vec3 dpdy = dFdy(VERTEX);
		float dhx = dFdx(wrinkle_h);
		float dhy = dFdy(wrinkle_h);
		vec3 r1 = cross(dpdy, NORMAL);
		vec3 r2 = cross(NORMAL, dpdx);
		float det = dot(dpdx, r1);
		if (abs(det) > 1e-12) {
			vec3 grad = sign(det) * (dhx * r1 + dhy * r2);
			NORMAL = normalize(abs(det) * NORMAL - grad);
		}
		base *= 1.0 + clamp(wrinkle_h * 120.0, -0.12, 0.0);   // (a crease is a little darker: less light gets in)
	}
	float scalp_here = clamp(scalp * scalp_amount, 0.0, 1.0);
	float rough = roughness_value;
	if (has_skin_spec) {
		rough = mix(0.85, 0.35, texture(skin_spec, UV).r);   // (MakeHuman spec maps are mostly mid-grey: 0.5 gives the old roughness of 0.6)
	}
	if (has_skin_normal) {
		NORMAL_MAP = texture(skin_normal, UV).rgb;
		NORMAL_MAP_DEPTH = normal_strength;
	} else if (pore_strength > 0.0) {
		vec2 p = UV * pore_scale;
		float footprint = length(fwidth(p));
		float fade = 1.0 - smoothstep(0.6, 1.8, footprint);   // (more than a pore per pixel: it would only shimmer)
		float pit_depth = 0.35 + 0.65 * pore_zone;
		float e = 0.35;
		float h = pore_height(p, pit_depth);
		float hx = pore_height(p + vec2(e, 0.0), pit_depth);
		float hy = pore_height(p + vec2(0.0, e), pit_depth);
		vec3 bump = normalize(vec3(-(hx - h) * 1.8, (hy - h) * 1.8, 1.0));   // (UV v runs down, a normal map's y up: the y slope is flipped, or the pits light like bumps)
		NORMAL_MAP = mix(vec3(0.5, 0.5, 1.0), bump * 0.5 + 0.5, fade);
		NORMAL_MAP_DEPTH = pore_strength * 1.6 * pore_zone;
		rough = clamp(rough + (0.5 - h) * 0.18 * fade, 0.0, 1.0);   // (pores are rougher, the skin between them catches the light)
		base *= 1.0 - clamp(0.45 - h, 0.0, 1.0) * 0.12 * fade * pore_strength;   // (a pore is a little darker inside)
	}
	// ---- debug: the zones as colours ----
	if (skin_debug == 1) {
		base = vec3(0.45) + vec3(red_zone * 0.5, oil_zone * 0.5, shave_zone * 0.6) + vec3(0.35, 0.0, 0.35) * eye_zone + vec3(0.6) * clamp(-wrinkle_h * 2500.0, 0.0, 1.0) - vec3(0.0, 0.3, 0.3) * ear_zone;
		base = mix(base, vec3(0.0, 0.0, 0.0), liner_zone);   // (makeup zones: the liner black, the shadow yellow)
		base = mix(base, vec3(1.0, 0.9, 0.0), shadow_zone * 0.6);
		base = mix(base, vec3(1.0, 0.0, 0.0), knee_zone);     // (joints: knees red, elbows blue, knuckles green)
		base = mix(base, vec3(0.0, 0.2, 1.0), elbow_zone);
		base = mix(base, vec3(0.0, 1.0, 0.0), knuckle_zone);
		base = mix(base, vec3(1.0, 0.0, 1.0), nail_zone);
		base = mix(base, vec3(0.0, 0.6, 1.0), vein_line);
		base = mix(base, vec3(1.0, 1.0, 0.0), palm_zone);
		base = mix(base, vec3(1.0, 0.5, 0.0), armpit_zone);
	}
	ALBEDO = mix(base, scalp_color, scalp_here);
	if (skin_debug == 2) {
		ALBEDO = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz * 0.5 + 0.5;   // (debug: the shading normal in world space)
	} else if (skin_debug == 3) {
		ALBEDO = (INV_VIEW_MATRIX * vec4(normalize(cross(dFdx(VERTEX), dFdy(VERTEX))), 0.0)).xyz * 0.5 + 0.5;   // (debug: the flat face normals: the triangles)
	}
	// the oily second shine: a sharp clearcoat lobe over the soft skin one, and the skin itself a little smoother there
	// (a broad soft sheen broken up by the pores, not a wet mirror)
	float oil_here = oil * oil_zone * (1.0 - scalp_here);
	if (has_lips && local_pos.z > lip_info.y) {
		vec2 lq2 = vec2(abs(local_pos.x) / (0.034 * lip_info.z), (local_pos.y - lip_y) / ((local_pos.y > lip_y ? 0.0135 : 0.0105) * lip_info.z));
		oil_here = max(oil_here, lipstick * 0.8 * (1.0 - smoothstep(0.7, 1.0, length(lq2))));   // (lipstick has a sheen)
	}
	rough = clamp(rough - 0.06 * oil_here, 0.0, 1.0);
	CLEARCOAT = oil_here * 0.22 * (0.6 + 0.4 * value_noise(UV * 900.0));
	CLEARCOAT_ROUGHNESS = 0.62;
	rough = clamp(rough + 0.15 * elbow_zone + 0.08 * knee_zone, 0.0, 1.0);   // (elbows and knees are drier)
	rough = mix(rough, mix(0.38, 0.18, nail_polish), nail_zone);   // (a nail is smooth; polish is glossy)
	ROUGHNESS = mix(rough, 1.0, scalp_here);   // the scalp is matte: seen at a grazing angle through a gap in the hair, a glossy skin showed up as a white speck
	SPECULAR = mix(0.5, 0.0, scalp_here);
	RIM = fuzz * 0.3 * (1.0 - scalp_here);
	RIM_TINT = 0.7;   // (mostly the light's colour, a little the skin's)
	SSS_STRENGTH = sss_strength * (1.0 - scalp_here) * (1.0 - 0.85 * nostril_zone);
	// light through the thin parts: the ears most, the nose a little (needs the light's shadow to know the thickness)
	SSS_TRANSMITTANCE_COLOR = vec4(1.0, 0.28, 0.18, 1.0);
	// (never 0: Godot's skin transmittance divides by it, 8.25 / depth, and times a shadow-depth difference of exactly 0 that is NaN; a NaN pixel was smeared into
	// striped blocks by the screen-space SSS and washed the whole frame white in the Forest background, on and off as the trees' shadows changed)
	SSS_TRANSMITTANCE_DEPTH = max(0.03 * ear_zone, 0.001);
	SSS_TRANSMITTANCE_BOOST = sss_strength * 0.5 * ear_zone;
}
