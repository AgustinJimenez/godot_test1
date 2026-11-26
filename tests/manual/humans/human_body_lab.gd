extends Node3D
## Human body lab: the two base bodies (female, male) with Height and Weight sliders.
##
## The bodies come from MPFB in Blender (see docs/blender_workflow.md): one mesh each with six
## blend shapes (height_short/tall, weight_light/heavy, muscle_low/high). A blend shape is a stored "move every vertex
## by this much" shape; the slider just sets how much of it to apply, so no mesh is rebuilt.
## Drag with the right mouse button to turn the body; mouse wheel zooms.
## Capture mode: `-- --capture=<png path>` saves one frame and quits.

const BODY_SCENES: Dictionary = {
	"Female": "res://assets/models/humans/female_body.glb",
	"Male": "res://assets/models/humans/male_body.glb",
}
## Plain villager clothes (tools/blender/make_clothes.py): a long-sleeved tunic shirt and trousers with a belt, cut from the body like the underwear (same blend shapes).
const CLOTHES_SCENES: Dictionary = {
	"Female": ["res://assets/models/humans/female_shirt.glb", "res://assets/models/humans/female_pants.glb"],
	"Male": ["res://assets/models/humans/male_shirt.glb", "res://assets/models/humans/male_pants.glb"],
}
const CLOTHES: Array = ["Villager", "Underwear"]
## (shirt colour, trousers colour) of the villager clothes: undyed linen and brown wool for him, a darker linen and grey-brown wool for her
const CLOTHES_COLOURS: Dictionary = {
	"Male": [Color(0.72, 0.66, 0.55), Color(0.33, 0.25, 0.18)],
	"Female": [Color(0.62, 0.55, 0.45), Color(0.3, 0.27, 0.23)],
}
const UNDERWEAR_SCENES: Dictionary = {
	"Female": "res://assets/models/humans/female_underwear.glb",
	"Male": "res://assets/models/humans/male_underwear.glb",
}
## Starting points for the head hair; every entry is a HumanHair parameter (the native class documents them).
const TressFXBridge := preload("res://tests/manual/humans/tressfx_bridge.gd")
# The face and age sliders (signed: negative = the first key, positive = the second). The keys come from tools/blender/make_bodies.py (MakeHuman targets). The deltas are small at 1.0 (mm to cm): the range goes to 1.5 (at 2 the narrowed head pushed an eyeball out of its socket).
# The face sliders (MakeHuman targets baked as blend-shape pairs by tools/blender/make_bodies.py). [name, key at -1, key at +1, range (default 1.5)];
# a one-element entry is a heading.
const FACE_SLIDERS: Array = [
	["Head"],
	["Age (young .. old)", "age_young", "age_old"],
	["Head width", "head_narrow", "head_wide", 1.0],   # (the optional 4th number is the slider range: a narrower head than 1.0 squeezes the eye socket until the eyeball shows through the cheek)
	["Face length", "face_short", "face_long", 1.0],
	["Forehead height", "forehead_low", "forehead_high", 1.0],
	["Ear size", "ears_small", "ears_big"],
	["Neck (thin .. thick)", "neck_thin", "neck_thick", 1.0],
	["Eyes and brows"],
	["Eye size", "eyes_small", "eyes_big"],
	["Eye spacing (close .. apart)", "eyes_close", "eyes_apart", 1.0],
	["Eye height", "eyes_down", "eyes_up", 1.0],
	["Eye slant (outer corners down .. up)", "eyes_slant_down", "eyes_slant_up", 1.0],
	["Eyelid fold (low .. high)", "eyelids_low", "eyelids_high", 1.0],
	["Eye bags (less .. more)", "eye_bags_less", "eye_bags_more", 1.0],
	["Eye depth (shallow .. deep-set)", "eyes_shallow", "eyes_deep", 1.0],
	["Brow ridge (flat .. strong)", "brow_ridge_less", "brow_ridge_more", 0.6],   # (at 1 the brow juts out like a ledge)
	["Brow height", "brows_down", "brows_up", 1.0],
	["Brow angle (down .. up at the ends)", "brows_angle_down", "brows_angle_up", 1.0],
	["Nose"],
	["Nose width", "nose_narrow", "nose_wide"],
	["Nose length", "nose_short", "nose_long"],
	["Nose bridge (straight .. hump)", "nose_hump_less", "nose_hump_more", 1.0],
	["Nose tip (down .. up)", "nose_tip_down", "nose_tip_up", 1.0],
	["Nostrils (narrow .. wide)", "nostrils_narrow", "nostrils_wide", 1.0],
	["Mouth, cheeks and jaw"],
	["Lips (thin .. full)", "lips_thin", "lips_full"],
	["Mouth width", "mouth_narrow", "mouth_wide", 1.0],
	["Mouth corners (down .. up)", "mouth_corners_down", "mouth_corners_up", 1.0],
	["Cheeks (hollow .. full)", "cheeks_hollow", "cheeks_full"],
	["Cheekbones (low .. high)", "cheekbones_low", "cheekbones_high", 1.0],
	["Jaw width", "jaw_narrow", "jaw_wide", 1.0],
	["Chin (receding .. prominent)", "chin_receding", "chin_prominent"],
	["Chin width", "chin_narrow", "chin_wide", 1.0],
]
# The body's proportions (same mechanism as the face: blend-shape pairs, baked into the hair build), on the Body tab under Height/Weight/Muscle.
const BODY_SHAPE_SLIDERS: Array = [
	["Proportions"],
	["Shoulders", "shoulders_narrow", "shoulders_wide", 1.0],
	["Waist", "waist_narrow", "waist_wide", 1.0],
	["Hips", "hips_narrow", "hips_wide", 1.0],
	["Belly (flat .. round)", "belly_flat", "belly_round", 0.6],   # (the MakeHuman target at full weight is a pregnancy)
	["Bust", "bust_small", "bust_big", 1.0],
]
const FACE_AGE_EYE_DY: Dictionary = {"Male": {"young": -0.1964, "old": -0.0235}, "Female": {"young": -0.1664, "old": -0.0083}}
const BEARD_STYLES: Array = [   # name, amount, length (m), zone (0 full, 1 goatee, 2 circle beard, 3 moustache, 4 mutton chops, 5 chin strap), neck beard
	["None", 0.0, 0.0, 0.0, 0.0], ["Stubble", 0.7, 0.003, 0.0, 0.5], ["Short", 0.8, 0.007, 0.0, 0.12], ["Full", 0.9, 0.012, 0.0, 0.3],
	["Long", 1.0, 0.03, 0.0, 0.6], ["Goatee", 0.9, 0.01, 1.0, 0.0], ["Circle beard", 0.9, 0.01, 2.0, 0.0], ["Curly", 0.95, 0.02, 0.0, 0.3, 0.8],
	["Moustache", 0.95, 0.008, 3.0, 0.0], ["Mutton chops", 0.9, 0.012, 4.0, 0.0], ["Chin strap", 0.9, 0.006, 5.0, 0.15],
]
# The skin shader's procedural detail (human_skin.gdshader): [shown name, uniform, low, high, default = the shader's]. The shave shadow's start follows the body.
const SKIN_DETAIL: Array = [
	["Skin tone (flat colour: very light .. very dark)", &"skin_tone", 0.0, 1.0, 0.45],
	["Undertone (pink .. neutral .. olive)", &"undertone", -1.0, 1.0, 0.0],
	["Redness (nose, cheeks, ears)", &"redness", 0.0, 1.0, 0.5],
	["Shadows round the eyes", &"eye_shadow", 0.0, 1.0, 0.65],
	["Shave shadow (stubble under the skin)", &"shave_shadow", 0.0, 1.0, 0.0],
	["Oily shine (forehead, nose, cheekbones)", &"oil", 0.0, 1.0, 0.5],
	["Pores", &"pore_strength", 0.0, 1.0, 0.5],
	["Age (wrinkles)", &"age", 0.0, 1.0, 0.25],
	["Freckles", &"freckles", 0.0, 1.0, 0.0],
	["Small spots and moles", &"spots", 0.0, 1.0, 0.35],
	["Light through the skin (ears, edges)", &"sss_strength", 0.0, 1.0, 0.35],
	["Peach fuzz (soft sheen at the edges)", &"fuzz", 0.0, 1.0, 0.35],
	["Knees, elbows, knuckles (redder, darker)", &"joint_tone", 0.0, 1.0, 0.5],
	["Veins (hands, forearms)", &"veins", 0.0, 1.0, 0.3],
]
# The Monk Skin Tone scale (Google, CC-BY 4.0: ten swatches of real skin, sRGB), the flat skin colour's range; a little redder than the swatches
# (they are photographed under neutral light; under the lab's filmic light they read grey-yellow otherwise).
const SKIN_TONES: Array = [Color("#f6ede4"), Color("#f3e7db"), Color("#f7ead0"), Color("#eadaba"), Color("#d7bd96"), Color("#a07e56"), Color("#825c43"), Color("#604134"), Color("#3a312a"), Color("#292420")]
# Brow styles: [shown name, file suffix] ({male,female}_brows<suffix>.glb, Mindfront CC0 layouts fitted by tools/blender/fit_mindfront.py)
const BROW_STYLES: Array = [["Thick, flat", "_mf"], ["Thin, straight", "_mf03"], ["Thick, arched", "_mf06"], ["Medium, arched", "_mf09"]]   # (our first generated brows, suffix "", look poor next to these: --face-hair= still loads them)
# Makeup (human_skin.gdshader): [shown name, amount uniform, colour uniform ("" = none), default colour]
const MAKEUP: Array = [
	["Lipstick", &"lipstick", &"lipstick_color", Color(0.6, 0.08, 0.12)],
	["Blush", &"blush", &"blush_color", Color(0.85, 0.35, 0.35)],
	["Eyeshadow", &"eyeshadow", &"eyeshadow_color", Color(0.35, 0.25, 0.35)],
	["Eyeliner", &"eyeliner", &"", Color.BLACK],
	["Nail polish", &"nail_polish", &"nail_polish_color", Color(0.55, 0.05, 0.1)],
]
const SKIN_FILES: Array = [   # CC0 MakeHuman skins, 1k (assets/models/humans/skins/CREDITS.md); both bodies share the MakeHuman UV layout
	["Male: light bronze", "male_light_bronze"], ["Male: light freckles", "male_light_freckles"], ["Male: light ginger", "male_light_ginger"],
	["Male: african", "male_african_middleage"],
	["Female: light bronze", "female_light_bronze"], ["Female: light freckles", "female_light_freckles"], ["Female: light ginger", "female_light_ginger"],
	["Female: midtoned", "female_midtoned"], ["Female: caucasian", "female_caucasian"], ["Female: young eurasian", "female_young_eurasian"], ["Female: indian", "female_indian"],
]
const EYE_COLOURS: Array = [   # natural iris colours (sRGB, as the picker shows them)
	["Dark brown", Color(0.26, 0.12, 0.03)], ["Brown", Color(0.4, 0.21, 0.06)]   , ["Hazel", Color(0.42, 0.32, 0.14)], ["Amber", Color(0.55, 0.36, 0.12)],
	["Green", Color(0.3, 0.4, 0.2)], ["Grey", Color(0.42, 0.46, 0.48)], ["Blue", Color(0.25, 0.45, 0.7)], ["Light blue", Color(0.45, 0.62, 0.8)],
]
const HAIR_COLOURS: Array = [   # natural colours only (names after the Fischer-Saller scale's groups: black, brown, blond, red, red-blond; grey and white from age). sRGB as the picker shows them, chosen by how they RENDER on the head (lighter than the swatch)
	["Black", Color(0.04, 0.035, 0.03)],
	["Dark brown", Color(0.15, 0.09, 0.05)],
	["Medium brown", Color(0.2, 0.12, 0.075)],
	["Light brown", Color(0.33, 0.22, 0.14)],
	["Auburn", Color(0.21, 0.09, 0.06)],
	["Red", Color(0.35, 0.16, 0.08)],
	["Strawberry blonde", Color(0.53, 0.35, 0.24)],
	["Dark blonde", Color(0.43, 0.32, 0.19)],
	["Blonde", Color(0.58, 0.45, 0.26)],
	["Light blonde", Color(0.68, 0.57, 0.36)],
	["Grey", Color(0.43, 0.43, 0.44)],
	["White", Color(0.66, 0.66, 0.66)],
]

const HAIR_PRESETS: Dictionary = {
	"Buzz": {&"side_trim": 0.0, &"length": 0.025, &"volume": 0.2, &"curl": 0.0, &"fringe": 0.3, &"sweep": 0.0, &"hug": 0.0, &"gravity": 0.2, &"parting": 0.0, &"strands": 40, &"points": 6},
	"Short": {&"side_trim": 0.55, &"length": 0.07, &"volume": 1.0, &"curl": 0.0, &"fringe": 0.35, &"sweep": 0.0, &"hug": 0.7, &"gravity": 0.7, &"parting": 0.2, &"strands": 40, &"points": 6},
	"Dapper": {&"side_trim": 0.75, &"length": 0.10, &"volume": 1.0, &"curl": 0.0, &"fringe": 0.1, &"sweep": 0.45, &"hug": 0.2, &"gravity": 0.7, &"parting": 0.5, &"quiff": 0.8, &"swept": 0.3, &"strands": 40, &"points": 6},
	"Pompadour": {&"side_trim": 0.9, &"length": 0.13, &"volume": 1.2, &"curl": 0.0, &"fringe": 0.1, &"sweep": 0.5, &"hug": 0.1, &"gravity": 0.6, &"parting": 0.1, &"quiff": 1.0, &"swept": 0.0, &"strands": 40, &"points": 6},
	"Side part": {&"side_trim": 0.7, &"length": 0.08, &"volume": 0.9, &"curl": 0.0, &"fringe": 0.25, &"sweep": 0.15, &"hug": 0.5, &"gravity": 0.8, &"parting": 0.55, &"quiff": 0.1, &"swept": 0.2, &"strands": 40, &"points": 6},
	"Undercut": {&"side_trim": 1.0, &"length": 0.14, &"volume": 1.0, &"curl": 0.0, &"fringe": 0.2, &"sweep": 0.6, &"hug": 0.1, &"gravity": 0.7, &"parting": 0.4, &"quiff": 0.5, &"swept": 0.5, &"strands": 40, &"points": 6},
	"Crew cut": {&"side_trim": 0.6, &"length": 0.03, &"volume": 0.4, &"curl": 0.0, &"fringe": 0.35, &"sweep": 0.0, &"hug": 0.8, &"gravity": 0.3, &"parting": 0.0, &"quiff": 0.4, &"swept": 0.0, &"strands": 40, &"points": 6},
	"Messy crop": {&"side_trim": 0.6, &"length": 0.07, &"volume": 1.3, &"curl": 0.15, &"fringe": 0.8, &"sweep": 0.0, &"hug": 0.2, &"gravity": 0.7, &"parting": 0.2, &"quiff": 0.2, &"swept": 0.0, &"strands": 40, &"points": 6},
	"Wavy medium": {&"side_trim": 0.0, &"length": 0.22, &"volume": 1.1, &"curl": 0.7, &"fringe": 0.0, &"sweep": 0.3, &"hug": 0.0, &"gravity": 0.9, &"parting": 0.5, &"quiff": 0.9, &"swept": 1.0, &"strands": 32, &"points": 10},
	"Curtains": {&"side_trim": 0.3, &"length": 0.13, &"volume": 1.0, &"curl": 0.05, &"fringe": 0.55, &"sweep": 0.0, &"hug": 0.1, &"gravity": 0.9, &"parting": 0.0, &"quiff": 0.0, &"swept": 0.0, &"strands": 32, &"points": 6},
	"Quiff": {&"side_trim": 0.8, &"length": 0.09, &"volume": 1.1, &"curl": 0.0, &"fringe": 0.1, &"sweep": 0.3, &"hug": 0.1, &"gravity": 0.6, &"parting": 0.0, &"quiff": 1.0, &"swept": 0.0, &"strands": 40, &"points": 6},
	"Fade": {&"side_trim": 1.0, &"length": 0.07, &"volume": 1.0, &"curl": 0.0, &"fringe": 0.2, &"sweep": 0.2, &"hug": 0.5, &"gravity": 0.6, &"parting": 0.35, &"quiff": 0.5, &"swept": 0.0, &"strands": 40, &"points": 6},
	"Shaggy": {&"side_trim": 0.2, &"length": 0.12, &"volume": 1.7, &"curl": 0.6, &"fringe": 0.25, &"sweep": 0.0, &"hug": 0.0, &"gravity": 0.55, &"parting": 0.2, &"quiff": 0.1, &"swept": 0.2, &"strands": 32, &"points": 10},
	"Bowl cut": {&"side_trim": 0.35, &"length": 0.09, &"volume": 1.0, &"curl": 0.0, &"fringe": 0.9, &"sweep": 0.0, &"hug": 0.0, &"gravity": 1.0, &"parting": 0.0, &"quiff": 0.0, &"swept": 0.0, &"strands": 32, &"points": 6},
	"Side fringe": {&"side_trim": 0.5, &"length": 0.16, &"volume": 1.0, &"curl": 0.0, &"fringe": 0.25, &"sweep": 0.0, &"hug": 0.0, &"gravity": 1.0, &"parting": 0.7, &"quiff": 0.0, &"swept": 1.0, &"strands": 32, &"points": 6},
	"Bedhead": {&"side_trim": 0.3, &"length": 0.11, &"volume": 1.7, &"curl": 0.3, &"fringe": 0.4, &"sweep": 0.0, &"hug": 0.0, &"gravity": 0.3, &"parting": 0.1, &"quiff": 0.3, &"swept": 0.0, &"strands": 40, &"points": 6},
	"French crop": {&"side_trim": 0.9, &"length": 0.05, &"volume": 1.0, &"curl": 0.0, &"fringe": 1.0, &"sweep": 0.0, &"hug": 0.3, &"gravity": 0.9, &"parting": 0.0, &"quiff": 0.0, &"swept": 0.0, &"strands": 40, &"points": 6},
	"Slick undercut": {&"side_trim": 1.0, &"length": 0.16, &"volume": 0.9, &"curl": 0.0, &"fringe": 0.0, &"sweep": 1.0, &"hug": 0.3, &"gravity": 0.8, &"parting": 0.3, &"quiff": 0.3, &"swept": 0.0, &"strands": 40, &"points": 7},
	"Mop top": {&"side_trim": 0.2, &"length": 0.14, &"volume": 1.3, &"curl": 0.1, &"fringe": 0.9, &"sweep": 0.0, &"hug": 0.0, &"gravity": 0.9, &"parting": 0.0, &"quiff": 0.0, &"swept": 0.0, &"strands": 40, &"points": 7},
	"Pixie": {&"side_trim": 0.8, &"length": 0.06, &"volume": 1.2, &"curl": 0.1, &"fringe": 0.5, &"sweep": 0.0, &"hug": 0.1, &"gravity": 0.6, &"parting": 0.4, &"quiff": 0.2, &"swept": 0.8, &"strands": 40, &"points": 6},
	"Ivy league": {&"side_trim": 0.7, &"length": 0.09, &"volume": 0.9, &"curl": 0.0, &"fringe": 0.3, &"sweep": 0.3, &"hug": 0.4, &"gravity": 0.8, &"parting": 0.6, &"quiff": 0.0, &"swept": 0.6, &"strands": 40, &"points": 6},
	"Long waves": {&"side_trim": 0.0, &"length": 0.3, &"volume": 1.1, &"curl": 0.18, &"fringe": 0.0, &"sweep": 0.3, &"hug": 0.0, &"gravity": 1.0, &"parting": 0.5, &"quiff": 0.5, &"swept": 1.0, &"strands": 36, &"points": 12},
	"Spiky": {&"side_trim": 0.6, &"length": 0.07, &"volume": 1.6, &"curl": 0.0, &"fringe": 0.1, &"sweep": 0.0, &"hug": 0.0, &"gravity": 0.05, &"parting": 0.0, &"quiff": 0.0, &"swept": 0.0, &"spike": 0.75, &"strands": 40, &"points": 7},
	"Surfer": {&"side_trim": 0.1, &"length": 0.17, &"volume": 1.2, &"curl": 0.3, &"fringe": 0.0, &"sweep": 0.6, &"hug": 0.1, &"gravity": 0.7, &"parting": 0.1, &"quiff": 0.3, &"swept": 0.0, &"strands": 36, &"points": 9},
	"Feathered": {&"side_trim": 0.3, &"length": 0.2, &"volume": 1.3, &"curl": 0.1, &"fringe": 0.0, &"sweep": 0.3, &"hug": 0.0, &"gravity": 0.8, &"parting": 0.35, &"quiff": 0.6, &"swept": 0.8, &"strands": 36, &"points": 9},
	"Cropped waves": {&"side_trim": 0.6, &"length": 0.09, &"volume": 1.2, &"curl": 0.45, &"fringe": 0.2, &"sweep": 0.0, &"hug": 0.2, &"gravity": 0.7, &"parting": 0.0, &"quiff": 0.2, &"swept": 0.0, &"strands": 40, &"points": 9},
	"Afro": {&"side_trim": 0.1, &"length": 0.09, &"volume": 2.0, &"curl": 1.0, &"fringe": 0.1, &"sweep": 0.0, &"hug": 0.0, &"gravity": 0.1, &"parting": 0.0, &"quiff": 0.0, &"swept": 0.0, &"strands": 40, &"points": 10},
	"Bob": {&"side_trim": 0.0, &"length": 0.17, &"volume": 1.0, &"curl": 0.0, &"fringe": 0.0, &"sweep": 0.0, &"hug": 0.0, &"gravity": 1.0, &"parting": 0.3, &"strands": 40, &"points": 7, &"swept": 0.6, &"quiff": 0.5},
	"Long": {&"side_trim": 0.0, &"length": 0.32, &"volume": 0.9, &"curl": 0.2, &"fringe": 0.0, &"sweep": 0.3, &"hug": 0.0, &"gravity": 1.0, &"parting": 0.5, &"strands": 40, &"points": 8, &"swept": 1.0, &"quiff": 0.5},
	"Slick back": {&"side_trim": 0.85, &"length": 0.15, &"volume": 0.8, &"curl": 0.0, &"fringe": 0.0, &"sweep": 1.0, &"gravity": 0.8, &"parting": 0.0, &"strands": 40, &"points": 6},
	"Wet messy": {&"side_trim": 0.55, &"length": 0.18, &"volume": 0.6, &"curl": 0.0, &"fringe": 0.3, &"sweep": 0.1, &"quiff": 0.3, &"swept": 0.1, &"hug": 0.6, &"gravity": 1.7, &"parting": 0.2, &"messy": 0.45, &"wave": 0.6, &"gaps": 0.6, &"wisps": 0.5, &"strips": 1.0, &"wet": 0.8, &"scalp_layer": 1.0, &"shine": 0.6, &"back_length": 0.5, &"tousle": 0.8, &"target_hairs": 40000, &"strand_width": 0.0011, &"strands": 40, &"points": 14},
	"Curly": {&"side_trim": 0.1, &"length": 0.12, &"volume": 1.3, &"curl": 0.9, &"fringe": 0.6, &"sweep": 0.0, &"hug": 0.0, &"gravity": 0.6, &"parting": 0.0, &"strands": 36, &"points": 10},
}
const EYE_SCENES: Dictionary = {
	"Female": "res://assets/models/humans/female_eyes.glb",
	"Male": "res://assets/models/humans/male_eyes.glb",
}
## Height slider -1..1 maps to blend-shape weight -HEIGHT_RANGE..HEIGHT_RANGE (full 1.0 is about
## 1.4 m taller than the base, far too much).
const HEIGHT_RANGE: float = 0.6
## weight_heavy is built heavy in Blender (tools/blender/heavy_mix.py: max-weight macro plus fat / girth targets), so it is used as made. (It was
## MakeHuman's max weight alone, about 3 cm at the waist, pushed to 3.0: that made hard lumps on the flanks. Keep in step with HumanRig::shape_weights.)
const WEIGHT_GAIN_HEAVY: float = 1.0
## The light shape is already at its designed size at 1.0; pushed to 3.0 it folds the waist and hips of the
## female body, so it only goes a little past.
const WEIGHT_GAIN_LIGHT: float = 1.25
## Muscle shapes move the body about 2-4 cm at 1.0; same split as weight (more on the high side, little past
## the designed range on the low side). Starting values, to be checked at the extremes.
const MUSCLE_GAIN_HIGH: float = 2.0
const MUSCLE_GAIN_LOW: float = 1.25

## Metres, measured on the exported meshes: base height, and how much a full height_tall shape adds / a full
## height_short shape removes.
const BASE_HEIGHT: Dictionary = {"Female": 1.61, "Male": 1.75}
const HEIGHT_TALL_M: float = 0.70
const HEIGHT_SHORT_M: float = 0.36

var _body: Node3D
var _mesh: MeshInstance3D
var _underwear_mesh: MeshInstance3D
var _cloth_material: ShaderMaterial
var _eyes_mesh: MeshInstance3D
var _brows_mesh: MeshInstance3D
var _lashes_mesh: MeshInstance3D
var _hair_mesh: MeshInstance3D
var _head_hair_material: ShaderMaterial
var _hair_style: Dictionary = {}
var _hair_sliders: Dictionary = {}
var _hair_defaults: Dictionary = {}   # the style parameters a fresh lab starts with (Reset hair)
var _hair_slider_labels: Dictionary = {}   # key -> [Label, base text]: the label shows the slider value
var _slider_label_time: float = 0.0
var _head_hair_color: Color = Color(0.15, 0.09, 0.05)   # "Dark brown" in HAIR_COLOURS
var _hair_colour_option: OptionButton = null   # the Hair tab's colour dropdown (HAIR_COLOURS + "Custom")
var _scalp_layer: float = 1.0   # the solid base under the hair (0 = none): it read as paint on the head
var _head_hair_density: float = 1.0
var _hair_dirty: bool = false
var _hair_friction: float = 0.05   # friction on small movements (Motion tab): 0 = none, higher = small wiggles die out faster
var _hair_max_swing: float = 0.4   # how far a point may leave its place in the style (share of the hair length up to it)
var _hair_tip: float = 0.25   # how firmly the tips are pulled back to the style (springiness)
var _hair_air: float = 0.15   # air drag across a strand (a swing slows down like real hair)
var _hair_strand_damp: float = 0.2   # damping of the difference in velocity between neighbouring points (the strand's own wobble)
var _hair_local: float = 0.3   # local shape (TressFX style): each segment keeps its angle to the previous one
var _hair_bend: float = 0.8   # bending stiffness (Motion section): how firmly a hair keeps its shape along its length
var _hair_root_stiffness: float = 0.35   # how firmly the roots hold the style (the tips are left free)
var _tressfx: bool = false   # --tressfx: draw and simulate the hair with the TressFX addon (comparison; needs res://addons/tressfx)
var _tfx_root: Node3D
var _tfx_library: bool = false   # --tfxlib: the addon's own demo hair on our head (nothing of our hair code in it)
var _hair_weight: float = 1.0   # how heavy the hair is (Motion tab): the simulation sags more and swings longer when heavy
var _hair_build_ms: float = 0.0   # how long the last hair build took
var _hair_last_change_ms: int = -100000   # when a hair slider last moved
var _switch_gender_arg: String = ""   # --switch-gender=Female: switch to that body 2.5 s after the start (tests: what the switch costs)
var _switch_gender_done: bool = false
var _switch_watch_until_ms: int = 0   # after a gender switch: frames slower than 50 ms are printed until then (GENDER_SWITCH lines)
var _switch_preset: String = ""   # --switch=Name: apply this preset 2.5 s after the start (tests: the longest frame while the hair builds)
var _switch_done: bool = false
var _show_follicles: bool = false   # the roots of the guide strands as dots, hair hidden (a check of where the hair grows from)
var _follicle_node: MultiMeshInstance3D = null
var _scalp_debug_shown: bool = false   # the Hair tab's debug box: scalp regions (coloured after the reference chart) and the growth direction of the guides as arrows
var _scalp_debug_node: Node3D = null
var _beard_only_change: bool = false   # the change that made the hair dirty was a beard one: no cheaper head-hair preview then (the head must not thin out while the beard length moves)
var _beard_tab: VBoxContainer = null   # (disabled on the female body: no beard there)
var _beard_follicles_shown: bool = false   # the Beard tab's debug box: the roots of the beard hairs as dots, hair hidden
var _beard_follicle_node: MultiMeshInstance3D = null
var _beard_area_shown: bool = false   # the Beard tab's second debug box: the skin area the beard grows on, tinted
var _beard_area_node: MeshInstance3D = null
var _style_gender: String = "Male"   # the body the current style was picked for
const DEFAULT_TARGET_HAIRS: int = 170000   # the real number of hairs every style aims for (a head has 100,000-150,000): hairs per lock are scaled to reach it
# Hair levels of detail (LOD): the lower levels draw fewer, wider hairs with fewer points each, so the cost falls with the distance and the coverage stays.
#   level: share of the hairs, points per hair (cap), width x, beard, wisps
const HAIR_LODS: Array = [
	[1.0, 16, 1.0, true, 1.0],
	[0.35, 8, 1.6, true, 0.6],
	[0.1, 5, 3.0, false, 0.2],
	[0.03, 4, 6.0, false, 0.0],
]
const LOD_DISTANCES: Array = [2.2, 4.5, 9.0]   # camera distance (m) above which the next level starts
var _lod: int = 0
var _lod_forced: int = -1   # --lod=N or the slider: a fixed level (-1 = by the camera distance)
var _target_hairs: int = DEFAULT_TARGET_HAIRS   # a preset can ask for fewer, thicker hairs (wet, clumped hair is drawn with fewer hairs so that single strands show)
var _strand_scale: float = 1.0   # learned: real hairs = guides x strands x about 0.58 (fewer hairs per lock near the hairline), so the first guess is 1 / 0.58
const MAX_HAIR_VERTICES: int = 4150000   # the vertex limit of ONE hair surface (65,535 compute groups x 64 vertices = 4,194,240; the builder cuts bigger meshes into several surfaces)
var _hair_guard_retry: int = 0
var _crowd: int = 0              # --crowd=N: N-1 more copies of the body and the hair (shared meshes, not simulated) in a grid: a cost test for several characters
var _crowd_nodes: Array = []
var _fade_old: MeshInstance3D = null   # the previous level, still drawn while the new one fades in
var _fade_t: float = 1.0
var _fade_pending: bool = false         # set when the level changed: the next finished build cross-fades
var _lod_switch_to: int = -1
var _fade_hold: float = -1.0            # --fade-hold=0..1: freeze the cross-fade at this point (tests)
var _hair_retry: int = 0
var _hair_task_id: int = -1   # the hair is built on a worker thread (HumanHair.build_arrays is pure data), so the lab does not freeze for 1-3 s
var _hair_task_result: Dictionary = {}
var _hair_task_started_us: int = 0
var _hair_task_body: Node3D = null   # the body the running build was started for (a gender switch while it runs: its result is thrown away)
var _body_hair: Dictionary = {"amount": 0.3, "chest": 1.0, "belly": 1.0, "back": 0.3, "arms": 1.0, "legs": 1.0, "armpits": 1.0, "length": 0.012, "curl": 0.4}   # the body hair (male): HumanBodyHair's settings (--body-hair=amount)
var _body_hair_mesh: MeshInstance3D = null
var _cloth_sim: bool = true   # the villager clothes simulated as cloth (task 103; --cloth=off, the "Simulate" box)
var _cloth_rig: Node3D = null   # the rigged body, hidden, at the visible body's place: its skeleton drives the simulated clothes, its mesh is the collider
var _cloth_solvers: Array = []
var _cloth_pieces: Array = []   # the simulated shirt and trousers (the static ones are hidden while these run)
var _cloth_restart_ms: int = -1   # when the simulation restarts (a slider moved: it waits until the slider rests)
var _cloth_shape_key: String = ""   # the body shapes the running simulation was built for
var _clothes: String = "Villager"   # "Villager" (a shirt and trousers) or "Underwear" (--clothes=underwear)
var _shirt_mesh: MeshInstance3D = null
var _pants_mesh: MeshInstance3D = null
var _shirt_material: ShaderMaterial
var _cloth_flaws: Dictionary = {"seed": 1.0, "imperfection": 0.5, "wear": 0.5}   # the clothes' stains, holes, patches and wear (each character its own seed)
var _pants_material: ShaderMaterial
var _body_hair_dirty_ms: int = -1   # a body hair setting changed at this time (rebuilt 200 ms after the last change)
var _hair_ever_built: bool = false   # after the first hair: later builds never block the frame (a gender switch showed a frozen lab for ~1 s)
var _hair_preview: bool = false   # building the cheap version (a sixth of the hairs) while a slider is being dragged
var _hair_next_build_ms: int = 0   # not before this time (Time.get_ticks_msec)
var _hair_enabled: bool = true
var _sim: HairSim   # the real hair simulation (native HairSim): guide strands with gravity, inertia and collisions
var _sim_enabled: bool = true
var _solo: bool = false      # --solo: grow exactly one hair and put the camera on it
var _solo_root: bool = false # --solo-root: ... and go in close on its root
var _aim: Vector3 = Vector3.ZERO
var _use_aim: bool = false
var _spin: bool = false      # --spin: hide the panel, hold still 3 s, then turn the body once in 4 s (for recording a video)
var _spin_time: float = 0.0
var _capture_at: int = 20   # --captureat=<frame>: the frame a --capture is taken (later = the hair has had time to settle)
var _sim_overrides: Dictionary = {}   # --sim=gravity:0,bend_stiffness:0: any HairSim property, for tests
var _pitch: float = 0.0   # camera height angle (radians): drag up/down with the right mouse button
var _osc_period: float = 0.0   # --osc=<seconds a half turn (180 degrees) takes>: random turns of 90..180 degrees either way with short pauses (the same sequence every run), panel hidden, to watch the hair swing
var _hide_panel: bool = false   # --nopanel: no control panel in the picture
var _osc_rng := RandomNumberGenerator.new()
var _osc_from: float = 0.3
var _osc_to: float = 0.3
var _osc_t: float = 0.0
var _osc_dur: float = 0.0
var _osc_pause: float = 1.0
var _ui_layer: CanvasLayer
var _panel: Control   # the control panel: the mouse wheel over it scrolls it instead of zooming the camera
# hair motion: wind (metres of bend at the tips) and a small spring that swings the hair when the head turns
var _wind: float = 0.0
var _shake_side: float = 1.0
var _hair_sway: HairSway
var _tip_color: Color = Color(0.8, 0.2, 0.45)
var _tip_mix: float = 0.0
var _shake_on_capture: bool = false
var _shine_override: float = -1.0
var _brow_material: ShaderMaterial
var _lash_material: ShaderMaterial
var _hair_color: Color = Color(0.16, 0.1, 0.06)
var _mh_hair: String = ""   # --mh-hair=hair_messy:short_messy_diff.png: a CC0 MakeHuman hair shell (tools/blender/fit_mh_mesh.py) instead of our hair, for comparison
var _face_values: Dictionary = {}   # shape key -> weight (the face sliders): applied as blend shapes to the body/eyes/brows and BAKED into the body the hair is built on
var _face_arg: String = ""
var _beard_colour_arg: String = ""
var _skin_file: String = ""      # --skin=male_light_bronze: one of the shipped skins (assets/models/humans/skins)
# the skin shader's procedural detail (Skin tab): key -> value, only what was changed (the shader's defaults otherwise); --skin-set=key:value,...
var _skin_values: Dictionary = {}
var _skin_shave_set: bool = false   # (the shave shadow follows the body (on for the male) until it is moved)
var _skin_sliders: Dictionary = {}
var _shape_sliders: Dictionary = {}
var _rig_cache: Dictionary = {}   # rig file path -> its parsed JSON (the skin's joint zones)
var _landmarks_dirty_ms: int = -1   # when the body's shapes last changed (-1: the skin's landmarks are up to date)
# saved characters (CharacterStore): the whole editor state under a name. Loading restarts the lab scene with the state applied at start, the
# way the command-line flags are (every control then starts at its value): the state waits in a static variable across the reload.
static var _pending_character: Dictionary = {}
static var _pending_character_name: String = ""
static var _pending_random: Dictionary = {}   # a random character's hairstyle and beard (applied by the lab's own preset/beard code after the reload)
static var _reload_test_done: bool = false
static var _random_character_done: bool = false   # (--random-character rolls once, not again after its own reload)   # --test-reload-character=<name>: load it through the panel's path (scene reload) once
var _characters_dir: String = "user://characters"   # (--characters-dir= for tests: they must not write the user's characters)
var _character_name: String = ""
var _load_character_arg: String = ""
var _save_character_arg: String = ""
var _test_brow_style: int = -1   # --test-brow-style=<index>: switch to that brow style after the start (the Brows tab's picker)
var _random_face_seed: int = -1
var _random_character_seed: int = -1   # --random-character=<seed>: roll a random character at start (the Random button, seeded)
var _beard_grey: float = 0.0     # the Beard tab's grey and ginger locks (the hair shader's beard_grey / beard_ginger)
var _beard_ginger: float = 0.0
var _hair_grey: float = 0.0       # greying head hair (the hair shader's hair_grey: salt and pepper)
var _hair_grey_slider: HSlider = null
var _brow_grey: float = 0.0   # greying brows (the face-hair shader's grey; the lashes grey a quarter as much), set by the whole-character Age
var _whole_age_arg: float = -9.0   # --whole-age=<-1..1>: move the Body tab's Age slider at start (tests, captures)
var _beard_grey_slider: HSlider = null   # --random-face=<seed>: start with a random face (the Face tab's button, seeded)
var _character_option: OptionButton = null
var _character_name_edit: LineEdit = null
var _character_zones_pending: Variant = null   # the first key of a face/body shape pair -> its slider (Random face, Reset face)
var _skin_tex_path: String = ""   # --skin-tex=<absolute png>: a skin diffuse map (e.g. a CC0 MakeHuman skin) read from outside the project, for a comparison
var _wet: float = 0.0
var _wet_slider: HSlider = null
var _brow_given: bool = false
var _face_hair_suffix: String = "_mf"   # the Mindfront (CC0, MakeHuman) brow and lash layout fitted by tools/blender/fit_mindfront.py (*_brows_mf.glb)
var _brow_density: float = 0.8
var _eye_material: ShaderMaterial
var _eye_color: Color = Color(0.32, 0.2, 0.1)
var _eye_color_other: Color = Color(0.25, 0.45, 0.7)
var _different_eyes: bool = false
var _iris_deg: float = 26.0
var _pupil: float = 0.38
var _sclera_tint: float = 0.0
var _veins: float = 0.25
var _second_eye_row: Control
var _gender: String = "Male"
var _height: float = 0.0
var _weight: float = 0.0
var _muscle: float = 0.0
var _yaw: float = 0.3
const FACE_DISTANCE := 0.35        # camera distance (m) for the eyes and brows close-up
const FACE_DISTANCE_HAIR := 0.55   # ... and for the hair tab: a little farther back
const FACE_DISTANCE_BEARD := 0.26   # the beard tab: closer, and looking at the jaw
const BEARD_LOOK_DROP := 0.095      # ... how far below the eyes the camera looks (the middle of the beard)
const FACE_HAIR_LIFT := 0.0        # ... (extra camera height for the hair tab: none, the eyes stay in the centre and the hair fits above them)
var _face_hair: bool = false
var _settle_override: int = -1   # --settle=N: steps the hair simulation runs at start (default: the native default)
var _start_tab: String = ""   # --tab=Hair: start on that tab (Body, Eyes, Brows, Hair, Beard)
var _distance: float = 3.6
var _shadows_arg: String = ""
var _wrap_arg: float = -1.0   # --wrap=: the hair shader's wrap_k (0.25 grey room, 0.7 in --env=real)
var _sun_gain_arg: float = -1.0   # --sun-gain=: the hair shader's sun strength (default 0.15, 0.45 in --env=real)
var _shadow_dist: float = 1.2   # --shadow-dist=m: how far the sun shadow map reaches (a small value = fine texels on the head)
var _shadow_bias: float = 0.05   # (0.001 drew shadow acne: concentric bands over the forehead and neck, even on a smooth sphere; 0.05 is clean and the small bias gave the hair almost no self-shadow anyway)
var _shadow_normal_bias: float = 0.05
var _ssao_arg: String = ""
var _real_env: bool = true      # a sky, shadows from the sun, ambient occlusion and a filmic tonemap (a place to judge the hair in, not a grey room); false in the Studio background
const BACKGROUNDS: Array = ["Forest", "Sky", "Studio"]   # Forest: sky, sun, grass and trees around; Sky: the same light, an empty sky (--env=real); Studio: the grey room
var _background: String = "Forest"   # --background=forest|sky|studio (--env=real = sky)
var _env_root: Node3D = null   # the light, sky and ground of the background (rebuilt when it changes)
var _bark_baked: bool = false
var _scalp_arg: float = -1.0    # --scalp-layer=0..1: overrides the preset value (tests)
var _beard_look_dy: float = -0.03   # --look-dy=m: the Beard camera aims this far above (+) or below (-) the beard view height (+0.07 looks at the mouth)
var _beard_view: bool = false   # the Beard tab is open: the camera looks at the jaw
var _look_y: float = 0.95
var _cam_y: float = 1.0
var _face_mode: bool = false
var _camera: Camera3D
var _readout: Label
var _fps_label: Label
var _fps_accum: float = 0.0
var _fps_frames: int = 0
var _fps_label_fps: float = 0.0
var _bench_seconds: float = 0.0   # --bench=<seconds>: measure fps and GPU/CPU frame time for that long (after 3 s warm-up), print it and quit
var _bench_time: float = 0.0
var _bench_n: int = 0
var _bench_rebuilds: int = 0
var _bench_since: float = 0.0
var _bench_spike: float = 0.0
var _bench_gpu: float = 0.0
var _bench_cpu: float = 0.0
var _bench_fps: float = 0.0
var _hair_info: String = "" # how much hair there is (shown under the readout)
var _material: ShaderMaterial
var _capture_path: String = ""
var _capture_frames: int = 0


func _ready() -> void:
	get_viewport().msaa_3d = Viewport.MSAA_4X   # hair-thin strands alias into dots without it (the Forest background uses FXAA instead: _build_environment)
	_hair_style = HumanHair.default_params()
	_hair_style["beard_length"] = 0.0   # (shaved until a beard style or the length slider says otherwise)
	_hair_style["extras"] = 0.0     # only the evenly spaced follicles (no extra locks crowding the hairline, crown and nape)
	_hair_style["locks"] = 4200     # follicles: with 40 hairs each, about 150,000 hairs
	for key: StringName in HAIR_PRESETS["Dapper"]:
		_hair_style[key] = HAIR_PRESETS["Dapper"][key]
	_hair_style[&"amount"] = 1.0   # (the Hair amount slider: only zones change it; the whole head has all its hair)
	_hair_defaults = _hair_style.duplicate()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			_capture_path = arg.trim_prefix("--capture=")
		elif arg == "--close":
			_distance = 1.3
			_look_y = 0.85
		elif arg.begins_with("--height="):
			_height = float(arg.trim_prefix("--height="))
		elif arg == "--tressfx":
			_tressfx = true
		elif arg == "--tfxlib":
			_tressfx = true
			_tfx_library = true
		elif arg.begins_with("--tfx="):
			for pair in arg.trim_prefix("--tfx=").split(","):
				var kv := pair.split(":")
				if kv.size() == 2:
					TressFXBridge.options[kv[0]] = float(kv[1])
		elif arg.begins_with("--weight="):
			_weight = float(arg.trim_prefix("--weight="))
		elif arg.begins_with("--muscle="):
			_muscle = float(arg.trim_prefix("--muscle="))
		elif arg == "--face":
			_distance = 0.8
			_look_y = 1.58
			_cam_y = 1.58
			_face_mode = true
		elif arg.begins_with("--eye="):
			_eye_color = Color.html(arg.trim_prefix("--eye="))
		elif arg.begins_with("--distance="):
			_distance = float(arg.trim_prefix("--distance="))
		elif arg.begins_with("--brow="):
			_hair_color = Color.html(arg.trim_prefix("--brow="))
			_brow_given = true
		elif arg.begins_with("--density="):
			_brow_density = float(arg.trim_prefix("--density="))
		elif arg == "--solo":
			_solo = true
			_hair_style[&"locks"] = 1
			_hair_style[&"strands"] = 1
		elif arg == "--solo-root":
			_solo = true
			_solo_root = true
			_yaw = 0.0
			_hair_style[&"locks"] = 1
			_hair_style[&"strands"] = 1
		elif arg == "--nopanel":
			_hide_panel = true
		elif arg.begins_with("--osc="):
			_osc_period = float(arg.trim_prefix("--osc="))
		elif arg.begins_with("--weight="):
			_hair_weight = float(arg.trim_prefix("--weight="))
		elif arg.begins_with("--friction="):
			_hair_friction = float(arg.trim_prefix("--friction="))
		elif arg.begins_with("--settle="):
			_settle_override = int(arg.trim_prefix("--settle="))
		elif arg.begins_with("--tab="):
			_start_tab = arg.trim_prefix("--tab=")
		elif arg.begins_with("--shadow-dist="):
			_shadow_dist = float(arg.trim_prefix("--shadow-dist="))
		elif arg.begins_with("--shadow-bias="):
			_shadow_bias = float(arg.trim_prefix("--shadow-bias="))
		elif arg.begins_with("--shadow-nbias="):
			_shadow_normal_bias = float(arg.trim_prefix("--shadow-nbias="))
		elif arg.begins_with("--wrap="):
			_wrap_arg = float(arg.trim_prefix("--wrap="))
		elif arg.begins_with("--sun-gain="):
			_sun_gain_arg = float(arg.trim_prefix("--sun-gain="))
		elif arg == "--env=real":
			_background = "Sky"
		elif arg.begins_with("--background="):
			_background = arg.trim_prefix("--background=").capitalize()
			if not BACKGROUNDS.has(_background):
				_background = "Forest"
		elif arg.begins_with("--scalp-layer="):
			_scalp_arg = float(arg.trim_prefix("--scalp-layer="))
			_scalp_layer = _scalp_arg
		elif arg.begins_with("--shadows="):
			_shadows_arg = arg.trim_prefix("--shadows=")
		elif arg.begins_with("--crowd="):
			_crowd = int(arg.trim_prefix("--crowd="))
		elif arg.begins_with("--fade-hold="):
			_fade_hold = float(arg.trim_prefix("--fade-hold="))
		elif arg.begins_with("--lod-switch="):
			_lod_switch_to = int(arg.trim_prefix("--lod-switch="))   # --lod-switch=N: 3 s after the start force level N (tests the cross-fade)
		elif arg.begins_with("--lod="):
			_lod_forced = int(arg.trim_prefix("--lod="))
			_lod = clampi(_lod_forced, 0, HAIR_LODS.size() - 1)
		elif arg.begins_with("--bench="):
			_bench_seconds = float(arg.trim_prefix("--bench="))
		elif arg == "--nosim":
			_sim_enabled = false
		elif arg == "--spin":
			_spin = true
		elif arg == "--nohair":
			_hair_enabled = false
		elif arg.begins_with("--test-brow-style="):
			_test_brow_style = int(arg.trim_prefix("--test-brow-style="))
		elif arg.begins_with("--whole-age="):
			_whole_age_arg = float(arg.trim_prefix("--whole-age="))
		elif arg.begins_with("--random-character="):
			_random_character_seed = int(arg.trim_prefix("--random-character="))
		elif arg.begins_with("--random-face="):
			_random_face_seed = int(arg.trim_prefix("--random-face="))
		elif arg.begins_with("--characters-dir="):
			_characters_dir = arg.trim_prefix("--characters-dir=")
		elif arg.begins_with("--test-reload-character=") and not _reload_test_done:
			_reload_test_done = true
			var test_name: String = arg.trim_prefix("--test-reload-character=")
			(func() -> void:
				var state: Dictionary = CharacterStore.load_character(_characters_dir, test_name)
				if not state.is_empty():
					_pending_character = state
					_pending_character_name = test_name
					get_tree().reload_current_scene()).call_deferred()
		elif arg.begins_with("--load-character="):
			_load_character_arg = arg.trim_prefix("--load-character=")
		elif arg.begins_with("--save-character="):
			_save_character_arg = arg.trim_prefix("--save-character=")
		elif arg.begins_with("--styles-dir="):
			_styles_dir = arg.trim_prefix("--styles-dir=")
		elif arg.begins_with("--save-style="):
			_save_style_arg = arg.trim_prefix("--save-style=")
		elif arg.begins_with("--hair-preset=") and not HAIR_PRESETS.has(arg.trim_prefix("--hair-preset=")):
			_pending_saved_style = arg.trim_prefix("--hair-preset=")   # (a saved style: applied after the arguments, when --styles-dir is known)
		elif arg.begins_with("--hair-preset="):
			var preset: Dictionary = HAIR_PRESETS[arg.trim_prefix("--hair-preset=")]
			_hair_preset_name = arg.trim_prefix("--hair-preset=")
			for reset_key: StringName in [&"quiff", &"swept", &"spike", &"hug", &"sweep", &"strands", &"points", &"messy", &"wave", &"gaps", &"wisps", &"strips", &"back_length", &"tousle"]:   # what the preset does not name is off (as the button does), not what the starting style left
				if not preset.has(reset_key):
					_hair_style[reset_key] = 0.0
			for key: StringName in preset:
				_hair_style[key] = preset[key]
			_wet = float(preset.get(&"wet", 0.0))
			_scalp_layer = float(preset.get(&"scalp_layer", 1.0))
			if preset.has(&"shine") and _shine_override < 0.0:
				_shine_override = float(preset[&"shine"])
			_target_hairs = int(preset.get(&"target_hairs", DEFAULT_TARGET_HAIRS))
			_strand_scale = float(_target_hairs) / float(DEFAULT_TARGET_HAIRS) * 0.6   # (the first guess: the build then learns the real value)
		elif arg.begins_with("--tip="):
			_tip_color = Color.html(arg.trim_prefix("--tip="))
		elif arg.begins_with("--tip-amount="):
			_tip_mix = float(arg.trim_prefix("--tip-amount="))
		elif arg.begins_with("--style="):
			for pair in arg.trim_prefix("--style=").split(","):   # --style=parting:0.5,swept:0.2 (tests): hair values after the preset
				var skv := pair.split(":")
				if skv.size() == 2:
					_hair_style[StringName(skv[0])] = float(skv[1])
		elif arg == "--follicles":
			_show_follicles = true
		elif arg == "--scalp-debug":
			_scalp_debug_shown = true
		elif arg == "--beard-area":
			_beard_area_shown = true
		elif arg == "--beard-follicles":
			_beard_follicles_shown = true   # (the Beard tab's debug box, on from the start: tests)
		elif arg.begins_with("--cloth-flaws="):
			var parts: PackedStringArray = arg.trim_prefix("--cloth-flaws=").split(",")
			_cloth_flaws["imperfection"] = clampf(float(parts[0]), 0.0, 1.0)
			if parts.size() > 1:
				_cloth_flaws["seed"] = float(parts[1])
		elif arg == "--cloth=off":
			_cloth_sim = false
		elif arg.begins_with("--clothes="):
			_clothes = arg.trim_prefix("--clothes=").capitalize()
			if not CLOTHES.has(_clothes):
				_clothes = "Villager"
		elif arg.begins_with("--body-hair="):
			_body_hair["amount"] = clampf(float(arg.trim_prefix("--body-hair=")), 0.0, 1.0)
		elif arg.begins_with("--switch-gender="):
			_switch_gender_arg = arg.trim_prefix("--switch-gender=")
		elif arg.begins_with("--switch="):
			_switch_preset = arg.trim_prefix("--switch=")
		elif arg.begins_with("--face-hair="):
			_face_hair_suffix = arg.trim_prefix("--face-hair=")   # e.g. _mf03: another Mindfront brow style (preview)
		elif arg.begins_with("--mh-hair="):
			_mh_hair = arg.trim_prefix("--mh-hair=")
			_hair_enabled = false
		elif arg.begins_with("--face="):
			_face_arg = arg.trim_prefix("--face=")   # --face=nose_wide:1.5,age_old:0.5
		elif arg.begins_with("--look-y="):
			_look_y = float(arg.trim_prefix("--look-y="))   # (captures: the height the camera looks at, after --close/--face)
			_cam_y = _look_y
		elif arg.begins_with("--look-dy="):
			_beard_look_dy = float(arg.trim_prefix("--look-dy="))
		elif arg.begins_with("--beard-colour="):
			_beard_colour_arg = arg.trim_prefix("--beard-colour=")   # --beard-colour=grey:0.5,ginger:0.3 (tests)
		elif arg.begins_with("--skin="):
			_skin_file = arg.trim_prefix("--skin=")
		elif arg.begins_with("--skin-set="):
			for entry: String in arg.trim_prefix("--skin-set=").split(",", false):
				var parts: PackedStringArray = entry.split(":")
				if parts.size() == 2:
					_skin_values[StringName(parts[0])] = float(parts[1])
					if parts[0] == "shave_shadow":
						_skin_shave_set = true
		elif arg.begins_with("--skin-tex="):
			_skin_tex_path = arg.trim_prefix("--skin-tex=")
		elif arg == "--classic-face-hair":
			_face_hair_suffix = ""   # our own first brows and lashes (make_face_hair.py)
		elif arg.begins_with("--sim="):
			for pair in arg.trim_prefix("--sim=").split(","):
				var kv := pair.split(":")
				if kv.size() == 2:
					_sim_overrides[kv[0]] = float(kv[1])
		elif arg.begins_with("--captureat="):
			_capture_at = int(arg.trim_prefix("--captureat="))
		elif arg.begins_with("--pitch="):
			_pitch = deg_to_rad(float(arg.trim_prefix("--pitch=")))
		elif arg.begins_with("--yaw="):
			_yaw = deg_to_rad(float(arg.trim_prefix("--yaw=")))
		elif arg.begins_with("--shine="):
			_shine_override = float(arg.trim_prefix("--shine="))
		elif arg == "--shake":
			_shake_on_capture = true
		elif arg.begins_with("--wind="):
			_wind = float(arg.trim_prefix("--wind="))
		elif arg.begins_with("--hair-colour="):
			_head_hair_color = Color.html(arg.trim_prefix("--hair-colour="))
		elif arg.begins_with("--strands="):
			_hair_style[&"strands"] = float(arg.trim_prefix("--strands="))
		elif arg.begins_with("--hair-set="):
			# --hair-set=key:value (any HumanHair parameter), e.g. --hair-set=length:0.2
			var pair: PackedStringArray = arg.trim_prefix("--hair-set=").split(":")
			_hair_style[StringName(pair[0])] = float(pair[1])
		elif arg.begins_with("--eye2="):
			_eye_color_other = Color.html(arg.trim_prefix("--eye2="))
			_different_eyes = true
		elif arg.begins_with("--iris="):
			_iris_deg = float(arg.trim_prefix("--iris="))
		elif arg.begins_with("--pupil="):
			_pupil = float(arg.trim_prefix("--pupil="))
		elif arg.begins_with("--sclera="):
			_sclera_tint = float(arg.trim_prefix("--sclera="))
		elif arg.begins_with("--veins="):
			_veins = float(arg.trim_prefix("--veins="))
		elif arg.begins_with("--ssao="):
			_ssao_arg = arg.trim_prefix("--ssao=")
		elif arg.begins_with("--gender="):
			_gender = arg.trim_prefix("--gender=")
		elif arg.begins_with("--zone-edit="):
			_zone_edit_arg = arg.trim_prefix("--zone-edit=")   # (captures: start with this zone chosen in the Editing dropdown)
		elif arg.begins_with("--hair-zone="):
			_hair_zone_arg = arg.trim_prefix("--hair-zone=")   # zone:setting:value,... (after --hair-preset, whatever the order)
	if _load_character_arg != "":
		_pending_character = CharacterStore.load_character(_characters_dir, _load_character_arg)
		if not _pending_character.is_empty():
			_character_name = _load_character_arg
	if not _pending_character.is_empty():
		_apply_character_state(_pending_character)
		_pending_character = {}
		if _pending_character_name != "":
			_character_name = _pending_character_name
			_pending_character_name = ""
	_build_environment()
	_build_material()
	_build_ui()
	if _pending_saved_style != "":
		_on_hair_preset(_pending_saved_style)
	var random_beard: int = -1
	if not _pending_random.is_empty():
		_on_hair_preset(str(_pending_random["preset"]))
		random_beard = int(_pending_random.get("beard", -1))
		_pending_random = {}
	# (after a saved style, before the body is set: that starts the first hair build)
	for entry: String in _hair_zone_arg.split(",", false):
		var parts: PackedStringArray = entry.split(":")
		if parts.size() == 3:
			if not _hair_zones.has(parts[0]):
				_hair_zones[parts[0]] = {}
			(_hair_zones[parts[0]] as Dictionary)[StringName(parts[1])] = float(parts[2])
	if _lod_forced < 0:
		_lod = clampi(_lod_for_distance(_distance), 0, HAIR_LODS.size() - 1)   # (the first hair is built for the starting distance: no full hair first and then a cheaper one)
		_strand_scale = clampf(_strand_scale * float(HAIR_LODS[_lod][0]), 0.08, 3.0)
	for pair in _face_arg.split(",", false):
		var parts: PackedStringArray = pair.split(":")
		if parts.size() == 2:
			_face_values[StringName(parts[0])] = float(parts[1])
	_set_gender(_gender)
	_update_beard_enabled()
	if random_beard >= 0:
		_on_beard_style(BEARD_STYLES[random_beard])
	_hair_zone_edit = _zone_edit_arg   # (last: choosing a style resets it)
	if _character_zones_pending != null:
		_hair_zones = _character_zones_pending   # (a loaded character's zones: after the style, which clears them)
		_character_zones_pending = null
		_hair_dirty = true
	if _test_brow_style >= 0:
		_on_brow_style.call_deferred(_test_brow_style)
	if _whole_age_arg > -2.0:
		_on_whole_age(_whole_age_arg)
	if _random_character_seed >= 0 and not _random_character_done:
		_random_character_done = true
		seed(_random_character_seed)
		_on_random_character.call_deferred()
	if _random_face_seed >= 0:
		seed(_random_face_seed)
		_on_random_face()
	if _save_character_arg != "":
		_save_character.call_deferred(_save_character_arg)
	_refresh_zone_ui()
	if _save_style_arg != "":
		_save_current_style(_save_style_arg)


func _build_environment() -> void:
	_real_env = _background != "Studio"
	if _env_root != null:
		_env_root.free()
	_env_root = Node3D.new()
	_env_root.name = "Background"
	add_child(_env_root)
	# The plants' shader (flora_wind) under 4x MSAA gives stray NaN pixels at leaf edges and a white veil over the whole frame, sky included (Godot 4.7.2; not its FOG
	# or BACKLIGHT, and not its realism), and TAA flashes whole frames of a wrong view while the body turns: the Forest background smooths the edges and the thin
	# hairs with FXAA (no history, no per-sample shading).
	var forest: bool = _background == "Forest"
	get_viewport().msaa_3d = Viewport.MSAA_DISABLED if forest else Viewport.MSAA_4X
	get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if forest else Viewport.SCREEN_SPACE_AA_DISABLED
	var env := Environment.new()
	if _real_env:
		var sky_material := ProceduralSkyMaterial.new()
		sky_material.sky_top_color = Color(0.32, 0.5, 0.85)
		sky_material.sky_horizon_color = Color(0.72, 0.8, 0.9)
		sky_material.ground_horizon_color = Color(0.62, 0.62, 0.6)
		sky_material.ground_bottom_color = Color(0.3, 0.3, 0.3)
		var sky := Sky.new()
		sky.sky_material = sky_material
		env.sky = sky
		env.background_mode = Environment.BG_SKY
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_energy = 1.3
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		env.tonemap_exposure = 1.6   # (filmic darkens: the skin read as dark copper at exposure 1)
		env.tonemap_white = 6.0
		env.ssao_enabled = true
		env.ssao_radius = 0.12
		env.ssao_intensity = 3.0
		env.ssao_detail = 1.0
		if _ssao_arg == "off":
			env.ssao_enabled = false   # --ssao=off: tests (the ambient occlusion shows the triangles of the coarse body as diagonal bands)
		elif _ssao_arg != "":
			env.ssao_intensity = float(_ssao_arg)
	env.background_mode = Environment.BG_SKY if _real_env else Environment.BG_COLOR
	env.background_color = Color(0.22, 0.23, 0.26)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.55, 0.6)
	env.ambient_light_energy = 0.35
	if forest:
		env.tonemap_exposure = 0.9   # (a whole sunlit scene, the ground lit too: 1.6 washes the sky, the grass and the leaves out)
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_env_root.add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35.0, 35.0, 0.0)
	sun.light_energy = 0.8
	if _real_env:
		sun.light_energy = 2.4
		sun.rotation_degrees = Vector3(-42.0, 38.0, 0.0)
		sun.shadow_enabled = true
		sun.directional_shadow_max_distance = _shadow_dist
		sun.shadow_bias = _shadow_bias
		sun.shadow_normal_bias = _shadow_normal_bias
		sun.shadow_blur = 1.2
	if _shadows_arg == "on":
		sun.shadow_enabled = true   # --shadows=on|off: the sun casts shadows (the hair is a shadow caster and receiver: tests)
	elif _shadows_arg == "off":
		sun.shadow_enabled = false
	_env_root.add_child(sun)
	RenderingServer.global_shader_parameter_set(&"cloud_sun_world", sun.global_transform.basis.z)   # the plants' shader lights its leaves from the way to the sun (the planet sets it in the game)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-10.0, -140.0, 0.0)
	fill.light_energy = 0.0 if _real_env else 0.25
	_env_root.add_child(fill)
	var floor_mesh := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 1.1
	disc.bottom_radius = 1.1
	disc.height = 0.02
	floor_mesh.mesh = disc
	floor_mesh.position.y = -0.011
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.3, 0.3, 0.33)
	floor_mesh.material_override = floor_mat
	floor_mesh.visible = not OS.get_cmdline_user_args().has("--nofloor") and _background != "Forest"   # (--nofloor: captures from below, the soles)
	_env_root.add_child(floor_mesh)
	if _background == "Forest" and not OS.get_cmdline_user_args().has("--nofloor"):
		_build_forest()
	if _camera == null:
		_camera = Camera3D.new()
		_camera.fov = 38.0
		add_child(_camera)
	_update_camera()


# The Forest background: a grass clearing with trees around it (the planet's own plant species, realistic meshes), shrubs, ferns and tall grass near its edge.
# Nothing stands within 6 m, so no tree shadow crosses the body (the sun's shadow reaches only a short way, to stay sharp on the head).
func _build_forest() -> void:
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(240.0, 240.0)
	ground.mesh = plane
	ground.position.y = -0.002
	var ground_material := StandardMaterial3D.new()
	var noise := FastNoiseLite.new()
	noise.frequency = 0.02
	var noise_texture := NoiseTexture2D.new()
	noise_texture.noise = noise
	noise_texture.seamless = true
	var ramp := Gradient.new()   # patches of grass, dry grass and soil
	ramp.set_color(0, Color(0.2, 0.27, 0.11))
	ramp.set_color(1, Color(0.36, 0.38, 0.18))
	ramp.add_point(0.75, Color(0.33, 0.28, 0.17))
	noise_texture.color_ramp = ramp
	ground_material.albedo_texture = noise_texture
	ground_material.uv1_scale = Vector3(24.0, 24.0, 1.0)
	ground_material.roughness = 0.95
	ground.material_override = ground_material
	_env_root.add_child(ground)

	WorldWind.set_realism(1.0)
	if not _bark_baked:
		_bark_baked = true   # the barks are drawn once into the plants' shader, as the planet does when it starts (white trunks till then)
		var bark := PlanetBarkBake.new()
		add_child(bark)
		bark.run()
	var registry := SpeciesRegistry.create(7, 36)
	var trees: Array = []
	var undergrowth: Array = []
	for one: PlantSpecies in registry.species:
		if one.form == PlantSpecies.Form.CONIFER or one.form == PlantSpecies.Form.BROADLEAF:
			trees.append(one)
		elif one.form == PlantSpecies.Form.SHRUB or one.form == PlantSpecies.Form.TALL_GRASS or one.form == PlantSpecies.Form.FERN:
			undergrowth.append(one)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var placed: Array[Vector2] = []
	var tries := 0
	while placed.size() < 70 and tries < 2000 and not trees.is_empty():
		tries += 1
		var angle := rng.randf() * TAU
		var spot := Vector2(cos(angle), sin(angle)) * (15.0 + pow(rng.randf(), 0.7) * 45.0)
		var free := true
		for other: Vector2 in placed:
			if other.distance_to(spot) < 4.0:
				free = false
				break
		if not free:
			continue
		placed.append(spot)
		_add_plant(registry, trees[rng.randi() % trees.size()], Vector3(spot.x, 0.0, spot.y), rng.randf_range(0.8, 1.2), rng)
	for i in 60:
		if undergrowth.is_empty():
			break
		var angle := rng.randf() * TAU
		var spot := Vector2(cos(angle), sin(angle)) * rng.randf_range(6.0, 16.0)
		_add_plant(registry, undergrowth[rng.randi() % undergrowth.size()], Vector3(spot.x, 0.0, spot.y), rng.randf_range(0.8, 1.3), rng)


func _add_plant(registry: SpeciesRegistry, species: PlantSpecies, at: Vector3, size: float, rng: RandomNumberGenerator) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = registry.mesh(species.id, rng.randi() % maxi(species.variants, 1), true)
	instance.material_override = FloraMeshes.material()
	instance.position = at
	instance.rotation.y = rng.randf() * TAU
	instance.scale = Vector3.ONE * size
	_env_root.add_child(instance)


func _on_background_selected(index: int) -> void:
	_background = BACKGROUNDS[index]
	_build_environment()
	if _head_hair_material != null:
		_apply_light_parameters()


# The hair's light terms that differ between the grey room and the sunny backgrounds.
func _apply_light_parameters() -> void:
	_head_hair_material.set_shader_parameter(&"wrap_k", _wrap_arg if _wrap_arg >= 0.0 else (0.7 if _real_env else 0.25))
	_head_hair_material.set_shader_parameter(&"sun_gain", _sun_gain_arg if _sun_gain_arg >= 0.0 else (0.45 if _real_env else 0.15))


func _build_material() -> void:
	_material = ShaderMaterial.new()
	_material.shader = load("res://shaders/human_skin.gdshader")
	for key: StringName in _skin_values:
		_material.set_shader_parameter(key, _skin_values[key])
	_apply_skin_tone()
	# light under the skin: the high quality screen-space scattering (the project default is low), scaled for a head
	RenderingServer.sub_surface_scattering_set_quality(RenderingServer.SUB_SURFACE_SCATTERING_QUALITY_HIGH)
	if _skin_tex_path != "":
		var skin_image := Image.load_from_file(_skin_tex_path)
		if skin_image != null:
			skin_image.generate_mipmaps()
			_material.set_shader_parameter(&"skin_tex", ImageTexture.create_from_image(skin_image))
			_material.set_shader_parameter(&"has_skin_tex", true)
	if _skin_file != "":
		_on_skin_chosen(_skin_file)
	_cloth_material = ShaderMaterial.new()
	_cloth_material.shader = load("res://shaders/human_underwear_fabric.gdshader")
	var clothes_shader: Shader = load("res://shaders/human_clothes.gdshader")
	_shirt_material = ShaderMaterial.new()
	_shirt_material.shader = clothes_shader
	_pants_material = ShaderMaterial.new()
	_pants_material.shader = clothes_shader
	_pants_material.set_shader_parameter(&"threads_per_metre", 600.0)   # (wool: thicker yarn than the linen)
	_pants_material.set_shader_parameter(&"roughness_base", 0.93)
	_pants_material.set_shader_parameter(&"sheen", 0.35)
	_eye_material = ShaderMaterial.new()
	_eye_material.shader = load("res://shaders/human_eye.gdshader")
	_apply_eye_parameters()
	var hair_shader: Shader = load("res://shaders/human_face_hair.gdshader")
	_brow_material = ShaderMaterial.new()
	_brow_material.shader = hair_shader
	_lash_material = ShaderMaterial.new()
	_lash_material.shader = hair_shader
	_lash_material.set_shader_parameter(&"is_lash", true)
	for material: ShaderMaterial in [_brow_material, _lash_material]:
		material.set_shader_parameter(&"grey", _brow_grey)
	if not _brow_given:
		_hair_color = _brow_colour_for(_head_hair_color)
	_apply_hair_parameters()
	_head_hair_material = ShaderMaterial.new()
	_head_hair_material.shader = load("res://shaders/human_hair.gdshader")
	_head_hair_material.set_shader_parameter(&"hair_color", _head_hair_color)
	_head_hair_material.set_shader_parameter(&"scalp_layer", _scalp_layer)
	_head_hair_material.set_shader_parameter(&"density", _head_hair_density)
	_head_hair_material.set_shader_parameter(&"tip_color", _tip_color)
	_head_hair_material.set_shader_parameter(&"tip_mix", _tip_mix)
	if _shine_override >= 0.0:
		_head_hair_material.set_shader_parameter(&"shine", _shine_override)
	for pair in _beard_colour_arg.split(",", false):
		var parts: PackedStringArray = pair.split(":")
		if parts.size() == 2:
			_head_hair_material.set_shader_parameter(StringName("beard_" + parts[0]), float(parts[1]))
	_head_hair_material.set_shader_parameter(&"wet", _wet)
	if _beard_grey > 0.0:
		_head_hair_material.set_shader_parameter(&"beard_grey", _beard_grey)
	_head_hair_material.set_shader_parameter(&"hair_grey", _hair_grey)
	if _beard_ginger > 0.0:
		_head_hair_material.set_shader_parameter(&"beard_ginger", _beard_ginger)
	_apply_light_parameters()
	_head_hair_material.set_shader_parameter(&"wind", Vector3(1.0, 0.0, 0.35) * _wind)
	_hair_sway = HairSway.new()
	add_child(_hair_sway)


func _build_ui() -> void:
	_make_fps_label()
	var layer := CanvasLayer.new()
	add_child(layer)
	_ui_layer = layer
	layer.visible = not (_spin or _osc_period > 0.0 or _hide_panel)
	var panel := PanelContainer.new()
	panel.position = Vector2(16.0, 16.0)
	panel.theme = _panel_theme()
	layer.add_child(panel)
	_panel = panel
	# many controls: the panel scrolls
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(460.0, 840.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var scroll_margin := MarginContainer.new()   # (room between the controls and the scroll bar)
	scroll_margin.add_theme_constant_override(&"margin_right", 14)
	scroll.add_child(scroll_margin)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(410.0, 0.0)
	scroll_margin.add_child(box)
	var title := Label.new()
	title.text = "Human body lab"
	box.add_child(title)
	var gender_row := HBoxContainer.new()
	box.add_child(gender_row)
	for gender_name: String in BODY_SCENES:
		var button := Button.new()
		button.text = gender_name
		button.toggle_mode = true
		button.button_pressed = gender_name == _gender
		button.pressed.connect(_on_gender_button.bind(gender_name))
		button.name = gender_name
		button.add_to_group(&"gender_buttons")
		gender_row.add_child(button)
	var background_row := HBoxContainer.new()
	box.add_child(background_row)
	var background_label := Label.new()
	background_label.text = "Background"
	background_row.add_child(background_label)
	var background_option := OptionButton.new()
	background_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for background_name: String in BACKGROUNDS:
		background_option.add_item(background_name)
	background_option.select(BACKGROUNDS.find(_background))
	background_option.item_selected.connect(_on_background_selected)
	background_row.add_child(background_option)
	var clothes_label := Label.new()
	clothes_label.text = "Clothes"
	background_row.add_child(clothes_label)
	var clothes_option := OptionButton.new()
	clothes_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for clothes_name: String in CLOTHES:
		clothes_option.add_item(clothes_name)
	clothes_option.select(CLOTHES.find(_clothes))
	clothes_option.item_selected.connect(_on_clothes_selected)
	background_row.add_child(clothes_option)
	var cloth_box := CheckBox.new()
	cloth_box.text = "Simulate"
	cloth_box.tooltip_text = "Simulate the clothes as cloth: they hang, fold and swing when the body turns (about 1 ms a frame)"
	cloth_box.button_pressed = _cloth_sim
	cloth_box.toggled.connect(func(on: bool) -> void:
		_cloth_sim = on
		_restart_cloth())
	background_row.add_child(cloth_box)
	# whole characters: save everything the editor sets under a name, load one back (the lab restarts with it)
	var character_row := HBoxContainer.new()
	box.add_child(character_row)
	_character_option = OptionButton.new()
	_character_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_character_option.tooltip_text = "Load a saved character"
	_character_option.item_selected.connect(_on_character_selected)
	character_row.add_child(_character_option)
	_character_name_edit = LineEdit.new()
	_character_name_edit.placeholder_text = "Character name"
	_character_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_character_name_edit.text = _character_name
	character_row.add_child(_character_name_edit)
	var save_character := Button.new()
	save_character.text = "Save"
	save_character.tooltip_text = "Save the whole character (body, face, skin, eyes, brows, hair, beard) under this name"
	save_character.pressed.connect(func() -> void: _save_character(_character_name_edit.text))
	character_row.add_child(save_character)
	var delete_character := Button.new()
	delete_character.text = "Delete"
	delete_character.tooltip_text = "Delete the saved character with this name"
	delete_character.pressed.connect(_on_delete_character)
	character_row.add_child(delete_character)
	var random_character := Button.new()
	random_character.text = "Random"
	random_character.tooltip_text = "A random character: body, face, skin, eyes, hair and beard (the lab restarts with it)"
	random_character.pressed.connect(_on_random_character)
	character_row.add_child(random_character)
	_fill_character_list()
	# one tab per part of the character, so the list stays short
	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(410.0, 0.0)
	box.add_child(tabs)
	var start_face := _face_mode # (adding the first tab fires tab_changed, which would turn the close-up off)
	tabs.tab_changed.connect(_on_tab_changed.bind(tabs))
	var body_tab := _add_tab(tabs, "Body")
	_add_slider(body_tab, "Height", _on_height_changed, _height)
	_add_slider(body_tab, "Weight", _on_weight_changed, _weight)
	_add_slider(body_tab, "Muscle", _on_muscle_changed, _muscle)
	# one Age for the whole character: it moves the face's age shape, the skin's wrinkles and the grey of the hair and beard (each can still be set on its own after)
	_add_value_slider(body_tab, "Age (whole character: young .. old)", -1.0, 1.0, 0.0, _on_whole_age)
	_add_shape_sliders(body_tab, BODY_SHAPE_SLIDERS)
	_add_section_label(body_tab, "Clothes")
	_add_value_slider(body_tab, "Imperfections (stains, holes, patches)", 0.0, 1.0, float(_cloth_flaws["imperfection"]), func(v: float) -> void:
		_cloth_flaws["imperfection"] = v
		_apply_cloth_flaws())
	_add_value_slider(body_tab, "Wear (faded, dirty hems)", 0.0, 1.0, float(_cloth_flaws["wear"]), func(v: float) -> void:
		_cloth_flaws["wear"] = v
		_apply_cloth_flaws())
	var new_flaws := Button.new()
	new_flaws.text = "New flaws"
	new_flaws.tooltip_text = "Other stains, holes and patches in the same amount"
	new_flaws.pressed.connect(func() -> void:
		_cloth_flaws["seed"] = float(randi() % 10000)
		_apply_cloth_flaws())
	body_tab.add_child(new_flaws)
	var eyes_tab := _add_tab(tabs, "Eyes")
	var eye_row: Control = _add_color_row(eyes_tab, "Eye colour", _eye_color, _on_eye_color_changed)
	var eye_picker: ColorPickerButton = eye_row.get_child(1) as ColorPickerButton
	var eye_swatches := HFlowContainer.new()   # natural iris colours in one click (the picker still sets any colour)
	eyes_tab.add_child(eye_swatches)
	for swatch: Array in EYE_COLOURS:
		var eye_button := Button.new()
		eye_button.text = str(swatch[0])
		eye_button.pressed.connect(func() -> void:
			eye_picker.color = swatch[1]
			_on_eye_color_changed(swatch[1]))
		eye_swatches.add_child(eye_button)
	var different := CheckBox.new()
	different.text = "Different colour per eye"
	different.button_pressed = _different_eyes
	different.toggled.connect(_on_different_eyes_toggled)
	eyes_tab.add_child(different)
	_second_eye_row = _add_color_row(eyes_tab, "Second eye colour", _eye_color_other, _on_eye_color_other_changed)
	_second_eye_row.visible = _different_eyes
	_add_range_slider(eyes_tab, "Iris size", 18.0, 34.0, _iris_deg, _on_iris_changed)
	_add_range_slider(eyes_tab, "Pupil size", 0.15, 0.7, _pupil, _on_pupil_changed)
	_add_range_slider(eyes_tab, "Sclera tint (yellowing)", 0.0, 1.0, _sclera_tint, _on_sclera_changed)
	_add_range_slider(eyes_tab, "Visible veins", 0.0, 1.0, _veins, _on_veins_changed)
	var brows_tab := _add_tab(tabs, "Brows")
	var brow_style_row := HBoxContainer.new()
	brows_tab.add_child(brow_style_row)
	var brow_style_label := Label.new()
	brow_style_label.text = "Brow style"
	brow_style_row.add_child(brow_style_label)
	var brow_style := OptionButton.new()
	brow_style.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for entry: Array in BROW_STYLES:
		brow_style.add_item(str(entry[0]))
		if str(entry[1]) == _face_hair_suffix:
			brow_style.select(brow_style.item_count - 1)
	brow_style.item_selected.connect(_on_brow_style)
	brow_style_row.add_child(brow_style)
	_add_color_row(brows_tab, "Brow and lash colour", _hair_color, _on_hair_color_changed)
	_add_range_slider(brows_tab, "Brow density", 0.2, 1.0, _brow_density, _on_brow_density_changed)
	# head hair (the native HumanHair class): the style and look in one tab, the amount of hair (and its cost) in another
	var hair_tab := _add_tab(tabs, "Hair")
	# the hairstyle: one dropdown (a row of a dozen buttons was confusing), with the reset beside it
	var presets := HBoxContainer.new()
	hair_tab.add_child(presets)
	var style_label := Label.new()
	style_label.text = "Hairstyle"
	presets.add_child(style_label)
	_hair_preset_option = OptionButton.new()
	_hair_preset_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hair_preset_option.item_selected.connect(func(index: int) -> void: _on_hair_preset(_hair_preset_option.get_item_text(index)))
	presets.add_child(_hair_preset_option)
	_fill_hairstyle_dropdown()
	var reset_button := Button.new()
	reset_button.text = "Reset"
	reset_button.tooltip_text = "Reset the hair settings to the body's default style"
	reset_button.pressed.connect(_on_hair_reset)
	presets.add_child(reset_button)
	# your own hairstyles: save what the sliders and zones make under a name (it joins the dropdown), or delete a saved one
	var save_row := HBoxContainer.new()
	hair_tab.add_child(save_row)
	_style_name_edit = LineEdit.new()
	_style_name_edit.placeholder_text = "Name for your hairstyle"
	_style_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_row.add_child(_style_name_edit)
	var save_button := Button.new()
	save_button.text = "Save as..."
	save_button.tooltip_text = "Save the hair settings and zones as your own hairstyle (not the colour)"
	save_button.pressed.connect(func() -> void: _save_current_style(_style_name_edit.text))
	save_row.add_child(save_button)
	_style_delete_button = Button.new()
	_style_delete_button.text = "Delete"
	_style_delete_button.tooltip_text = "Delete the saved hairstyle shown above"
	_style_delete_button.pressed.connect(_on_delete_style)
	save_row.add_child(_style_delete_button)
	# hair zones: the sliders below edit the whole head or one zone (a zone changes only what is moved while it is chosen)
	var zone_row := HBoxContainer.new()
	hair_tab.add_child(zone_row)
	var zone_label := Label.new()
	zone_label.text = "Editing"
	zone_row.add_child(zone_label)
	_zone_option = OptionButton.new()
	_zone_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_zone_option.add_item("Whole head")
	for zone: Array in ZONES:
		_zone_option.add_item(str(zone[1]))
	_zone_option.item_selected.connect(_on_zone_selected)
	zone_row.add_child(_zone_option)
	_zone_reset_button = Button.new()
	_zone_reset_button.text = "Reset zone"
	_zone_reset_button.tooltip_text = "This zone follows the whole head again"
	_zone_reset_button.pressed.connect(_on_zone_reset)
	zone_row.add_child(_zone_reset_button)
	_zone_show_check = CheckBox.new()
	_zone_show_check.text = "Show the zone (tint its hair)"
	_zone_show_check.button_pressed = true
	_zone_show_check.toggled.connect(func(_on: bool) -> void: _refresh_zone_ui())
	hair_tab.add_child(_zone_show_check)
	_add_hair_slider(hair_tab, "Hair amount (in this zone; 0 = no hair)", &"amount", 0.0, 1.0)
	var colour_row := HBoxContainer.new()   # natural colours only (a dropdown of HAIR_COLOURS, no free colour picker)
	hair_tab.add_child(colour_row)
	var colour_label := Label.new()
	colour_label.text = "Hair colour"
	colour_row.add_child(colour_label)
	_hair_colour_option = OptionButton.new()
	_hair_colour_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for swatch: Array in HAIR_COLOURS:
		_hair_colour_option.add_icon_item(_colour_icon(swatch[1]), str(swatch[0]))
	_hair_colour_option.add_item("Custom")   # (a saved character or --hair-colour= with a colour not in the list)
	_hair_colour_option.set_item_disabled(HAIR_COLOURS.size(), true)
	_hair_colour_option.item_selected.connect(func(index: int) -> void:
		if index < HAIR_COLOURS.size():
			_on_head_hair_color_changed(HAIR_COLOURS[index][1]))
	colour_row.add_child(_hair_colour_option)
	_sync_hair_colour_option()
	_hair_grey_slider = _add_value_slider(hair_tab, "Grey hair (salt and pepper)", 0.0, 1.0, _hair_grey, func(v: float) -> void:
		_hair_grey = v
		_head_hair_material.set_shader_parameter(&"hair_grey", v))
	_wet_slider = _add_value_slider(hair_tab, "Wet look (dark, thin sharp highlights)", 0.0, 1.0, _wet, _on_wet_changed)
	_add_hair_slider(hair_tab, "Length", &"length", 0.0, 0.35)
	_add_hair_slider(hair_tab, "Volume", &"volume", 0.0, 2.2)
	_add_hair_slider(hair_tab, "Curl", &"curl", 0.0, 1.0)
	_add_hair_slider(hair_tab, "Fringe (front falls forward)", &"fringe", 0.0, 1.0)
	_add_hair_slider(hair_tab, "Combed back (0 = away from the crown)", &"sweep", 0.0, 1.0)
	_add_hair_slider(hair_tab, "Hugs the head (follows the skull)", &"hug", 0.0, 1.0)
	_add_hair_slider(hair_tab, "Quiff (front lifts and rolls back)", &"quiff", 0.0, 1.0)
	_add_hair_slider(hair_tab, "Swept to one side (away from the parting)", &"swept", 0.0, 1.0)
	_add_hair_slider(hair_tab, "Spikes (stands off the skin)", &"spike", 0.0, 1.0)
	_add_hair_slider(hair_tab, "Parting", &"parting", -1.0, 1.0)
	_add_hair_slider(hair_tab, "Fall (gravity)", &"gravity", 0.0, 2.0)
	_add_hair_slider(hair_tab, "Messy (locks differ and cross)", &"messy", 0.0, 1.0)
	_add_hair_slider(hair_tab, "Wave (a slow wave in every hair)", &"wave", 0.0, 1.0)
	_add_hair_slider(hair_tab, "Clumping (lived-in: hairs gather into locks)", &"clumping", 0.0, 1.0)
	_add_hair_slider(hair_tab, "Gaps (patches without locks, tighter clumps)", &"gaps", 0.0, 1.0)
	_add_hair_slider(hair_tab, "Wisps (long loose wavy hairs)", &"wisps", 0.0, 1.0)
	_add_hair_slider(hair_tab, "Tousle (locks on top lift and arch)", &"tousle", 0.0, 1.0)
	_add_hair_slider(hair_tab, "Longer behind (layers)", &"back_length", 0.0, 1.0)
	_add_hair_slider(hair_tab, "Fringe strips (separate strips with gaps)", &"strips", 0.0, 1.0)
	_add_hair_slider(hair_tab, "Sides and back shorter", &"side_trim", 0.0, 1.0)
	_add_range_slider(hair_tab, "Hair shine", 0.0, 1.0, 0.0, _on_hair_shine_changed)
	var new_seed := Button.new()
	new_seed.text = "New hair (other dice)"
	new_seed.pressed.connect(_on_new_hair_seed)
	hair_tab.add_child(new_seed)
	_add_section_label(hair_tab, "Amount of hair")
	var skin_tab := _add_tab(tabs, "Skin")
	var skin_label := Label.new()
	skin_label.text = "Skin (CC0 MakeHuman textures)"
	skin_tab.add_child(skin_label)
	var skin_buttons := HFlowContainer.new()
	skin_tab.add_child(skin_buttons)
	var flat_button := Button.new()
	flat_button.text = "Flat colour"
	flat_button.pressed.connect(_on_skin_chosen.bind(""))
	skin_buttons.add_child(flat_button)
	for entry: Array in SKIN_FILES:
		var skin_button := Button.new()
		skin_button.text = entry[0]
		skin_button.pressed.connect(_on_skin_chosen.bind(entry[1]))
		skin_buttons.add_child(skin_button)
	_add_section_label(skin_tab, "Skin detail (on any skin)")
	for entry: Array in SKIN_DETAIL:
		var key: StringName = entry[1]
		var start: float = float(_skin_values.get(key, entry[4]))
		if key == &"shave_shadow" and not _skin_shave_set:
			start = 0.75 if _gender == "Male" else 0.0
		_add_skin_slider(skin_tab, str(entry[0]), key, float(entry[2]), float(entry[3]), start)
	_add_section_label(skin_tab, "Makeup")
	for entry: Array in MAKEUP:
		var amount_key: StringName = entry[1]
		_add_skin_slider(skin_tab, str(entry[0]), amount_key, 0.0, 1.0, float(_skin_values.get(amount_key, 0.0)))
		var colour_key: StringName = entry[2]
		if colour_key != &"":
			var start_colour: Color = _skin_values.get(colour_key, entry[3])
			_add_color_row(skin_tab, str(entry[0]) + " colour", start_colour, func(c: Color) -> void:
				_skin_values[colour_key] = c
				_material.set_shader_parameter(colour_key, c))
	var zones_check := CheckBox.new()
	zones_check.text = "Show the skin zones (debug colours)"
	zones_check.button_pressed = int(_skin_values.get(&"skin_debug", 0)) != 0
	zones_check.toggled.connect(func(on: bool) -> void: _material.set_shader_parameter(&"skin_debug", 1 if on else 0))
	skin_tab.add_child(zones_check)
	var face_tab := _add_tab(tabs, "Face")
	var face_buttons := HBoxContainer.new()
	face_tab.add_child(face_buttons)
	var random_face := Button.new()
	random_face.text = "Random face"
	random_face.tooltip_text = "A new random face (every face slider, mostly small changes)"
	random_face.pressed.connect(_on_random_face)
	face_buttons.add_child(random_face)
	var reset_face := Button.new()
	reset_face.text = "Reset face"
	reset_face.pressed.connect(_on_reset_face)
	face_buttons.add_child(reset_face)
	_add_shape_sliders(face_tab, FACE_SLIDERS)
	var beard_tab := _add_tab(tabs, "Beard")
	_beard_tab = beard_tab   # (a tab of its own; the colour of the beard is the hair colour)
	_add_hair_slider(beard_tab, "Beard length", &"beard_length", 0.0, 0.1)   # (the first row; 0 is shaved)
	var beard_styles := HFlowContainer.new()
	beard_tab.add_child(beard_styles)
	for style_entry: Array in BEARD_STYLES:
		var style_button := Button.new()
		style_button.text = style_entry[0]
		style_button.pressed.connect(_on_beard_style.bind(style_entry))
		beard_styles.add_child(style_button)
	_beard_grey_slider = _add_value_slider(beard_tab, "Greying (grey locks)", 0.0, 1.0, _beard_grey, func(v: float) -> void:
		_beard_grey = v
		_head_hair_material.set_shader_parameter(&"beard_grey", v))
	_add_value_slider(beard_tab, "Ginger locks", 0.0, 1.0, _beard_ginger, func(v: float) -> void:
		_beard_ginger = v
		_head_hair_material.set_shader_parameter(&"beard_ginger", v))
	_add_hair_slider(beard_tab, "Beard curl (0 straight .. 1 tight curls)", &"beard_curl", 0.0, 1.0)
	_add_hair_slider(beard_tab, "Neck beard (under the jaw)", &"neck_beard", 0.0, 1.0)
	var beard_follicle_check := CheckBox.new()
	beard_follicle_check.text = "Debug: show beard follicles (hair roots), hide hair"
	beard_follicle_check.button_pressed = _beard_follicles_shown
	beard_follicle_check.toggled.connect(_on_beard_follicles_toggled)
	beard_tab.add_child(beard_follicle_check)
	var beard_area_check := CheckBox.new()
	beard_area_check.text = "Debug: mark the beard area (regions)"
	beard_area_check.button_pressed = _beard_area_shown
	beard_area_check.toggled.connect(func(pressed: bool) -> void:
		_beard_area_shown = pressed
		_update_beard_area())
	beard_tab.add_child(beard_area_check)
	_add_section_label(beard_tab, "Body hair")
	for row: Array in [["Body hair amount (0 = none)", "amount"], ["Chest", "chest"], ["Belly line", "belly"], ["Back", "back"], ["Arms", "arms"], ["Legs", "legs"], ["Armpits", "armpits"], ["Body hair curl", "curl"]]:
		var key: String = row[1]
		_add_value_slider(beard_tab, row[0], 0.0, 1.0, float(_body_hair[key]), func(v: float) -> void:
			_body_hair[key] = v
			_body_hair_dirty_ms = Time.get_ticks_msec())
	_add_value_slider(beard_tab, "Body hair length (mm)", 3.0, 40.0, float(_body_hair["length"]) * 1000.0, func(v: float) -> void:
		_body_hair["length"] = v / 1000.0
		_body_hair_dirty_ms = Time.get_ticks_msec())
	var amount_tab: Control = hair_tab
	_add_hair_slider(amount_tab, "Guide locks (how many places hair grows from)", &"locks", 200.0, 6000.0)
	_add_hair_slider(amount_tab, "Individual hairs per lock (0 = ribbons)", &"strands", 0.0, 96.0)
	_add_hair_slider(amount_tab, "Points per hair (0 = auto; fewer = cheaper)", &"points", 0.0, 16.0)
	_add_hair_slider(amount_tab, "Hair spread (clump)", &"clump", 0.0, 0.02)
	_add_hair_slider(amount_tab, "Hair thickness (metres; real hair is 0.00007)", &"strand_width", 0.00005, 0.003)
	_add_range_slider(amount_tab, "Hair density", 0.3, 1.0, _head_hair_density, _on_head_hair_density_changed)
	_add_section_label(hair_tab, "Motion")
	var motion_tab: Control = hair_tab
	_add_range_slider(motion_tab, "Wind", 0.0, 0.08, _wind, _on_wind_changed)
	_add_range_slider(motion_tab, "Hair weight (1 = normal)", 0.5, 2.0, _hair_weight, _on_hair_weight_changed)
	_add_range_slider(motion_tab, "Friction on small movements", 0.0, 0.5, _hair_friction, _on_hair_friction_changed)
	_add_range_slider(motion_tab, "Bending stiffness (keeps its shape)", 0.0, 1.0, _hair_bend, _on_hair_bend_changed)
	_add_range_slider(motion_tab, "Local shape (curve holds along the strand)", 0.0, 1.0, _hair_local, _on_hair_local_changed)
	var extras_check := CheckBox.new()
	extras_check.text = "Extra locks at hairline, part, crown (fills gaps, uneven)"
	extras_check.button_pressed = float(_hair_style["extras"]) > 0.5
	extras_check.toggled.connect(func(pressed: bool) -> void:
		_hair_style["extras"] = 1.0 if pressed else 0.0
		_hair_last_change_ms = Time.get_ticks_msec()
		_hair_dirty = true)
	hair_tab.add_child(extras_check)
	var follicle_check := CheckBox.new()
	follicle_check.text = "Show follicles (hair roots), hide hair"
	follicle_check.button_pressed = _show_follicles
	follicle_check.toggled.connect(_on_follicles_toggled)
	hair_tab.add_child(follicle_check)
	var scalp_debug_check := CheckBox.new()
	scalp_debug_check.text = "Debug: scalp regions and growth direction (arrows)"
	scalp_debug_check.button_pressed = _scalp_debug_shown
	scalp_debug_check.toggled.connect(func(pressed: bool) -> void:
		_scalp_debug_shown = pressed
		_update_scalp_debug())
	hair_tab.add_child(scalp_debug_check)
	_add_range_slider(hair_tab, "Crown patch under the hair (0 = none)", 0.0, 1.0, _scalp_layer, _on_scalp_layer_changed)
	_add_range_slider(motion_tab, "Max swing (share of the length)", 0.05, 1.5, _hair_max_swing, _on_hair_max_swing_changed)
	_add_range_slider(motion_tab, "Tip stiffness (springiness)", 0.0, 0.5, _hair_tip, _on_hair_tip_changed)
	_add_range_slider(motion_tab, "Air drag (swing slows down)", 0.0, 0.6, _hair_air, _on_hair_air_changed)
	_add_range_slider(motion_tab, "Strand damping (stops wobble)", 0.0, 1.0, _hair_strand_damp, _on_hair_strand_damp_changed)
	_add_range_slider(motion_tab, "Root stiffness (less swing near the head)", 0.1, 0.9, _hair_root_stiffness, _on_hair_root_stiffness_changed)
	var shake := Button.new()
	shake.text = "Shake head (swing the hair)"
	shake.pressed.connect(_on_shake_pressed)
	motion_tab.add_child(shake)
	for i in tabs.get_child_count():
		if tabs.get_child(i).name == _start_tab:
			tabs.current_tab = i
	if start_face and _start_tab == "":
		tabs.current_tab = 1 # --face: start on the Eyes tab (the close-up follows the tab)
	_readout = Label.new()
	box.add_child(_readout)


func _add_section_label(parent: Control, text: String) -> void:
	parent.add_child(HSeparator.new())
	var label := Label.new()
	label.text = text
	label.add_theme_color_override(&"font_color", Color(0.75, 0.85, 1.0))
	parent.add_child(label)


# The panel's spacing: margins round the panel and inside the tabs, gaps between rows and buttons, a little more room above each label
# (so a label sits with the slider under it, apart from the one above).
func _panel_theme() -> Theme:
	var base: Theme = ThemeDB.get_default_theme()
	var theme := Theme.new()
	var panel_box := base.get_stylebox(&"panel", &"PanelContainer").duplicate() as StyleBox
	panel_box.set_content_margin_all(14.0)
	theme.set_stylebox(&"panel", &"PanelContainer", panel_box)
	var tab_box := base.get_stylebox(&"panel", &"TabContainer").duplicate() as StyleBox
	tab_box.set_content_margin_all(12.0)
	theme.set_stylebox(&"panel", &"TabContainer", tab_box)
	theme.set_constant(&"separation", &"VBoxContainer", 6)
	theme.set_constant(&"separation", &"HBoxContainer", 8)
	theme.set_constant(&"h_separation", &"HFlowContainer", 6)
	theme.set_constant(&"v_separation", &"HFlowContainer", 6)
	theme.set_constant(&"h_separation", &"GridContainer", 8)
	theme.set_constant(&"v_separation", &"GridContainer", 6)
	var label_box := StyleBoxEmpty.new()
	label_box.content_margin_top = 4.0
	theme.set_stylebox(&"normal", &"Label", label_box)
	return theme


func _add_tab(tabs: TabContainer, tab_name: String) -> VBoxContainer:
	var page := VBoxContainer.new()
	page.name = tab_name
	tabs.add_child(page)
	return page


func _add_slider(parent: Control, label_text: String, callback: Callable, start: float = 0.0) -> void:
	var label := Label.new()
	label.text = label_text
	parent.add_child(label)
	var slider := HSlider.new()
	slider.scrollable = false
	slider.min_value = -1.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = start
	slider.name = label_text
	slider.value_changed.connect(callback)
	parent.add_child(slider)


var _hair_preset_option: OptionButton = null   # the Hair tab's hairstyle dropdown
var _hair_preset_name: String = "Dapper"   # the style last picked (shown in the dropdown; the start style and --hair-preset are set before the panel exists)
# Hair zones: the scalp's named zones, each able to change the shape settings below and a hair amount (the native builder blends them over ~1.5 cm at a border).
# [key the builder reads, name shown]; the order is the zone index (the shader's zone_tint)
const ZONES: Array = [["front", "Front"], ["top", "Top"], ["crown", "Crown"], ["left_side", "Left side"], ["right_side", "Right side"], ["back", "Back"], ["nape", "Nape"]]
const ZONE_KEYS: Array[StringName] = [&"length", &"volume", &"curl", &"wave", &"clumping", &"fringe", &"sweep", &"hug", &"quiff", &"swept", &"spike", &"gravity", &"messy", &"gaps", &"wisps", &"tousle", &"amount"]
const HEAD_ONLY_KEYS: Array[StringName] = [&"parting", &"side_trim", &"back_length", &"strips"]   # Hair-tab sliders that only make sense for the whole head (disabled while a zone is edited)
var _hair_zones: Dictionary = {}          # zone key -> {setting: value}: what each zone changes (only the settings it changes)
var _hair_zone_edit: String = ""          # the zone the Hair sliders edit ("" = the whole head)
var _hair_zone_arg: String = ""           # --hair-zone=zone:key:value,...
var _zone_edit_arg: String = ""           # --zone-edit=zone
var _zone_option: OptionButton = null
var _zone_reset_button: Button = null
var _zone_show_check: CheckBox = null
# saved custom hairstyles (HairStyleStore): listed in the Hairstyle dropdown after the built-in ones
var _styles_dir: String = "user://hair_styles"   # (--styles-dir= for tests: they must not write the user's own styles)
var _pending_saved_style: String = ""            # --hair-preset=<a saved style>: applied once the store can be read
var _save_style_arg: String = ""                 # --save-style=<name>: save the style the flags made (captures, checks)
var _saved_zones: Dictionary = {}                # (the zones of the saved style being applied)
var _style_name_edit: LineEdit = null
var _style_delete_button: Button = null
const DEFAULT_STYLE: Dictionary = {"Male": "Dapper", "Female": "Long waves"}   # the style a body starts with when its button is pressed


func _on_gender_button(gender_name: String) -> void:
	var t0 := Time.get_ticks_usec()
	_set_gender(gender_name)
	var t1 := Time.get_ticks_usec()
	_update_beard_enabled()
	if DEFAULT_STYLE.has(gender_name) and gender_name != _style_gender:
		_style_gender = gender_name
		_on_hair_preset(DEFAULT_STYLE[gender_name])
	print("GENDER_SWITCH to %s: set_gender %.0f ms, beard + preset %.0f ms" % [gender_name, (t1 - t0) / 1000.0, (Time.get_ticks_usec() - t1) / 1000.0])
	_switch_watch_until_ms = Time.get_ticks_msec() + 10000


# The female body has no beard: the Beard tab's controls are disabled (and the debug views off), and the hair is built with beard 0.
func _update_beard_enabled() -> void:
	var female: bool = _gender == "Female"
	if female:
		_hair_style[&"beard"] = 0.0
		_beard_follicles_shown = false
		_beard_area_shown = false
		_update_beard_follicles()
		_update_beard_area()
	if _beard_tab != null:
		_set_disabled_deep(_beard_tab, female)


func _set_disabled_deep(node: Node, disabled: bool) -> void:
	if node is BaseButton:
		(node as BaseButton).disabled = disabled
		if disabled and node is CheckBox:
			(node as CheckBox).button_pressed = false
	elif node is Range:
		(node as Range).editable = not disabled
	for child in node.get_children():
		_set_disabled_deep(child, disabled)


func _set_gender(gender_name: String) -> void:
	var lap: Array = [Time.get_ticks_usec()]   # (in an array: a lambda cannot assign a captured local)
	var laps: PackedStringArray = []
	var mark := func(what: String) -> void:
		var now := Time.get_ticks_usec()
		laps.append("%s %.0f" % [what, (now - int(lap[0])) / 1000.0])
		lap[0] = now
	_gender = gender_name
	_stop_cloth()   # Clear references before the previous body frees its skeleton and garments.
	if _body != null:
		_body.queue_free()
	var packed: PackedScene = load(BODY_SCENES[gender_name])
	_body = packed.instantiate() as Node3D
	add_child(_body)
	_hair_sway.target = _body
	_mesh = _find_mesh(_body)
	_mesh.material_override = _material
	mark.call("body")
	_set_face_frame(_mesh.mesh)
	mark.call("face_frame")
	if not _skin_shave_set:
		var shave: float = 0.75 if gender_name == "Male" else 0.0   # (a shaved man's jaw is darker; the slider takes over once moved)
		_material.set_shader_parameter(&"shave_shadow", shave)
		if _skin_sliders.has(&"shave_shadow"):
			(_skin_sliders[&"shave_shadow"] as HSlider).set_value_no_signal(shave)
	# The underwear has the same blend shapes as the body, so the same weights fit it.
	var underwear_packed: PackedScene = load(UNDERWEAR_SCENES[gender_name])
	var underwear: Node3D = underwear_packed.instantiate() as Node3D
	_body.add_child(underwear)
	_underwear_mesh = _find_mesh(underwear)
	_underwear_mesh.material_override = _cloth_material
	_load_clothes()
	# The eyes too: two spheres that move with the head under the same shape weights.
	var eyes_packed: PackedScene = load(EYE_SCENES[gender_name])
	var eyes: Node3D = eyes_packed.instantiate() as Node3D
	_body.add_child(eyes)
	_eyes_mesh = _find_mesh(eyes)
	_eyes_mesh.material_override = _eye_material
	if _mh_hair != "":
		var pieces: PackedStringArray = _mh_hair.split(":")
		var shell: Node3D = (load("res://assets/models/humans/mh_hair/%s_%s.glb" % [gender_name.to_lower(), pieces[0]]) as PackedScene).instantiate() as Node3D
		_body.add_child(shell)
		var shell_mesh: MeshInstance3D = _find_mesh(shell)
		var shell_material := StandardMaterial3D.new()
		shell_material.albedo_texture = load("res://assets/models/humans/mh_hair/" + pieces[1]) as Texture2D
		shell_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		shell_material.alpha_scissor_threshold = 0.5
		shell_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		shell_material.roughness = 0.8
		shell_mesh.material_override = shell_material
	mark.call("underwear+eyes")
	_load_face_hair()
	mark.call("face_hair")
	_hair_mesh = null
	_hair_dirty = true   # (if a build for the old body is still running, this one starts when it is done)
	_rebuild_hair()
	mark.call("hair")
	_body_hair_mesh = null   # (went with the old body)
	_rebuild_body_hair()
	mark.call("body_hair")
	_apply()
	mark.call("apply")
	if _switch_gender_arg != "":
		print("GENDER_SWITCH steps ms: ", ", ".join(laps))
	for button: Node in get_tree().get_nodes_in_group(&"gender_buttons"):
		(button as Button).button_pressed = button.name == gender_name
	_body.rotation.y = _yaw


# Brows and lashes: hair cards bound to the face, same shape names again. The brow style is the file (BROW_STYLES); a new style swaps only these two.
func _load_face_hair() -> void:
	for old: MeshInstance3D in [_brows_mesh, _lashes_mesh]:
		if old != null and is_instance_valid(old):
			# free the old brows / lashes (their glb root under the body). Only when they hang under the CURRENT body: after a gender switch _body is already
			# the new body, the old ones go with the old body, and walking up looking for _body went past the top and freed the scene's root window (the lab froze or crashed)
			var root: Node = old
			while root != null and root.get_parent() != _body:
				root = root.get_parent()
			if root != null:
				root.queue_free()
	var base_path: String = "res://assets/models/humans/%s_" % _gender.to_lower()
	var brows: Node3D = (load(base_path + "brows" + _face_hair_suffix + ".glb") as PackedScene).instantiate() as Node3D
	_body.add_child(brows)
	_brows_mesh = _find_mesh(brows)
	_brows_mesh.material_override = _brow_material
	var lashes: Node3D = (load(base_path + "lashes" + ("_mf" if _face_hair_suffix != "" else "") + ".glb") as PackedScene).instantiate() as Node3D
	_body.add_child(lashes)
	_lashes_mesh = _find_mesh(lashes)
	_lashes_mesh.material_override = _lash_material


func _on_brow_style(index: int) -> void:
	_face_hair_suffix = str(BROW_STYLES[index][1])
	if _body == null:
		return
	_load_face_hair()
	_apply_face_shapes()   # (the new meshes start with no blend shapes set)
	_apply()


func _find_mesh(root: Node) -> MeshInstance3D:
	if root is MeshInstance3D:
		return root as MeshInstance3D
	for child: Node in root.get_children():
		var found: MeshInstance3D = _find_mesh(child)
		if found != null:
			return found
	return null


func _on_height_changed(value: float) -> void:
	_height = value
	_apply()


func _add_color_row(parent: Control, label_text: String, color: Color, callback: Callable) -> Control:
	var row := VBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	row.add_child(label)
	var picker := ColorPickerButton.new()
	picker.color = color
	picker.custom_minimum_size = Vector2(0.0, 28.0)
	picker.color_changed.connect(callback)
	row.add_child(picker)
	return row


func _add_range_slider(parent: Control, label_text: String, low: float, high: float, value: float, callback: Callable) -> void:
	var label := Label.new()
	label.text = label_text
	parent.add_child(label)
	var slider := HSlider.new()
	slider.scrollable = false
	slider.min_value = low
	slider.max_value = high
	slider.step = (high - low) / 100.0
	slider.value = value
	slider.value_changed.connect(callback)
	parent.add_child(slider)


func _apply_eye_parameters() -> void:
	_eye_material.set_shader_parameter(&"iris_color", _eye_color)
	_eye_material.set_shader_parameter(&"iris_color_other", _eye_color_other)
	_eye_material.set_shader_parameter(&"different_eyes", _different_eyes)
	_eye_material.set_shader_parameter(&"iris_radius_deg", _iris_deg)
	_eye_material.set_shader_parameter(&"pupil_size", _pupil)
	_eye_material.set_shader_parameter(&"sclera_tint", _sclera_tint)
	_eye_material.set_shader_parameter(&"vein_amount", _veins)


func _apply_hair_parameters() -> void:
	for material: ShaderMaterial in [_brow_material, _lash_material]:
		material.set_shader_parameter(&"hair_color", _hair_color)
	_brow_material.set_shader_parameter(&"brow_density", _brow_density)


# The Eyes, Brows, Hair and Beard tabs are about the head: the camera goes to the face; the other tabs show the whole body.
func _on_tab_changed(index: int, tabs: TabContainer) -> void:
	var tab_name: String = tabs.get_child(index).name
	var wants_face: bool = tab_name in ["Eyes", "Brows", "Hair", "Beard", "Face"]
	# Eyes and Brows keep the tight framing; Hair stands back a little and looks higher so the whole head of hair is in the picture
	var wants_hair: bool = tab_name == "Hair"
	_beard_view = tab_name == "Beard"
	if wants_face != _face_mode:
		_face_hair = wants_hair
		_on_face_toggled(wants_face)
	elif wants_face:
		_face_hair = wants_hair
		_distance = FACE_DISTANCE_BEARD if _beard_view else (FACE_DISTANCE_HAIR if wants_hair else FACE_DISTANCE)
		_apply()
		_update_camera()


func _on_face_toggled(pressed: bool) -> void:
	_face_mode = pressed
	if pressed:
		_distance = FACE_DISTANCE_BEARD if _beard_view else (FACE_DISTANCE_HAIR if _face_hair else FACE_DISTANCE)
	else:
		_distance = 3.6
		_cam_y = 1.0
		_look_y = 0.95
	_apply()
	_update_camera()


func _add_hair_slider(parent: Control, label_text: String, key: StringName, low: float, high: float) -> void:
	var label := Label.new()
	label.text = label_text
	parent.add_child(label)
	var slider := HSlider.new()
	slider.scrollable = false
	slider.min_value = low
	slider.max_value = high
	slider.step = 0.0005 if key == &"beard_length" else (high - low) / 100.0
	slider.value = float(_hair_style[key])
	slider.value_changed.connect(_on_hair_param.bind(key))
	parent.add_child(slider)
	_hair_sliders[key] = slider
	_hair_slider_labels[key] = [label, label_text]
	_show_slider_value(key)


func _show_slider_value(key: StringName) -> void:
	var entry: Array = _hair_slider_labels[key]
	var value: float = (_hair_sliders[key] as HSlider).value
	var shown: String = "%.5f" % value if absf(value) < 0.01 and value != 0.0 else "%.3f" % value
	var text: String = "%s: %s" % [entry[1], shown]
	if _hair_zone_edit != "" and key in ZONE_KEYS and not (_hair_zones.get(_hair_zone_edit, {}) as Dictionary).has(key):
		text += " (head)"   # (this zone does not change it: the whole head's value)
	if key == &"beard_length":
		text = "%s: %.2f cm" % [entry[1], value * 100.0]   # (centimetres)
	if (entry[0] as Label).text != text:
		(entry[0] as Label).text = text


func _on_hair_param(value: float, key: StringName) -> void:
	if _hair_zone_edit != "" and key in ZONE_KEYS:
		if not _hair_zones.has(_hair_zone_edit):
			_hair_zones[_hair_zone_edit] = {}
		(_hair_zones[_hair_zone_edit] as Dictionary)[key] = value   # (the zone's own value from now on)
	else:
		_hair_style[key] = value
	_show_slider_value(key)
	_hair_retry = 0
	_hair_last_change_ms = Time.get_ticks_msec()
	_beard_only_change = key in [&"beard_length", &"beard_curl", &"neck_beard", &"beard"]
	_hair_dirty = true


# Every hair slider (and the style of the current body) back to what the lab starts with.
func _on_hair_reset() -> void:
	_hair_style = _hair_defaults.duplicate()
	_on_hair_preset(DEFAULT_STYLE.get(_gender, "Dapper"))
	for key: StringName in _hair_sliders:
		if _hair_style.has(key):
			(_hair_sliders[key] as HSlider).set_value_no_signal(float(_hair_style[key]))
		_show_slider_value(key)
	_hair_retry = 0
	_hair_dirty = true


func _on_hair_preset(preset_name: String) -> void:
	_beard_only_change = false
	_hair_preset_name = preset_name
	_hair_zones.clear()   # (a hairstyle is a whole-head style: picking one drops the zone changes)
	_hair_zone_edit = ""
	if _hair_preset_option != null:
		# the dropdown shows the style however it was chosen (the dropdown, a body button, Reset, --hair-preset)
		for index: int in _hair_preset_option.item_count:
			if not _hair_preset_option.is_item_separator(index) and _hair_preset_option.get_item_text(index) == preset_name:
				_hair_preset_option.select(index)
	var preset: Dictionary = HAIR_PRESETS.get(preset_name, {})
	_saved_zones = {}
	if not HAIR_PRESETS.has(preset_name):
		# a saved hairstyle: its settings (as a preset names them), its zones and its wet look
		var saved: Dictionary = HairStyleStore.load_style(_styles_dir, preset_name)
		if saved.is_empty():
			return
		preset = (saved["style"] as Dictionary).duplicate()
		preset[&"wet"] = float(saved["wet"])
		_saved_zones = saved["zones"]
	for reset_key: StringName in [&"quiff", &"swept", &"spike", &"hug", &"sweep", &"strands", &"points", &"messy", &"wave", &"gaps", &"wisps", &"strips", &"back_length", &"tousle"]:   # what a preset does not name goes back to off
		if not preset.has(reset_key):
			_hair_style[reset_key] = 0.0
			if _hair_sliders.has(reset_key):
				(_hair_sliders[reset_key] as HSlider).set_value_no_signal(0.0)
	for key: StringName in preset:
		_hair_style[key] = preset[key]
		if _hair_sliders.has(key):
			(_hair_sliders[key] as HSlider).set_value_no_signal(float(preset[key]))
	# (a hairstyle never changes the hair colour: the colour is the swatches' alone)
	var new_target: int = int(preset.get(&"target_hairs", DEFAULT_TARGET_HAIRS))
	_strand_scale = clampf(_strand_scale * float(new_target) / float(_target_hairs), 0.08, 3.0)   # (keep what the lab learned about hairs per lock: only the target changes. Resetting it to a guess built 600,000 hairs, more than the simulation can handle, and the head came out bald)
	_target_hairs = new_target
	_hair_style[&"wet"] = float(preset.get(&"wet", 0.0))
	_scalp_layer = float(preset.get(&"scalp_layer", 1.0))   # (a solid hair-coloured layer under the hair: wet, swept hair leaves bare patches that the skin tint does not cover)
	_head_hair_material.set_shader_parameter(&"scalp_layer", _scalp_layer)
	_wet = float(preset.get(&"wet", 0.0))   # (a preset with a wet look sets it; every other preset dries the hair)
	_head_hair_material.set_shader_parameter(&"wet", _wet)
	_head_hair_material.set_shader_parameter(&"shine", float(preset.get(&"shine", 0.25)))   # (a preset can ask for a glossier look; the others go back to the default)
	if _wet_slider != null:
		_wet_slider.set_value_no_signal(_wet)
	_hair_zones = _saved_zones.duplicate(true)   # (a saved style brings its zones; a built-in one has none)
	if _style_delete_button != null:
		_style_delete_button.disabled = HAIR_PRESETS.has(preset_name)
	_refresh_zone_ui()
	_hair_dirty = true


# The Hairstyle dropdown: the built-in styles, then the saved ones; the current style is selected.
func _fill_hairstyle_dropdown() -> void:
	if _hair_preset_option == null:
		return
	_hair_preset_option.clear()
	for preset_name: String in HAIR_PRESETS:
		_hair_preset_option.add_item(preset_name)
	var saved: PackedStringArray = HairStyleStore.list_styles(_styles_dir)
	if not saved.is_empty():
		_hair_preset_option.add_separator("Your hairstyles")
		for saved_name: String in saved:
			_hair_preset_option.add_item(saved_name)
	for index: int in _hair_preset_option.item_count:
		if not _hair_preset_option.is_item_separator(index) and _hair_preset_option.get_item_text(index) == _hair_preset_name:
			_hair_preset_option.select(index)
	if _style_delete_button != null:
		_style_delete_button.disabled = HAIR_PRESETS.has(_hair_preset_name)


# Saves the whole-head settings (with the hair count target, shine and scalp layer the style was made with), the zones and the wet look. Never the colour.
func _save_current_style(style_name: String) -> void:
	var clean: String = HairStyleStore.clean_name(style_name)
	if clean.is_empty() or HAIR_PRESETS.has(clean):
		return   # (no name, or a built-in style's name)
	var style: Dictionary = _hair_style.duplicate()
	for key: StringName in style.keys():
		if str(key).begins_with("beard") or key == &"neck_beard":
			style.erase(key)   # (the beard is not part of a hairstyle: loading one keeps the beard as it is)
	style[&"target_hairs"] = _target_hairs
	style[&"scalp_layer"] = _scalp_layer
	var shine: Variant = _head_hair_material.get_shader_parameter(&"shine")
	style[&"shine"] = float(shine) if shine != null else 0.25   # (unset until a style sets it: the shader default)
	if HairStyleStore.save_style(_styles_dir, clean, style, _hair_zones, _wet) == OK:
		_hair_preset_name = clean
		_fill_hairstyle_dropdown()
		print("HUMAN_LAB saved hairstyle ", clean, " in ", _styles_dir)


func _on_delete_style() -> void:
	if HAIR_PRESETS.has(_hair_preset_name):
		return
	HairStyleStore.delete_style(_styles_dir, _hair_preset_name)
	_on_hair_preset(DEFAULT_STYLE.get(_gender, "Dapper"))
	_fill_hairstyle_dropdown()


func _on_zone_selected(index: int) -> void:
	_hair_zone_edit = "" if index == 0 else str(ZONES[index - 1][0])
	_refresh_zone_ui()


func _on_zone_reset() -> void:
	_hair_zones.erase(_hair_zone_edit)
	_refresh_zone_ui()
	_hair_retry = 0
	_hair_dirty = true


# The Hair sliders show the zone being edited (its own values, or the whole head's marked "(head)"), the controls that only fit the whole head are disabled
# while a zone is edited, and the zone's hair is tinted.
func _refresh_zone_ui() -> void:
	if _zone_option == null:
		return
	var zone_index: int = -1
	for i: int in ZONES.size():
		if str(ZONES[i][0]) == _hair_zone_edit:
			zone_index = i
	_zone_option.select(zone_index + 1)
	_zone_reset_button.disabled = _hair_zone_edit == ""
	var overrides: Dictionary = _hair_zones.get(_hair_zone_edit, {})
	for key: StringName in _hair_sliders:
		var slider := _hair_sliders[key] as HSlider
		if _hair_zone_edit != "" and key in ZONE_KEYS:
			slider.set_value_no_signal(float(overrides.get(key, _hair_style.get(key, 1.0))))
		elif _hair_style.has(key):
			slider.set_value_no_signal(float(_hair_style[key]))
		slider.editable = not (_hair_zone_edit != "" and key in HEAD_ONLY_KEYS)
		_show_slider_value(key)
	if _hair_sliders.has(&"amount"):
		(_hair_sliders[&"amount"] as HSlider).visible = _hair_zone_edit != ""
		((_hair_slider_labels[&"amount"] as Array)[0] as Label).visible = _hair_zone_edit != ""
	if _wet_slider != null:
		_wet_slider.editable = _hair_zone_edit == ""
	_head_hair_material.set_shader_parameter(&"zone_tint", zone_index if _zone_show_check.button_pressed else -1)


func _on_tip_color_changed(color: Color) -> void:
	_tip_color = color
	_head_hair_material.set_shader_parameter(&"tip_color", color)


func _on_tip_mix_changed(value: float) -> void:
	_tip_mix = value
	_head_hair_material.set_shader_parameter(&"tip_mix", value)


func _on_hair_shine_changed(value: float) -> void:
	_head_hair_material.set_shader_parameter(&"shine", value)


# The wind pushes the simulated hair (so the head stops it); without the simulation it is the old vertex-shader bend.
func _apply_wind() -> void:
	var direction := Vector3(1.0, 0.0, 0.35)
	if _sim_enabled and _sim != null and _hair_mesh != null:
		_sim.wind = direction * _wind * 100.0   # 0.08 -> about 8 m/s2, near gravity
		_head_hair_material.set_shader_parameter(&"wind", Vector3.ZERO)
	else:
		_head_hair_material.set_shader_parameter(&"wind", direction * _wind)


func _on_hair_max_swing_changed(value: float) -> void:
	_hair_max_swing = value
	if _sim != null:
		_sim.max_swing = value


func _on_hair_tip_changed(value: float) -> void:
	_hair_tip = value
	if _sim != null:
		_sim.tip_stiffness = value


func _on_hair_air_changed(value: float) -> void:
	_hair_air = value
	if _sim != null:
		_sim.air_drag = value


func _on_hair_strand_damp_changed(value: float) -> void:
	_hair_strand_damp = value
	if _sim != null:
		_sim.strand_damping = value


func _on_hair_local_changed(value: float) -> void:
	_hair_local = value
	if _sim != null:
		_sim.local_stiffness = value


func _on_hair_bend_changed(value: float) -> void:
	_hair_bend = value
	if _sim != null:
		_sim.bend_stiffness = value


func _on_hair_root_stiffness_changed(value: float) -> void:
	_hair_root_stiffness = value
	if _sim != null:
		_sim.root_stiffness = value


func _on_hair_friction_changed(value: float) -> void:
	_hair_friction = value
	if _sim != null:
		_sim.calm_damping = 1.0 - value


func _on_hair_weight_changed(value: float) -> void:
	_hair_weight = value
	if _sim != null:
		_sim.weight = value


func _on_wind_changed(value: float) -> void:
	_wind = value
	# the wind blows from the character's right, a little from the front, in the body's own space
	_apply_wind()


func _on_shake_pressed() -> void:
	_hair_sway.kick(Vector3(0.9 * _shake_side, 0.25, 0.5))
	_shake_side = -_shake_side




func _on_new_hair_seed() -> void:
	_hair_style[&"seed"] = int(_hair_style[&"seed"]) + 1
	_hair_dirty = true


func _on_follicles_toggled(pressed: bool) -> void:
	_show_follicles = pressed
	_update_follicles()


# The guide strands' roots (the first point of every guide: where a lock grows from) as small dots; the hair itself is hidden while they show.
func _update_follicles() -> void:
	if _follicle_node != null:
		_follicle_node.queue_free()
		_follicle_node = null
	if _hair_mesh != null:
		_hair_mesh.visible = not (_show_follicles or _beard_follicles_shown or _scalp_debug_shown)
	if not _show_follicles or _hair_mesh == null or not (_hair_mesh.mesh is ArrayMesh):
		return
	var mesh := _hair_mesh.mesh as ArrayMesh
	var guides: PackedVector3Array = mesh.get_meta(&"hair_guides", PackedVector3Array())
	var steps: int = int(mesh.get_meta(&"hair_guide_steps", 1))
	var count: int = int(mesh.get_meta(&"hair_guide_count", 0))
	if count == 0:
		return
	var dot := SphereMesh.new()
	dot.radius = 0.0016
	dot.height = 0.0032
	dot.radial_segments = 6
	dot.rings = 3
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.05, 0.9, 1.0)
	dot.material = material
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = dot
	multi.instance_count = count
	for g in count:
		multi.set_instance_transform(g, Transform3D(Basis(), guides[g * steps]))
	_follicle_node = MultiMeshInstance3D.new()
	_follicle_node.multimesh = multi
	_body.add_child(_follicle_node)
	_hair_info = "Follicles: %s (the roots of the guide strands)" % _thousands(count)
	_apply()


# The skin triangles the beard grows on (HumanHair keeps them as the mesh meta "hair_beard_area"), as a translucent green layer just above the skin; the hair stays visible.
func _update_beard_area() -> void:
	if _beard_area_node != null:
		_beard_area_node.queue_free()
		_beard_area_node = null
	if not _beard_area_shown or _hair_mesh == null or not (_hair_mesh.mesh is ArrayMesh):
		return
	var points: PackedVector3Array = (_hair_mesh.mesh as ArrayMesh).get_meta(&"hair_beard_area", PackedVector3Array())
	if points.is_empty():
		return
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_COLOR] = (_hair_mesh.mesh as ArrayMesh).get_meta(&"hair_beard_area_colors", PackedColorArray())
	var area_mesh := ArrayMesh.new()
	area_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	area_mesh.surface_set_material(0, material)
	_beard_area_node = MeshInstance3D.new()
	_beard_area_node.mesh = area_mesh
	_body.add_child(_beard_area_node)


# Scalp regions after the reference chart, from the guide roots (dots, coloured) and the growth direction of every guide (an arrow along its first segment). The regions are
# worked out from where a root is in the head's own box (front/back, height, side), so they follow the head size; the hair is hidden while this shows.
func _update_scalp_debug() -> void:
	if _scalp_debug_node != null:
		_scalp_debug_node.queue_free()
		_scalp_debug_node = null
	if _hair_mesh != null:
		_hair_mesh.visible = not (_scalp_debug_shown or _show_follicles or _beard_follicles_shown)
	if not _scalp_debug_shown or _hair_mesh == null or not (_hair_mesh.mesh is ArrayMesh):
		return
	var mesh := _hair_mesh.mesh as ArrayMesh
	var guides: PackedVector3Array = mesh.get_meta(&"hair_guides", PackedVector3Array())
	var steps: int = int(mesh.get_meta(&"hair_guide_steps", 1))
	var count: int = int(mesh.get_meta(&"hair_guide_count", 0))
	if count == 0 or steps < 2:
		return
	var low := Vector3(1e9, 1e9, 1e9)
	var high := Vector3(-1e9, -1e9, -1e9)
	for g in count:
		var root: Vector3 = guides[g * steps]
		low = low.min(root)
		high = high.max(root)
	var centre_z: float = 0.5 * (low.z + high.z)
	var half_depth: float = 0.5 * (high.z - low.z)
	var half_width: float = maxf(absf(low.x), absf(high.x))
	var crown := Vector3.ZERO
	var crown_n: int = 0
	for g in count:
		var root: Vector3 = guides[g * steps]
		if root.y > high.y - 0.012:
			crown += root
			crown_n += 1
	if crown_n > 0:
		crown /= float(crown_n)
	if mesh.has_meta(&"hair_crown"):
		crown = mesh.get_meta(&"hair_crown")   # (the crown the builder uses)
	var dot := SphereMesh.new()
	dot.radius = 0.0013
	dot.height = 0.0026
	dot.radial_segments = 5
	dot.rings = 3
	var dot_material := StandardMaterial3D.new()
	dot_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dot_material.vertex_color_use_as_albedo = true
	dot_material.vertex_color_is_srgb = true
	dot.material = dot_material
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.mesh = dot
	multi.instance_count = count
	var lines := PackedVector3Array()
	for g in count:
		var root: Vector3 = guides[g * steps]
		var u: float = (root.z - centre_z) / maxf(half_depth, 0.001)      # +1 front .. -1 back
		var h: float = (root.y - low.y) / maxf(high.y - low.y, 0.001)      # 0 lowest root .. 1 top
		var side: float = absf(root.x) / maxf(half_width, 0.001)          # 0 middle .. 1 side
		var crown_d: float = Vector2(root.x - crown.x, root.z - crown.z).length()
		var colour := Color(1.0, 0.9, 0.3)                                # parietal
		if crown_d < 0.035:
			colour = Color(0.9, 0.3, 0.85)                                # vertex / crown whorl
		elif u < -0.35 and h < 0.2:
			colour = Color(1.0, 0.55, 0.7)                                # nape
		elif u < -0.2 and h < 0.55:
			colour = Color(0.3, 0.5, 0.95)                                # occipital
		elif side > 0.72 and h < 0.55 and u > 0.1:
			colour = Color(0.55, 0.9, 0.3)                                # temples
		elif side > 0.72 and h < 0.6:
			colour = Color(0.3, 0.85, 0.6)                                # temporal
		elif u > 0.35 and h < 0.45:
			colour = Color(0.45, 0.75, 1.0)                               # frontal hairline
		elif u > 0.05:
			colour = Color(0.7, 0.4, 0.95)                                # frontal top
		multi.set_instance_transform(g, Transform3D(Basis(), root))
		multi.set_instance_color(g, colour)
		if g % 14 == 0:
			var direction: Vector3 = (guides[g * steps + mini(4, steps - 1)] - root).normalized()
			var tip: Vector3 = root + direction * 0.03
			lines.push_back(root)
			lines.push_back(tip)
			var side_dir: Vector3 = direction.cross(Vector3.UP).normalized() * 0.004   # (a small head for the arrow)
			lines.push_back(tip)
			lines.push_back(tip - direction * 0.006 + side_dir)
			lines.push_back(tip)
			lines.push_back(tip - direction * 0.006 - side_dir)
	_scalp_debug_node = Node3D.new()
	var dots_node := MultiMeshInstance3D.new()
	dots_node.multimesh = multi
	_scalp_debug_node.add_child(dots_node)
	var line_arrays: Array = []
	line_arrays.resize(Mesh.ARRAY_MAX)
	line_arrays[Mesh.ARRAY_VERTEX] = lines
	var line_mesh := ArrayMesh.new()
	line_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, line_arrays)
	var line_material := StandardMaterial3D.new()
	line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_material.albedo_color = Color(1.0, 1.0, 1.0)
	line_mesh.surface_set_material(0, line_material)
	var lines_node := MeshInstance3D.new()
	lines_node.mesh = line_mesh
	_scalp_debug_node.add_child(lines_node)
	_body.add_child(_scalp_debug_node)


func _on_beard_follicles_toggled(pressed: bool) -> void:
	_beard_follicles_shown = pressed
	_update_beard_follicles()


# The beard's follicles: where each beard hair group is rooted on the skin (HumanHair keeps them as the mesh meta "hair_beard_roots"; every dot grows several hairs).
# Orange dots; the hair is hidden while they show. They are rebuilt with the hair (a slider moves, a style is picked).
func _update_beard_follicles() -> void:
	if _beard_follicle_node != null:
		_beard_follicle_node.queue_free()
		_beard_follicle_node = null
	if _hair_mesh != null:
		_hair_mesh.visible = not (_beard_follicles_shown or _show_follicles or _scalp_debug_shown)
	if not _beard_follicles_shown or _hair_mesh == null or not (_hair_mesh.mesh is ArrayMesh):
		return
	var roots: PackedVector3Array = (_hair_mesh.mesh as ArrayMesh).get_meta(&"hair_beard_roots", PackedVector3Array())
	if roots.is_empty():
		_hair_info = "Beard follicles: none (the beard amount is 0)"
		_apply()
		return
	var dot := SphereMesh.new()
	dot.radius = 0.0007
	dot.height = 0.0014
	dot.radial_segments = 5
	dot.rings = 3
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.55, 0.05)
	dot.material = material
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = dot
	multi.instance_count = roots.size()
	for f in roots.size():
		multi.set_instance_transform(f, Transform3D(Basis(), roots[f]))
	_beard_follicle_node = MultiMeshInstance3D.new()
	_beard_follicle_node.multimesh = multi
	_body.add_child(_beard_follicle_node)
	_hair_info = "Beard follicles: %s (each roots several hairs)" % _thousands(roots.size())
	_apply()


func _on_scalp_layer_changed(value: float) -> void:
	_scalp_layer = value
	_head_hair_material.set_shader_parameter(&"scalp_layer", value)


# The skin shader darkens the scalp (where the hair grows) to the colour of the hair roots: the weights come with the hair mesh.
func _upload_scalp(built: ArrayMesh) -> void:
	if _material == null or built == null or not built.has_meta(&"hair_scalp_weight"):
		return
	var weights: PackedFloat32Array = built.get_meta(&"hair_scalp_weight")
	var nonzero: int = 0
	var top: float = 0.0
	for w in weights:
		if w > 0.0:
			nonzero += 1
		top = maxf(top, w)
	print("HUMAN_LAB scalp weights: ", weights.size(), " vertices, ", nonzero, " above zero, max ", top, " mesh vertices ", _mesh.mesh.surface_get_array_len(0) if _mesh != null else -1)
	var width: int = 1024
	var height: int = int(ceil(float(weights.size()) / float(width)))
	var padded := PackedFloat32Array()
	padded.resize(width * height)
	for i in weights.size():
		padded[i] = weights[i]
	var image := Image.create_from_data(width, height, false, Image.FORMAT_RF, padded.to_byte_array())
	_material.set_shader_parameter(&"scalp_tex", ImageTexture.create_from_image(image))
	_material.set_shader_parameter(&"scalp_width", width)
	if built.has_meta(&"hair_mouth"):
		var mouth: Vector3 = built.get_meta(&"hair_mouth")
		_material.set_shader_parameter(&"lip_info", mouth)
		_material.set_shader_parameter(&"has_lips", mouth != Vector3.ZERO)
	_material.set_shader_parameter(&"has_scalp", true)


func _update_scalp_colour() -> void:
	if _material != null:
		_material.set_shader_parameter(&"scalp_color", _head_hair_color * 0.55)


# A slider whose label shows its value (the plain range slider does not).
func _add_value_slider(parent: Control, label_text: String, low: float, high: float, value: float, callback: Callable) -> HSlider:
	var label := Label.new()
	label.text = "%s: %.2f" % [label_text, value]
	parent.add_child(label)
	var slider := HSlider.new()
	slider.scrollable = false
	slider.min_value = low
	slider.max_value = high
	slider.step = (high - low) / 100.0
	slider.value = value
	slider.value_changed.connect(func(v: float) -> void: label.text = "%s: %.2f" % [label_text, v])
	slider.value_changed.connect(callback)
	parent.add_child(slider)
	return slider


func _on_beard_style(entry: Array) -> void:
	_beard_only_change = true
	_hair_style[&"beard"] = float(entry[1])
	_hair_style[&"beard_length"] = float(entry[2])
	_hair_style[&"beard_zone"] = float(entry[3])
	_hair_style[&"neck_beard"] = float(entry[4])
	_hair_style[&"beard_curl"] = float(entry[5]) if entry.size() > 5 else 0.0
	if _hair_sliders.has(&"beard_curl"):
		(_hair_sliders[&"beard_curl"] as HSlider).set_value_no_signal(float(_hair_style[&"beard_curl"]))
	if _hair_sliders.has(&"neck_beard"):
		(_hair_sliders[&"neck_beard"] as HSlider).set_value_no_signal(float(entry[4]))
	for key: StringName in [&"beard", &"beard_length"]:
		if _hair_sliders.has(key):
			(_hair_sliders[key] as HSlider).set_value_no_signal(float(_hair_style[key]))
		if _hair_slider_labels.has(key):
			_show_slider_value(key)
	_hair_retry = 0
	_hair_last_change_ms = Time.get_ticks_msec()
	_hair_dirty = true


# Everything the editor sets, as one Dictionary (CharacterStore saves it).
func _character_state() -> Dictionary:
	var shine: Variant = _head_hair_material.get_shader_parameter(&"shine") if _head_hair_material != null else null
	return {
		"gender": _gender, "height": _height, "weight": _weight, "muscle": _muscle,
		"face_values": _face_values.duplicate(),
		"skin_file": _skin_file, "skin_values": _skin_values.duplicate(), "skin_shave_set": _skin_shave_set,
		"eye_color": _eye_color, "eye_color_other": _eye_color_other, "different_eyes": _different_eyes,
		"iris_deg": _iris_deg, "pupil": _pupil, "sclera_tint": _sclera_tint, "veins": _veins,
		"brow_style": _face_hair_suffix, "brow_density": _brow_density, "brow_color": _hair_color, "brow_given": _brow_given,
		"hair_color": _head_hair_color, "tip_color": _tip_color, "tip_mix": _tip_mix,
		"hair_preset": _hair_preset_name, "hair_style": _hair_style.duplicate(), "hair_zones": _hair_zones.duplicate(true),
		"wet": _wet, "scalp_layer": _scalp_layer, "target_hairs": _target_hairs,
		"beard_grey": _beard_grey, "beard_ginger": _beard_ginger, "body_hair": _body_hair.duplicate(), "clothes": _clothes, "cloth_flaws": _cloth_flaws.duplicate(), "hair_density": _head_hair_density, "hair_grey": _hair_grey, "brow_grey": _brow_grey,
		"shine": float(shine) if shine != null else 0.25,
	}


# Sets the lab's variables from a saved state (before the panel and materials are built). Missing entries keep the defaults.
func _apply_character_state(state: Dictionary) -> void:
	if BODY_SCENES.has(str(state.get("gender", _gender))):
		_gender = str(state["gender"])
	_height = float(state.get("height", _height))
	_weight = float(state.get("weight", _weight))
	_muscle = float(state.get("muscle", _muscle))
	if state.get("face_values") is Dictionary:
		_face_values = (state["face_values"] as Dictionary).duplicate()
	_skin_file = str(state.get("skin_file", _skin_file))
	if state.get("skin_values") is Dictionary:
		_skin_values = (state["skin_values"] as Dictionary).duplicate()
	_skin_shave_set = bool(state.get("skin_shave_set", _skin_shave_set))
	for entry: Array in [["eye_color", "_eye_color"], ["eye_color_other", "_eye_color_other"], ["brow_color", "_hair_color"], ["hair_color", "_head_hair_color"], ["tip_color", "_tip_color"]]:
		if state.get(entry[0]) is Color:
			set(entry[1], state[entry[0]])
	_different_eyes = bool(state.get("different_eyes", _different_eyes))
	_iris_deg = float(state.get("iris_deg", _iris_deg))
	_pupil = float(state.get("pupil", _pupil))
	_sclera_tint = float(state.get("sclera_tint", _sclera_tint))
	_veins = float(state.get("veins", _veins))
	_face_hair_suffix = str(state.get("brow_style", _face_hair_suffix))
	_brow_density = float(state.get("brow_density", _brow_density))
	_brow_given = bool(state.get("brow_given", _brow_given))
	_tip_mix = float(state.get("tip_mix", _tip_mix))
	_hair_preset_name = str(state.get("hair_preset", _hair_preset_name))
	if state.get("hair_style") is Dictionary:
		for key: StringName in state["hair_style"]:
			_hair_style[key] = (state["hair_style"] as Dictionary)[key]
	_wet = float(state.get("wet", _wet))
	_hair_style[&"wet"] = _wet
	_scalp_layer = float(state.get("scalp_layer", _scalp_layer))
	_target_hairs = int(state.get("target_hairs", _target_hairs))
	_shine_override = float(state.get("shine", _shine_override))
	_beard_grey = float(state.get("beard_grey", _beard_grey))
	if state.get("cloth_flaws") is Dictionary:
		for key: String in state["cloth_flaws"]:
			if _cloth_flaws.has(key):
				_cloth_flaws[key] = float(state["cloth_flaws"][key])
	if state.get("clothes") is String and CLOTHES.has(state["clothes"]):
		_clothes = state["clothes"]
	if state.get("body_hair") is Dictionary:
		for key: String in state["body_hair"]:
			if _body_hair.has(key):
				_body_hair[key] = float(state["body_hair"][key])
	_beard_ginger = float(state.get("beard_ginger", _beard_ginger))
	_head_hair_density = float(state.get("hair_density", _head_hair_density))
	_hair_grey = float(state.get("hair_grey", _hair_grey))
	_brow_grey = float(state.get("brow_grey", _brow_grey))
	if state.get("hair_zones") is Dictionary:
		_character_zones_pending = (state["hair_zones"] as Dictionary).duplicate(true)


const RANDOM_STYLES: Dictionary = {
	"Male": ["Buzz", "Short", "Dapper", "Pompadour", "Side part", "Undercut", "Crew cut", "Messy crop", "Quiff", "Fade", "Bedhead", "French crop", "Slick undercut", "Ivy league", "Spiky", "Surfer", "Cropped waves", "Afro", "Slick back", "Curly", "Wavy medium", "Curtains", "Shaggy"],
	"Female": ["Long waves", "Bob", "Long", "Pixie", "Curtains", "Wavy medium", "Feathered", "Afro", "Curly", "Shaggy", "Side fringe", "Mop top"],
}


# A random character (same gender): the state is made here and loaded the way a saved character is (the lab restarts with it, every control at its value).
func _on_random_character() -> void:
	var state: Dictionary = _character_state()
	var spread := func(width: float) -> float: return clampf(randfn(0.0, width), -1.0, 1.0)
	state["height"] = spread.call(0.35)
	state["weight"] = spread.call(0.35)
	state["muscle"] = spread.call(0.35)
	var face: Dictionary = {}
	for entry: Array in FACE_SLIDERS + BODY_SHAPE_SLIDERS:
		if entry.size() == 1:
			continue
		var shape_range: float = minf(float(entry[3]) if entry.size() > 3 else 1.5, 1.0)
		var value: float = float(spread.call(0.3)) * shape_range
		if entry[1] == "age_young":
			value = randf_range(-0.6, 0.7)
		if entry[1] == "bust_small" and _gender != "Female":
			value = 0.0
		face[StringName(entry[1])] = maxf(-value, 0.0)
		face[StringName(entry[2])] = maxf(value, 0.0)
	state["face_values"] = face
	# skin: any tone, an undertone, freckles now and then on light skin; the flat colour (the tone shows)
	var tone: float = randf()
	var skin: Dictionary = (state["skin_values"] as Dictionary).duplicate()
	skin[&"skin_tone"] = tone
	skin[&"undertone"] = randf_range(-0.35, 0.6)   # (a strong pink undertone with the default redness made a red nose)
	skin[&"freckles"] = randf_range(0.2, 0.7) if tone < 0.35 and randf() < 0.3 else 0.0
	skin[&"age"] = clampf(0.15 + 0.6 * float(face[&"age_old"]), 0.0, 1.0)
	state["skin_values"] = skin
	state["skin_file"] = ""
	# hair and eyes: darker skin mostly has dark hair and brown eyes; no grey or white here (greying comes with age)
	var dark: bool = tone > 0.55 and randf() < 0.9
	var hair_pick: Array = HAIR_COLOURS[randi_range(0, 1)] if dark else HAIR_COLOURS[randi_range(0, HAIR_COLOURS.size() - 3)]
	state["hair_color"] = hair_pick[1]
	state["brow_given"] = false
	state.erase("brow_color")
	var eye_pick: Array = EYE_COLOURS[randi_range(0, 1)] if (dark or randf() < 0.45) else EYE_COLOURS[randi() % EYE_COLOURS.size()]
	state["eye_color"] = eye_pick[1]
	state["brow_style"] = str(BROW_STYLES[randi() % BROW_STYLES.size()][1])
	state["hair_zones"] = {}
	state["hair_grey"] = smoothstep(0.35, 1.0, float(face[&"age_old"])) * 0.75
	var styles: Array = RANDOM_STYLES.get(_gender, RANDOM_STYLES["Male"])
	# a beard for half the men; otherwise "None" (index 0), so the last character's beard and its grey/ginger do not carry over
	var beard_index: int = randi_range(1, BEARD_STYLES.size() - 1) if _gender == "Male" and randf() < 0.5 else 0
	_pending_random = {"preset": styles[randi() % styles.size()], "beard": beard_index}
	state["beard_grey"] = minf(float(state["hair_grey"]) * 1.15, 1.0) if beard_index > 0 else 0.0
	state["beard_ginger"] = 0.0
	state["cloth_flaws"] = {"seed": float(randi() % 10000), "imperfection": randf_range(0.1, 0.9), "wear": randf_range(0.2, 0.9)}   # (a villager's clothes: some new, some old)
	if _gender == "Male":
		# body hair: from none to hairy (most men in between), the length and curl of their own
		var body_hair: Dictionary = _body_hair.duplicate()
		body_hair["amount"] = clampf(randf_range(0.0, 1.0) * randf_range(0.3, 1.0), 0.0, 1.0)
		body_hair["back"] = randf_range(0.0, 0.6) if randf() < 0.4 else 0.0
		body_hair["length"] = randf_range(0.008, 0.02)
		body_hair["curl"] = randf_range(0.1, 0.8)
		state["body_hair"] = body_hair
	_pending_character = state
	_pending_character_name = ""
	get_tree().reload_current_scene()


func _fill_character_list() -> void:
	if _character_option == null:
		return
	_character_option.clear()
	_character_option.add_item("Load a character...")
	for character_name: String in CharacterStore.list_characters(_characters_dir):
		_character_option.add_item(character_name)
		if character_name == _character_name:
			_character_option.select(_character_option.item_count - 1)


func _save_character(character_name: String) -> void:
	var clean: String = HairStyleStore.clean_name(character_name)
	if clean.is_empty():
		return
	if CharacterStore.save_character(_characters_dir, clean, _character_state()) == OK:
		_character_name = clean
		_fill_character_list()
		print("HUMAN_LAB saved character ", clean, " in ", _characters_dir)


func _on_character_selected(index: int) -> void:
	if index <= 0:
		return
	var character_name: String = _character_option.get_item_text(index)
	var state: Dictionary = CharacterStore.load_character(_characters_dir, character_name)
	if state.is_empty():
		return
	_pending_character = state
	_pending_character_name = character_name
	get_tree().reload_current_scene()


func _on_delete_character() -> void:
	var clean: String = HairStyleStore.clean_name(_character_name_edit.text)
	if clean.is_empty():
		return
	CharacterStore.delete_character(_characters_dir, clean)
	if clean == _character_name:
		_character_name = ""
	_fill_character_list()


# Sliders for blend-shape pairs (FACE_SLIDERS, BODY_SHAPE_SLIDERS), started at the current values.
func _add_shape_sliders(parent: Control, entries: Array) -> void:
	for entry: Array in entries:
		if entry.size() == 1:
			_add_section_label(parent, str(entry[0]))
			continue
		var label := Label.new()
		label.text = "%s: 0.00" % entry[0]
		parent.add_child(label)
		var slider := HSlider.new()
		slider.scrollable = false
		var shape_range: float = float(entry[3]) if entry.size() > 3 else 1.5
		slider.min_value = -shape_range
		slider.max_value = shape_range
		slider.step = 0.05   # (0.04 did not land on 0 for a +-1.5 range: a "neutral" face had 0.02 of every such key)
		slider.value = float(_face_values.get(StringName(entry[2]), 0.0)) - float(_face_values.get(StringName(entry[1]), 0.0))
		label.text = "%s: %.2f" % [entry[0], slider.value]
		slider.value_changed.connect(_on_face_slider.bind(entry, label))
		parent.add_child(slider)
		_shape_sliders[StringName(entry[1])] = slider


func _on_whole_age(value: float) -> void:
	if _shape_sliders.has(&"age_young"):
		(_shape_sliders[&"age_young"] as HSlider).value = value
	var old: float = maxf(value, 0.0)
	if _skin_sliders.has(&"age"):
		(_skin_sliders[&"age"] as HSlider).value = lerpf(0.1, 1.0, old) if value >= 0.0 else lerpf(0.1, 0.0, -value)
	var grey: float = smoothstep(0.35, 1.0, old) * 0.75   # (greying starts in middle age; at the oldest a little dark hair remains)
	if _hair_grey_slider != null:
		_hair_grey_slider.value = grey
	if _beard_grey_slider != null:
		_beard_grey_slider.value = minf(grey * 1.15, 1.0)   # (a beard greys a little sooner than the head)
	_brow_grey = grey * 0.6   # (the brows grey last)
	for material: ShaderMaterial in [_brow_material, _lash_material]:
		material.set_shader_parameter(&"grey", _brow_grey)


# A random face: every face slider moved a little (a normal-ish spread: most faces near the middle, now and then a strong feature).
func _on_random_face() -> void:
	for entry: Array in FACE_SLIDERS:
		if entry.size() == 1 or not _shape_sliders.has(StringName(entry[1])):
			continue
		var shape_range: float = float(entry[3]) if entry.size() > 3 else 1.5
		var value: float = clampf(randfn(0.0, 0.3), -1.0, 1.0) * minf(shape_range, 1.0)
		if entry[1] == "age_young":
			value = randf_range(-0.6, 0.6)
		(_shape_sliders[StringName(entry[1])] as HSlider).value = snappedf(value, 0.05)


func _on_reset_face() -> void:
	for entry: Array in FACE_SLIDERS:
		if entry.size() > 1 and _shape_sliders.has(StringName(entry[1])):
			(_shape_sliders[StringName(entry[1])] as HSlider).value = 0.0


func _on_face_slider(value: float, entry: Array, label: Label) -> void:
	label.text = "%s: %.2f" % [entry[0], value]
	_face_values[StringName(entry[1])] = maxf(-value, 0.0)
	_face_values[StringName(entry[2])] = maxf(value, 0.0)
	_apply_face_shapes()
	_apply()
	_hair_retry = 0
	_hair_last_change_ms = Time.get_ticks_msec()
	_hair_dirty = true   # (the hair is rebuilt on the new head; while a slider moves a light preview, then the full hair)


# The face keys as blend shapes on every mesh that has them (body, eyes, brows, lashes, underwear); the hair has none of them: it is built on a body with them baked in.
func _apply_face_shapes() -> void:
	for target: MeshInstance3D in [_mesh, _underwear_mesh, _eyes_mesh, _brows_mesh, _lashes_mesh, _shirt_mesh, _pants_mesh]:
		if target == null:
			continue
		for key: StringName in _face_values:
			var index: int = target.find_blend_shape_by_name(key)
			if index >= 0:
				target.set_blend_shape_value(index, float(_face_values[key]))
	_landmarks_dirty_ms = Time.get_ticks_msec()   # (the skin's landmarks follow once the sliders rest: _update_landmarks)


# The skin's landmarks from the reshaped body (face frame, eye centre, joints). Baking every blend shape into the body costs about 50 ms, so it waits
# until the shapes have rested for 0.15 s (a slider being dragged changes them every frame).
func _update_landmarks() -> void:
	if _mesh != null and _material != null:
		_set_face_frame(_shaped_body_mesh())   # (the skin's zones follow the reshaped face: the shader sees every blend shape applied)
		if _eyes_mesh != null:
			_set_eye_centre(_shaped_body_mesh(_eyes_mesh))
		_set_joints()


# A mesh with every blend shape it shows now baked in (height, weight, muscle and face): for the body, where the skin shader's VERTEX really is.
func _shaped_body_mesh(instance: MeshInstance3D = null) -> ArrayMesh:
	if instance == null:
		instance = _mesh
	var base := instance.mesh as ArrayMesh
	var names := PackedStringArray()
	var values := PackedFloat32Array()
	for index: int in base.get_blend_shape_count():
		var value: float = instance.get_blend_shape_value(index)
		if absf(value) > 0.0001:
			names.append(String(base.get_blend_shape_name(index)))
			values.append(value)
	if names.is_empty():
		return base
	return HumanHair.bake_shapes(base, names, values)


# The body hair (men only): HumanBodyHair grown on the base body (it carries the height / weight / muscle shapes, so the sliders do not rebuild it),
# drawn with the head hair's material (it is marked like the beard: the beard's colour, grey and ginger). About 0.1 s for 45,000 hairs.
# The clothes for this body: the villager shirt and trousers (the underwear stays under them, hidden), or the underwear alone.
func _load_clothes() -> void:
	_stop_cloth()
	for old: MeshInstance3D in [_shirt_mesh, _pants_mesh]:
		if old != null and is_instance_valid(old) and _body != null and _body.is_ancestor_of(old):
			var root: Node = old
			while root != null and root.get_parent() != _body:
				root = root.get_parent()
			if root != null:
				root.queue_free()
	_shirt_mesh = null
	_pants_mesh = null
	var clothed: bool = _clothes == "Villager"
	if _underwear_mesh != null:
		_underwear_mesh.visible = not clothed
	if not clothed or _body == null:
		return
	var colours: Array = CLOTHES_COLOURS[_gender]
	_shirt_material.set_shader_parameter(&"cloth_color", colours[0])
	_pants_material.set_shader_parameter(&"cloth_color", colours[1])
	_apply_cloth_flaws()
	var paths: Array = CLOTHES_SCENES[_gender]
	for i in 2:
		var piece: Node3D = (load(paths[i]) as PackedScene).instantiate() as Node3D
		_body.add_child(piece)
		var mesh: MeshInstance3D = _find_mesh(piece)
		mesh.material_override = _shirt_material if i == 0 else _pants_material
		if i == 0:
			_shirt_mesh = mesh
		else:
			_pants_mesh = mesh
	_cloth_shape_key = ""
	_cloth_restart_ms = Time.get_ticks_msec() + 100   # (after the shapes are set on the new pieces)


func _apply_cloth_flaws() -> void:
	for i in 2:
		var cloth: ShaderMaterial = _shirt_material if i == 0 else _pants_material
		if cloth == null:
			continue
		cloth.set_shader_parameter(&"flaw_seed", float(_cloth_flaws["seed"]) + float(i) * 7.3)   # (the shirt and the trousers have different flaws)
		cloth.set_shader_parameter(&"imperfection", float(_cloth_flaws["imperfection"]))
		cloth.set_shader_parameter(&"wear", float(_cloth_flaws["wear"]))
		# a patch is a scrap of some other cloth: a little darker or lighter than the garment, its own tint
		var rng := RandomNumberGenerator.new()
		rng.seed = int(float(_cloth_flaws["seed"]) * 1000.0) + i
		var garment: Color = CLOTHES_COLOURS[_gender][i]
		var scraps: Array = [Color(0.66, 0.6, 0.5), Color(0.4, 0.31, 0.22), Color(0.3, 0.28, 0.26), Color(0.5, 0.45, 0.38), Color(0.36, 0.33, 0.24), Color(0.42, 0.26, 0.2)]   # (undyed linen, brown, grey wool, oatmeal, a dull green-brown, a faded madder red)
		var scrap: Color = scraps[rng.randi() % scraps.size()]
		cloth.set_shader_parameter(&"patch_color", scrap * rng.randf_range(0.85, 1.05))
	if _cloth_rig != null:
		_cloth_restart_ms = Time.get_ticks_msec() + 400   # (the simulated pieces draw with copies of these materials: rebuilt with the new flaws)


const CLOTH_BODY_SHAPES: Array = [&"height_tall", &"height_short", &"weight_heavy", &"weight_light", &"muscle_high", &"muscle_low"]


# The villager clothes as cloth (task 103), as in the rig lab: the GPU cloth solver needs a skeleton, and this lab's body has none. So the rigged body
# (same mesh, same shapes) is loaded hidden at the body's place; the rig is set to the body's shapes (HumanRig moves the bones and the skin binds);
# the garments and the rigged mesh are BAKED to the current shapes (the solver reads a mesh's base vertices: blend shapes are not part of its rest
# shape), skinned to that skeleton, and simulated. The body turns, the skeleton with it, the cloth swings. A slider change restarts it once the slider
# rests; so do the gender and the clothes.
func _stop_cloth() -> void:
	for solver: Node in _cloth_solvers:
		if is_instance_valid(solver):
			solver.queue_free()
	_cloth_solvers.clear()
	_cloth_pieces.clear()
	if _cloth_rig != null and is_instance_valid(_cloth_rig):
		_cloth_rig.queue_free()
	_cloth_rig = null
	_cloth_restart_ms = -1


func _restart_cloth() -> void:
	_stop_cloth()
	var simulate: bool = _cloth_sim and _clothes == "Villager" and _body != null and _shirt_mesh != null and _pants_mesh != null
	for static_piece: MeshInstance3D in [_shirt_mesh, _pants_mesh]:
		if static_piece != null and is_instance_valid(static_piece):
			static_piece.visible = not simulate
	if not simulate:
		return
	var weights: Dictionary = {}
	for shape: StringName in CLOTH_BODY_SHAPES:
		weights[shape] = _mesh.get_blend_shape_value(_mesh.find_blend_shape_by_name(shape))
	_cloth_shape_key = _cloth_key(weights)
	var base: String = "res://assets/models/humans/%s_" % _gender.to_lower()
	_cloth_rig = (load(base + "rigged.glb") as PackedScene).instantiate() as Node3D
	_cloth_rig.name = "ClothRig"
	_body.add_child(_cloth_rig)
	var skeleton: Skeleton3D = _cloth_rig.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var collider: MeshInstance3D = null
	var largest: int = -1
	for candidate: MeshInstance3D in _cloth_rig.find_children("*", "MeshInstance3D", true, false):
		var count: int = (candidate.mesh as ArrayMesh).surface_get_array_len(0)
		candidate.visible = false
		if count > largest:   # (the male rigged glb carries a small extra mesh: the body is the largest)
			largest = count
			collider = candidate
	var materials: Array = [_shirt_material, _pants_material]
	for i in 2:
		var scene: Node = (load(CLOTHES_SCENES[_gender][i]) as PackedScene).instantiate()
		var piece: MeshInstance3D = _find_mesh(scene)
		piece.get_parent().remove_child(piece)
		scene.free()
		piece.name = "ShirtSim" if i == 0 else "PantsSim"
		skeleton.add_child(piece)
		HumanRig.attach_skinned(piece, collider, skeleton)
		_cloth_pieces.append(piece)
	var skinned: Array = [collider]
	skinned.append_array(_cloth_pieces)
	for target: MeshInstance3D in skinned:
		for shape: StringName in weights:
			var index: int = target.find_blend_shape_by_name(shape)
			if index >= 0:
				target.set_blend_shape_value(index, float(weights[shape]))
	var rig := HumanRig.new()
	if not rig.setup(skeleton, skinned, HumanRig.load_data(base + "rig.json")):
		push_error("cloth: HumanRig.setup failed")
		return
	rig.apply(weights)   # (the bones and the skin binds follow the shapes)
	for target: MeshInstance3D in skinned:
		target.mesh = _baked_mesh(target)
	for i in 2:
		var piece: MeshInstance3D = _cloth_pieces[i]
		var solver := GPUClothSolver.new()
		solver.name = "ShirtCloth" if i == 0 else "PantsCloth"
		solver.cloth_weight_channel = 2   # (make_clothes.py: vertex colour blue, 0 glued .. 1 free)
		solver.cloth_material = materials[i]
		solver.flip_normals = true   # (without it the solver's normals for our garments point into the body: a dark shirt with bright specks)
		solver.solver_iterations = 4
		solver.substeps = 2
		solver.stiffness = 0.9
		solver.bend_stiffness = 0.6
		solver.damping = 0.985
		solver.max_travel_distance = 0.04
		solver.cloth_skin_offset = 0.0
		solver.cloth_render_offset = 0.004   # (drawn 4 mm out along the normal: hides the skin where free cloth sinks onto capsules inside the body)
		solver.body_collider_voxel_resolution = 0   # Capsule support; the shirt adds native arm contact below.
		solver.auto_collider_lod = 1
		# (the torso is oval, a capsule round: small capsules, inside the body, or they push the shirt out like a cape and the trousers' waistband out
		# over the shirt's hem; the shins full ones, or they poke through: per bone, a local patch in the add-on)
		solver.auto_collider_radius_percentile = 0.5
		solver.auto_collider_radius_scale = 0.8
		if i == 0:
			# Exact arm surface, weighted like the visible body, packed in native code.
			solver.body_collider_voxel_resolution = 1
			solver.body_collider_preparer = func(data: Dictionary) -> Dictionary:
				return HumanRig.prepare_cloth_arms(data)
			solver.body_collider_packer = func(data: Dictionary, poses: Array) -> PackedByteArray:
				return HumanRig.skin_cloth_arms(data, poses)
			solver.cloth_render_offset = 0.001
		else:
			solver.auto_collider_bone_overrides = {"mixamorig_LeftLeg": Vector2(0.85, 1.0), "mixamorig_RightLeg": Vector2(0.85, 1.0)}
		solver.body_collider_thickness = 0.004 if i == 0 else 0.006
		solver.peer_collider_voxel_resolution = 8
		solver.collider_friction = 0.5
		_cloth_solvers.append(solver)
	# (paths set before the solvers enter the tree: they start on their own _ready)
	for i in 2:
		var solver: GPUClothSolver = _cloth_solvers[i]
		solver.target_mesh = NodePath("../" + String(_cloth_rig.get_path_to(_cloth_pieces[i])))
		solver.skeleton = NodePath("../" + String(_cloth_rig.get_path_to(skeleton)))
		solver.body_mesh = NodePath("../" + String(_cloth_rig.get_path_to(collider)))
	(_cloth_solvers[0] as GPUClothSolver).peer_cloth_solvers = [NodePath("../PantsCloth")]
	(_cloth_solvers[1] as GPUClothSolver).peer_cloth_solvers = [NodePath("../ShirtCloth")]
	for solver: GPUClothSolver in _cloth_solvers:
		_cloth_rig.add_child(solver)


func _cloth_key(weights: Dictionary) -> String:
	var parts: PackedStringArray = []
	for shape: StringName in CLOTH_BODY_SHAPES:
		parts.append("%.4f" % float(weights.get(shape, 0.0)))
	return ",".join(parts)


# The mesh as it is drawn now: its blend shapes added into the base vertices, no shapes left (the cloth solver reads only the base vertices).
func _baked_mesh(target: MeshInstance3D) -> ArrayMesh:
	var source: ArrayMesh = target.mesh as ArrayMesh
	var baked := ArrayMesh.new()
	var relative: bool = source.blend_shape_mode == Mesh.BLEND_SHAPE_MODE_RELATIVE
	for surface in source.get_surface_count():
		var arrays: Array = source.surface_get_arrays(surface)
		var shapes: Array = source.surface_get_blend_shape_arrays(surface)
		var base: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var vertices: PackedVector3Array = base.duplicate()
		for shape in source.get_blend_shape_count():
			var amount: float = target.get_blend_shape_value(shape)
			if absf(amount) < 0.00001:
				continue
			var moved: PackedVector3Array = (shapes[shape] as Array)[Mesh.ARRAY_VERTEX]
			for v in vertices.size():
				vertices[v] += (moved[v] if relative else moved[v] - base[v]) * amount
		arrays[Mesh.ARRAY_VERTEX] = vertices
		var flags: int = source.surface_get_format(surface) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		baked.add_surface_from_arrays(source.surface_get_primitive_type(surface), arrays, [], {}, flags)
		baked.surface_set_material(surface, source.surface_get_material(surface))
	return baked


func _on_clothes_selected(index: int) -> void:
	_clothes = CLOTHES[index]
	_load_clothes()
	_apply_face_shapes()   # (the new pieces start with no shape set)
	_apply()
	_rebuild_body_hair()


func _rebuild_body_hair() -> void:
	if _body_hair_mesh != null and is_instance_valid(_body_hair_mesh):
		_body_hair_mesh.queue_free()
	_body_hair_mesh = null
	if _gender != "Male" or _mesh == null or not (_mesh.mesh is ArrayMesh) or float(_body_hair.get("amount", 0.0)) <= 0.0:
		return
	if _clothes != "Underwear":
		return   # (under the clothes: the curly chest hair would poke through the shirt, and nothing of it would show)
	var params: Dictionary = HumanBodyHair.default_params()
	for key: String in _body_hair:
		params[key] = _body_hair[key]
	var joints: Dictionary = BodyHairJoints.for_gender(_gender)
	# the nipples of the BASE body (the hair is built on it; the skin material holds the reshaped body's): the face frame cached on the base mesh
	var frame: Dictionary = _mesh.mesh.get_meta(&"lab_face_frame", {})
	if bool(frame.get(&"has_nipples", false)):
		var nipples: PackedVector3Array = frame[&"nipples"]
		if nipples.size() == 2:
			joints["nipple_l"] = nipples[0]
			joints["nipple_r"] = nipples[1]
	params["joints"] = joints
	var built: Dictionary = HumanBodyHair.build_arrays(HumanHair.prepare(_mesh.mesh as ArrayMesh), params)
	if not built.has("arrays"):
		return
	_body_hair_mesh = MeshInstance3D.new()
	_body_hair_mesh.name = "BodyHair"
	_body_hair_mesh.mesh = HumanHair.make_mesh(built)
	_body_hair_mesh.material_override = _head_hair_material
	_body.add_child(_body_hair_mesh)
	_apply()   # (the body's current height / weight / muscle on the new mesh)


func _hair_body_mesh() -> ArrayMesh:
	var names := PackedStringArray()
	var values := PackedFloat32Array()
	for key: StringName in _face_values:
		if absf(float(_face_values[key])) > 0.0001:
			names.append(String(key))
			values.append(float(_face_values[key]))
	if names.is_empty():
		return _mesh.mesh as ArrayMesh
	return HumanHair.bake_shapes(_mesh.mesh as ArrayMesh, names, values)


# The face's landmarks for the skin shader's zones (redness, shave shadow, oily T-zone, wrinkles...): the nose tip (the frontmost vertex on the
# middle line of the head), the top of the head and the chin (the lowest middle-line vertex in front, under the nose). In the mesh's own space.
const FACE_FRAME_PARAMS: Array[StringName] = [&"has_face", &"face_nose", &"has_nipples", &"nipples", &"has_mouth", &"mouth_y", &"face_top", &"face_chin"]


# The face frame of a mesh, worked out once per mesh (kept in its meta): the walk over every vertex took ~75 ms of each gender switch.
func _set_face_frame(mesh: Mesh) -> void:
	if mesh == null:
		return
	if mesh.has_meta(&"lab_face_frame"):
		var saved: Dictionary = mesh.get_meta(&"lab_face_frame")
		for key: StringName in saved:
			_material.set_shader_parameter(key, saved[key])
		return
	_compute_face_frame(mesh)
	var values: Dictionary = {}
	for key: StringName in FACE_FRAME_PARAMS:
		values[key] = _material.get_shader_parameter(key)
	mesh.set_meta(&"lab_face_frame", values)


func _compute_face_frame(mesh: Mesh) -> void:
	if mesh == null or mesh.get_surface_count() == 0:
		return
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var top: float = -INF
	for p: Vector3 in vertices:
		top = maxf(top, p.y)
	var nose := Vector3(0.0, 0.0, -INF)
	for p: Vector3 in vertices:
		if p.y > top - 0.25 and absf(p.x) < 0.006 and p.z > nose.z:
			nose = p
	if is_inf(nose.z):
		_material.set_shader_parameter(&"has_face", false)   # (no vertex on the middle line near the face: a mesh this frame does not fit; no zones rather than NaN)
		return
	var chin_y: float = nose.y
	for p: Vector3 in vertices:
		if absf(p.x) < 0.006 and p.y > top - 0.27 and p.z > nose.z - 0.045:
			chin_y = minf(chin_y, p.y)
	_material.set_shader_parameter(&"face_nose", nose)
	# the nipples: the most forward point of each side of the chest (15-30 cm below the chin, 5-14 cm out from the middle)
	var nipples := PackedVector3Array([Vector3(0.0, 0.0, -INF), Vector3(0.0, 0.0, -INF)])
	for p: Vector3 in vertices:
		if p.y < chin_y - 0.15 and p.y > chin_y - 0.3 and absf(p.x) > 0.05 and absf(p.x) < 0.14:
			var side: int = 0 if p.x > 0.0 else 1
			if p.z > nipples[side].z:
				nipples[side] = p
	_material.set_shader_parameter(&"has_nipples", not is_inf(nipples[0].z) and not is_inf(nipples[1].z))
	_material.set_shader_parameter(&"nipples", nipples)
	# the mouth line: on the middle line, the deepest point of the profile below the upper lip's most forward point (walking down in 1 mm steps until the
	# profile comes forward again: the lower lip); a step far deeper than both its neighbours is the inside of the mouth and is skipped
	var front_z: Dictionary = {}   # mm below the nose tip -> the most forward z there
	for p: Vector3 in vertices:
		if absf(p.x) < 0.004 and p.y < nose.y - 0.015 and p.y > nose.y - 0.05:
			var step: int = int(round((nose.y - p.y) * 1000.0))
			front_z[step] = maxf(float(front_z.get(step, -INF)), p.z)
	var upper_step: int = -1
	for step: int in range(18, 36):
		if front_z.has(step) and (upper_step < 0 or float(front_z[step]) > float(front_z[upper_step])):
			upper_step = step
	var mouth_step: int = -1
	if upper_step >= 0:
		var best: float = INF
		for step: int in range(upper_step + 1, 50):
			if not front_z.has(step):
				continue
			var z: float = front_z[step]
			var around: float = maxf(float(front_z.get(step - 1, z)), float(front_z.get(step + 1, z)))
			if z < around - 0.004:
				continue   # (the inside of the mouth)
			if z < best:
				best = z
				mouth_step = step
			elif z > best + 0.0005:
				break   # (the lower lip: the profile comes forward again)
	_material.set_shader_parameter(&"has_mouth", mouth_step >= 0)
	if mouth_step >= 0:
		_material.set_shader_parameter(&"mouth_y", nose.y - float(mouth_step) * 0.001)
	_material.set_shader_parameter(&"face_top", top)
	_material.set_shader_parameter(&"face_chin", chin_y)
	_material.set_shader_parameter(&"has_face", true)


# The joints for the skin's knee, elbow and knuckle zones: the rig file's bone heads (assets/models/humans/<body>_rig.json, the body's own space),
# moved by the height/weight/muscle shapes the body shows now (the file stores each shape's move of every joint).
func _set_joints() -> void:
	var path: String = "res://assets/models/humans/%s_rig.json" % _gender.to_lower()
	if not FileAccess.file_exists(path):
		return
	if not _rig_cache.has(path):
		_rig_cache[path] = JSON.parse_string(FileAccess.get_file_as_string(path))
	var rig: Variant = _rig_cache[path]
	if not (rig is Dictionary):
		return
	var bones: Array = rig["bones"]
	var heads: Array = rig["head"]
	var shapes: Dictionary = rig.get("shapes", {})
	var weights: Dictionary = {}
	var base := _mesh.mesh as ArrayMesh
	for index: int in base.get_blend_shape_count():
		var shape_name: String = String(base.get_blend_shape_name(index))
		if shapes.has(shape_name):
			weights[shape_name] = _mesh.get_blend_shape_value(index)
	var tails: Array = rig["tail"]
	var joint := func(bone: String, end: String = "head") -> Vector3:
		var i: int = bones.find("mixamorig:" + bone)
		if i < 0:
			return Vector3.ZERO
		var h: Array = (heads if end == "head" else tails)[i]
		var p := Vector3(float(h[0]), float(h[1]), float(h[2]))
		for shape_name: String in weights:
			var d: Array = ((shapes[shape_name] as Dictionary)[end] as Array)[i]
			p += Vector3(float(d[0]), float(d[1]), float(d[2])) * float(weights[shape_name])
		return p
	_material.set_shader_parameter(&"knee_l", joint.call("LeftLeg"))
	_material.set_shader_parameter(&"knee_r", joint.call("RightLeg"))
	for cloth: ShaderMaterial in [_shirt_material, _pants_material]:
		if cloth != null:
			cloth.set_shader_parameter(&"elbow_l", joint.call("LeftForeArm"))
			cloth.set_shader_parameter(&"elbow_r", joint.call("RightForeArm"))
			cloth.set_shader_parameter(&"knee_l", joint.call("LeftLeg"))
			cloth.set_shader_parameter(&"knee_r", joint.call("RightLeg"))
			cloth.set_shader_parameter(&"has_joints", true)
	_material.set_shader_parameter(&"elbow_l", joint.call("LeftForeArm"))
	_material.set_shader_parameter(&"elbow_r", joint.call("RightForeArm"))
	var knuckles := PackedVector3Array()
	for hand: String in ["Left", "Right"]:
		for finger: String in ["Index", "Middle", "Ring", "Pinky"]:
			knuckles.append(joint.call(hand + "Hand" + finger + "1"))
	_material.set_shader_parameter(&"knuckles", knuckles)
	# fingernails: the back of each hand is the normal of the plane through the wrist and the index and little-finger knuckles, on the side away from the body;
	# a nail is centred just behind the fingertip and a few millimetres toward the back of the finger
	var nails := PackedVector3Array()
	var nail_backs := PackedVector3Array()
	for hand: String in ["Left", "Right"]:
		var wrist: Vector3 = joint.call(hand + "Hand")
		var index: Vector3 = joint.call(hand + "HandIndex1")
		var pinky: Vector3 = joint.call(hand + "HandPinky1")
		var back: Vector3 = (index - wrist).cross(pinky - wrist).normalized()
		if back.x * wrist.x < 0.0:
			back = -back   # (the palms face the thighs in the rest pose: the back of a hand faces away from the body)
		for finger: String in ["Thumb", "Index", "Middle", "Ring", "Pinky"]:
			var tip: Vector3 = joint.call(hand + "Hand" + finger + "3", "tail")
			var last: Vector3 = joint.call(hand + "Hand" + finger + "3")
			var along: Vector3 = (tip - last).normalized()
			var nail_back: Vector3 = back
			if finger == "Thumb":
				# (the thumb is turned: its pad faces the index finger, its nail away from it)
				var away: Vector3 = tip - index
				nail_back = (away - along * away.dot(along)).normalized()
			nail_back = (nail_back - along * nail_back.dot(along)).normalized()
			nails.append(tip - along * 0.0065 + nail_back * 0.005)
			nail_backs.append(nail_back)
	_material.set_shader_parameter(&"nails", nails)
	var pits := PackedVector3Array()
	for side: String in ["Left", "Right"]:
		var shoulder: Vector3 = joint.call(side + "Arm")
		pits.append(shoulder + Vector3(-signf(shoulder.x) * 0.025, -0.055, -0.005))   # (the hollow: below the joint and toward the body)
	_material.set_shader_parameter(&"armpits", pits)
	_material.set_shader_parameter(&"has_armpits", true)
	_material.set_shader_parameter(&"wrists", PackedVector3Array([joint.call("LeftHand"), joint.call("RightHand")]))
	_material.set_shader_parameter(&"hand_mids", PackedVector3Array([joint.call("LeftHandMiddle1"), joint.call("RightHandMiddle1")]))
	_material.set_shader_parameter(&"nail_backs", nail_backs)
	_material.set_shader_parameter(&"has_joints", true)


# The centre of the +x eyeball (the eye mesh's vertices on that side), for the skin's eye zones: lids, eyeshadow, eyeliner, crow's feet.
func _set_eye_centre(mesh: Mesh) -> void:
	if mesh == null or mesh.get_surface_count() == 0:
		return
	var centre := Vector3.ZERO
	var count: int = 0
	for p: Vector3 in mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		if p.x > 0.0:
			centre += p
			count += 1
	if count > 0:
		_material.set_shader_parameter(&"face_eye", centre / float(count))
		_material.set_shader_parameter(&"has_eye", true)


# The Skin tab's detail sliders (the shader's procedural layers).
func _on_skin_value(value: float, key: StringName, label: Label, label_text: String) -> void:
	_skin_values[key] = value
	if key == &"shave_shadow":
		_skin_shave_set = true
	label.text = "%s: %.2f" % [label_text, value]
	if key == &"skin_tone" or key == &"undertone":
		_apply_skin_tone()
		return
	_material.set_shader_parameter(key, value)


# The flat skin colour from the tone (along the Monk scale) and the undertone (pink: more red and blue; olive: more green, less blue).
func _apply_skin_tone() -> void:
	var tone: float = clampf(float(_skin_values.get(&"skin_tone", 0.45)), 0.0, 1.0) * float(SKIN_TONES.size() - 1)
	var i: int = mini(int(tone), SKIN_TONES.size() - 2)
	var c: Color = (SKIN_TONES[i] as Color).lerp(SKIN_TONES[i + 1], tone - float(i))
	# (the swatches are a little grey-yellow as albedo: blood under the skin makes it warmer, the more so the darker; the lightest are a
	# little dimmed: under the lab's exposure they read white)
	var f: float = tone / float(SKIN_TONES.size() - 1)
	c = Color(c.r * (1.03 + 0.14 * f), c.g * (0.90 - 0.02 * f), c.b * (0.84 - 0.10 * f)) * lerpf(0.88, 1.0, f)
	var under: float = clampf(float(_skin_values.get(&"undertone", 0.0)), -1.0, 1.0)
	if under < 0.0:
		c = Color(c.r * (1.0 - 0.03 * under), c.g * (1.0 + 0.05 * under), c.b * (1.0 - 0.02 * under))   # pink: redder, bluer, less green
	else:
		c = Color(c.r * (1.0 - 0.03 * under), c.g * (1.0 + 0.03 * under), c.b * (1.0 - 0.08 * under))   # olive: greener, less red and blue
	_material.set_shader_parameter(&"skin_color", c)


func _add_skin_slider(parent: Control, label_text: String, key: StringName, low: float, high: float, value: float) -> void:
	var label := Label.new()
	label.text = "%s: %.2f" % [label_text, value]
	parent.add_child(label)
	var slider := HSlider.new()
	slider.scrollable = false
	slider.min_value = low
	slider.max_value = high
	slider.step = (high - low) / 100.0
	slider.value = value
	slider.value_changed.connect(_on_skin_value.bind(key, label, label_text))
	parent.add_child(slider)
	_skin_sliders[key] = slider


func _on_skin_chosen(file_name: String) -> void:
	if _material == null:
		return
	if file_name == "":
		_material.set_shader_parameter(&"has_skin_tex", false)
		_material.set_shader_parameter(&"has_skin_normal", false)
		_material.set_shader_parameter(&"has_skin_spec", false)
		return
	var texture := load("res://assets/models/humans/skins/%s.jpg" % file_name) as Texture2D
	if texture == null:
		push_warning("skin not found: " + file_name)
		return
	_material.set_shader_parameter(&"skin_tex", texture)
	_material.set_shader_parameter(&"has_skin_tex", true)
	# the optional maps of the same skin (only the Mindfront skins ship them): <name>_n.png (normal) and <name>_s.jpg (specular)
	var normal_path := "res://assets/models/humans/skins/%s_n.png" % file_name
	var spec_path := "res://assets/models/humans/skins/%s_s.jpg" % file_name
	var has_normal: bool = ResourceLoader.exists(normal_path)
	var has_spec: bool = ResourceLoader.exists(spec_path)
	_material.set_shader_parameter(&"has_skin_normal", has_normal)
	_material.set_shader_parameter(&"has_skin_spec", has_spec)
	if has_normal:
		_material.set_shader_parameter(&"skin_normal", load(normal_path) as Texture2D)
	if has_spec:
		_material.set_shader_parameter(&"skin_spec", load(spec_path) as Texture2D)


func _on_wet_changed(value: float) -> void:
	_wet = value
	_hair_style[&"wet"] = value   # (the shape of wet hair is built in C++: clumps, pointed tips, heavy fall)
	_hair_last_change_ms = Time.get_ticks_msec()
	_hair_retry = 0
	_hair_dirty = true
	_head_hair_material.set_shader_parameter(&"wet", value)


# A small square of the colour for the dropdown's entries.
func _colour_icon(color: Color) -> ImageTexture:
	var image := Image.create(16, 16, false, Image.FORMAT_RGB8)
	image.fill(color)
	return ImageTexture.create_from_image(image)


# The dropdown shows the head hair's colour: its entry, or "Custom" when the colour is not one of HAIR_COLOURS.
func _sync_hair_colour_option() -> void:
	if _hair_colour_option == null:
		return
	var index: int = HAIR_COLOURS.size()
	for i in HAIR_COLOURS.size():
		var swatch: Color = HAIR_COLOURS[i][1]
		if absf(swatch.r - _head_hair_color.r) + absf(swatch.g - _head_hair_color.g) + absf(swatch.b - _head_hair_color.b) < 0.01:
			index = i
			break
	_hair_colour_option.select(index)   # (select() sends no signal)


# Brows and lashes follow the head hair, but light hair has darker brows and lashes (blond brows are not the colour of blond hair).
func _brow_colour_for(head: Color) -> Color:
	var luma: float = head.r * 0.3 + head.g * 0.59 + head.b * 0.11
	var base: Color = head.darkened(0.45 * clampf(luma * 2.2, 0.0, 1.0))
	# a blond head has light brown brows (not olive): move the hue of a yellow towards orange and add some red
	var light: float = clampf(luma * 2.2, 0.0, 1.0)
	return Color(base.r * (1.0 + 0.12 * light), base.g * (1.0 - 0.08 * light), base.b * (1.0 - 0.12 * light))


func _on_head_hair_color_changed(color: Color) -> void:
	_head_hair_color = color
	_sync_hair_colour_option()
	_hair_color = _brow_colour_for(color)   # brows and lashes follow the head hair (a little lighter); the Brows tab picker can still override
	_apply_hair_parameters()
	_update_scalp_colour()
	if _tressfx:
		_hair_dirty = true   # (the scalp layer and the TressFX hair take the colour when they are made)
	_head_hair_material.set_shader_parameter(&"hair_color", color)


func _on_head_hair_density_changed(value: float) -> void:
	_head_hair_density = value
	_head_hair_material.set_shader_parameter(&"density", value)


# Builds the head hair from the body's own mesh in native code (a few ms), as a sibling of the body mesh with the same blend shapes.
# --solo: look at the one hair from close by (the real width is about 1 mm, so it is thin; the camera goes to about 25 cm from it).
func _frame_solo_hair(built: ArrayMesh) -> void:
	var vertices: PackedVector3Array = built.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = built.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var low := Vector3(INF, INF, INF)
	var high := Vector3(-INF, -INF, -INF)
	for i: int in vertices.size():
		if colors[i].b < 0.5:   # the hair itself, not the scalp layer
			low = low.min(vertices[i])
			high = high.max(vertices[i])
	if low.x == INF:
		print("SOLO no hair grown (the one lock was dropped); try another --hair-set=seed:N")
		return
	var centre: Vector3 = (low + high) * 0.5
	print("SOLO hair: %.1f cm long, root at y %.3f" % [(high - low).length() * 100.0, high.y])
	_face_mode = false
	_cam_y = centre.y
	_look_y = centre.y
	_distance = maxf(0.22, (high - low).length() * 2.2)
	if _solo_root:
		# the root is the end of the hair that is nearest the scalp (its first points: lowest strand position in the UV)
		var uvs: PackedVector2Array = built.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
		var root: Vector3 = Vector3.ZERO
		var best: float = INF
		for i: int in vertices.size():
			if colors[i].b < 0.5 and uvs[i].y < best:
				best = uvs[i].y
				root = vertices[i]
		_aim = root + Vector3(0.0, -0.004, 0.0)
		_use_aim = true
		_distance = 0.15
		print("SOLO root at ", root)
	_update_camera()


# The simulation drives the hair through the texture `sim_tex` of its material (the shader moves every hair by its guide).
func _attach_sim() -> void:
	if _sim == null:
		_sim = HairSim.new()
		add_child(_sim)
	if _sim_enabled:
		# looser than the defaults: the pull back to the style is what makes hair look stiff
		_sim.root_stiffness = _hair_root_stiffness
		_sim.bend_stiffness = _hair_bend
		_sim.local_stiffness = _hair_local
		_sim.tip_stiffness = _hair_tip   # (0.004 left the tips floating: slow honey-like swings with no spring)
		_sim.damping = 0.998
		_sim.air_drag = _hair_air
		_sim.max_swing = _hair_max_swing
		_sim.strand_damping = _hair_strand_damp
		_sim.weight = _hair_weight
		_apply_wind()
		_sim.calm_damping = 1.0 - _hair_friction
		if _settle_override >= 0:
			_sim.settle_steps = _settle_override
		for key in _sim_overrides:
			_sim.call("set_" + key, _sim_overrides[key])   # --sim=prop:value,... (tests)
		_sim.hair = _hair_mesh
		_sim.material = _head_hair_material
	else:
		_sim.hair = null
		_head_hair_material.set_shader_parameter(&"use_sim", false)


func _thousands(n: int) -> String:
	var s: String = str(absi(n))
	var out: String = ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


func _effective_target() -> int:
	return maxi(int(float(_target_hairs) * float(HAIR_LODS[_lod][0])), 1500)


func _lod_for_distance(distance: float) -> int:
	var level: int = 0
	for d: float in LOD_DISTANCES:
		if distance > d * (1.0 if level >= _lod else 0.9):   # (a little hysteresis: the level does not flicker at a border)
			level += 1
	return level


# A cost test for several characters: copies of the body and of the current hair mesh in a grid behind and beside the first (the meshes and materials are shared; only the first hair is simulated).
func _make_crowd() -> void:
	for node in _crowd_nodes:
		(node as Node).queue_free()
	_crowd_nodes.clear()
	if _hair_mesh == null or _mesh == null:
		return
	var columns: int = 4
	for index in range(1, _crowd):
		var holder := Node3D.new()
		holder.position = Vector3(float(index % columns - 1) * 0.9 - 0.45, 0.0, -float(index / columns + 1) * 0.9)
		_body.get_parent().add_child(holder)
		var body_copy := MeshInstance3D.new()
		body_copy.mesh = _mesh.mesh
		body_copy.material_override = _mesh.material_override
		body_copy.skeleton = NodePath()
		holder.add_child(body_copy)
		var hair_copy := MeshInstance3D.new()
		hair_copy.mesh = _hair_mesh.mesh
		hair_copy.material_override = _head_hair_material
		holder.add_child(hair_copy)
		_crowd_nodes.append(holder)


func _rebuild_hair() -> void:
	_rebuild_hair_now()   # (starts the build on a worker thread; _finish_hair_task sets _hair_build_ms when it is done)


func _rebuild_hair_now() -> void:
	if _hair_task_id >= 0:
		return   # (one build at a time: the dirty flag stays set, so the next one starts when this one is done)
	_hair_dirty = false
	if not _hair_enabled or _mesh == null or not (_mesh.mesh is ArrayMesh):
		if _hair_mesh != null:
			_hair_mesh.queue_free()
			_hair_mesh = null
		return
	var params: Dictionary = _hair_style.duplicate()
	if not _hair_zones.is_empty():
		params["zones"] = _hair_zones.duplicate(true)   # (the builder reads each lock's settings from the zones its root is in)
	if _hair_preview and int(params.get(&"strands", 0)) > 8:
		params[&"strands"] = maxi(int(params[&"strands"]) / 6, 4)   # (the preview while dragging)
	params["eye_drop"] = HumanHair.default_params_for(_gender)["eye_drop"]
	var lod_row: Array = HAIR_LODS[_lod]
	_head_hair_material.set_shader_parameter(&"scalp_layer", _scalp_arg if _scalp_arg >= 0.0 else maxf(_scalp_layer, 1.0 if _lod > 0 else 0.0))   # (the lower levels have fewer hairs: a solid hair-coloured layer under them keeps the scalp from showing)
	if _lod > 0:
		var cap: int = int(lod_row[1])
		var own: int = int(params.get(&"points", 0))
		params[&"points"] = cap if own < 3 else mini(own, cap)
		params[&"strand_width"] = float(params.get(&"strand_width", 0.0004)) * float(lod_row[2])
		params[&"lock_share"] = pow(float(lod_row[0]), 0.4)   # (a SUBSET of the full hair's follicles: the same guides, so the style does not change between levels; the hairs per lock carry the rest of the reduction)
		if not bool(lod_row[3]):
			params[&"beard"] = 0.0
		params[&"wisps"] = float(params.get(&"wisps", 0.0)) * float(lod_row[4])
	# the beard length is the switch: 0 is shaved (no beard), anything above it covers the whole beard area
	params[&"beard"] = 1.0 if float(params.get(&"beard_length", 0.0)) > 0.00005 else 0.0
	if _gender == "Female":
		params[&"beard"] = 0.0
	# (no cheaper beard preview while a slider moves: the beard builds in ~80 ms, and a 2,500-follicle preview showed an almost empty beard for seconds before the full one came)
	_head_hair_material.set_shader_parameter(&"single_hairs", int(_hair_style.get(&"strands", 0)) > 0)
	if not _hair_preview and int(params.get(&"strands", 0)) > 8:
		params[&"strands"] = clampi(int(round(40.0 * _strand_scale)), 3, 96)   # (every style has the same follicles and the same hairs per follicle)
	var body_data = HumanHair.prepare(_hair_body_mesh())   # (on this thread: it reads the body mesh)
	_hair_task_started_us = Time.get_ticks_usec()
	_hair_task_body = _body
	_hair_task_id = WorkerThreadPool.add_task(_hair_task_run.bind(body_data, params), false, "hair build")
	# the first hair, a capture and a benchmark wait for the result; while the lab runs the old hair stays until the new one is ready (after a gender
	# switch the new body is bald for the build's ~1 s rather than the whole lab freezing for it)
	if (_hair_mesh == null and not _hair_ever_built) or _capture_path != "":
		_finish_hair_task(true)


func _hair_task_run(body_data, params: Dictionary) -> void:
	_hair_task_result = HumanHair.build_arrays(body_data, params)


func _poll_hair_task() -> void:
	if _hair_task_id >= 0 and WorkerThreadPool.is_task_completed(_hair_task_id):
		_finish_hair_task(false)


func _finish_hair_task(wait: bool) -> void:
	if _hair_task_id < 0:
		return
	WorkerThreadPool.wait_for_task_completion(_hair_task_id)
	_hair_task_id = -1
	if _hair_task_body != _body:
		_hair_task_result = {}   # (built for the body before a gender switch: thrown away, and built again for this one)
		_hair_dirty = true
		return
	_hair_ever_built = true
	var built: ArrayMesh = HumanHair.make_mesh(_hair_task_result)
	_hair_task_result = {}
	if _fade_old != null:
		_fade_old.queue_free()   # (a build finished in the middle of a cross-fade: drop the old level)
		_fade_old = null
	var fading: bool = false
	if _hair_mesh != null:
		if _fade_pending and built != null and not _tressfx:
			# keep the old level on screen (static: its own copy of the material without the simulation) and fade it out while the new one fades in
			var old_material := _head_hair_material.duplicate() as ShaderMaterial
			old_material.set_shader_parameter(&"use_sim", false)
			old_material.set_shader_parameter(&"wind", Vector3.ZERO)
			_hair_mesh.material_override = old_material
			_fade_old = _hair_mesh
			fading = true
		else:
			_hair_mesh.queue_free()
		_hair_mesh = null
	_fade_pending = false
	if built == null:
		_hair_info = "LOD %d  Hair: " % _lod + "none (bald)"
		if _sim != null:
			_sim.hair = null
		return
	var strands: int = int(_hair_style.get(&"strands", 0))
	var guides: int = int(built.get_meta(&"hair_guide_count", 0))
	var verts: int = 0
	var biggest_surface: int = 0
	for si: int in built.get_surface_count():
		verts += built.surface_get_array_len(si)
		biggest_surface = maxi(biggest_surface, built.surface_get_array_len(si))
	if biggest_surface > MAX_HAIR_VERTICES and _hair_guard_retry < 6:
		# the engine moves a surface's vertices with one compute group per 64 vertices and the device allows 65,535 groups (4,194,240 vertices a surface): above that the hair fails and the head comes out bald
		# (the builder cuts a big mesh into several surfaces, so this only catches a mesh it could not cut)
		_hair_guard_retry += 1
		_strand_scale = clampf(_strand_scale * float(MAX_HAIR_VERTICES) / float(biggest_surface) * 0.93, 0.08, 3.0)
		print("HUMAN_LAB hair guard: ", verts, " vertices is over the limit, hairs per lock scale -> ", snappedf(_strand_scale, 0.001))
		_hair_info = "Hair: too many vertices (%s), rebuilding with fewer hairs" % _thousands(verts)
		_hair_dirty = true
		return
	_hair_guard_retry = 0
	if strands > 0 and guides > 0:
		# the real number of hairs: every hair is a ribbon of `steps` points (2 vertices each); near the hairline a lock grows fewer hairs than `strands`, so guides x strands overstates it
		var steps_meta: int = maxi(int(built.get_meta(&"hair_render_steps", built.get_meta(&"hair_guide_steps", 1))), 1)
		var head_vertices: int = int(built.get_meta(&"hair_head_vertices", 0))   # (the head hair alone, from the builder: whatever the beard has)
		var real_hairs: int = (head_vertices - 600) / (2 * steps_meta) if head_vertices > 0 else (verts - 600 - int(built.get_meta(&"hair_beard_vertices", 0))) / (2 * steps_meta)   # (the beard is not head hair: counting its vertices made the first build look 25% too hairy and cost a second build)
		_hair_info = "LOD %d  Hair: " % _lod + "%s hairs (%s guides, up to %d each)   %s vertices" % [_thousands(real_hairs), _thousands(guides), strands, _thousands(verts)]
		# aim for the target: when the count is off by more than 8%, learn a better scale and build again (five times at most)
		print("HUMAN_LAB hair count: LOD ", _lod, " real ", real_hairs, " target ", _effective_target(), " scale ", snappedf(_strand_scale, 0.001), " retry ", _hair_retry)
		var tolerance: float = 0.08 if int(round(40.0 * _strand_scale)) >= 12 else 0.3   # (a few hairs per lock: one more or less is a big step, so do not chase the number)
		if not _hair_preview and _hair_retry < 5 and absf(float(real_hairs) / float(_effective_target()) - 1.0) > tolerance:
			var used: int = clampi(int(round(40.0 * _strand_scale)), 3, 96)
			if used < 96 or real_hairs > _effective_target():
				_strand_scale = clampf(_strand_scale * float(_effective_target()) / float(maxi(real_hairs, 1)), 0.08, 3.0)
				_hair_retry += 1
				_hair_dirty = true
		elif absf(float(real_hairs) / float(_effective_target()) - 1.0) <= tolerance:
			_hair_retry = 0
	else:
		_hair_info = "LOD %d  Hair: " % _lod + "ribbon locks, %s vertices" % _thousands(verts)
	_hair_mesh = MeshInstance3D.new()
	_hair_mesh.mesh = built
	if _solo:
		_frame_solo_hair(built)
	_hair_mesh.material_override = _head_hair_material
	_attach_sim()
	_body.add_child(_hair_mesh)
	if fading:
		_fade_t = 0.0
		print("HUMAN_LAB lod cross-fade started, new level ", _lod)
		_hair_mesh.set_instance_shader_parameter(&"lod_fade", 0.0)
	_hair_sway.hair = _hair_mesh # (the swing goes to this mesh's own `sway` instance uniform)
	if _crowd > 1:
		_make_crowd()
	if _tressfx:
		# the same guide strands, drawn and simulated by the TressFX addon instead of ours
		if _tfx_root != null:
			_tfx_root.queue_free()
			_tfx_root = null
		# our own locks are not drawn, but the solid dark scalp layer under them is (TressFX draws only strands: skin would show between them)
		var scalp_only := _head_hair_material.duplicate() as ShaderMaterial
		scalp_only.set_shader_parameter(&"density", 0.0)
		scalp_only.set_shader_parameter(&"use_sim", false)
		scalp_only.set_shader_parameter(&"wind", Vector3.ZERO)
		if float(TressFXBridge.options.get("showours", 0.0)) < 0.5:
			_hair_mesh.material_override = scalp_only   # (--tfx=showours:1 keeps our own ribbons visible too, for an overlay)
		if _sim != null:
			_sim.hair = null
		if _tfx_library:
			# only a dark scalp layer in the library hair's own colour under the strands (no locks of ours): skin would show through the gaps otherwise
			var lib_scalp := _head_hair_material.duplicate() as ShaderMaterial
			lib_scalp.set_shader_parameter(&"hair_color", Color(0.36, 0.11, 0.04))
			lib_scalp.set_shader_parameter(&"density", 0.0)
			lib_scalp.set_shader_parameter(&"use_sim", false)
			lib_scalp.set_shader_parameter(&"wind", Vector3.ZERO)
			_hair_mesh.material_override = lib_scalp
			_tfx_root = TressFXBridge.attach_library(_body, built, _mesh.mesh as ArrayMesh)
		else:
			_tfx_root = TressFXBridge.attach(_body, built, _mesh.mesh as ArrayMesh, _head_hair_color)
		_hair_info = "TressFX: %s strands (guides x 8)" % _thousands(int(built.get_meta(&"hair_guide_count", 0)))
	_apply()
	_hair_build_ms = (Time.get_ticks_usec() - _hair_task_started_us) / 1000.0
	if Time.get_ticks_msec() < _switch_watch_until_ms:
		print("GENDER_SWITCH hair ready after %.0f ms (%d vertices)" % [_hair_build_ms, (built.surface_get_array_len(0) if built != null and built.get_surface_count() > 0 else 0)])
	_upload_scalp(built)
	_update_scalp_colour()
	if _show_follicles:
		_update_follicles()
	if _scalp_debug_shown:
		_update_scalp_debug()
	if _beard_follicles_shown:
		_update_beard_follicles()
	if _beard_area_shown:
		_update_beard_area()


func _on_hair_color_changed(color: Color) -> void:
	_hair_color = color
	_apply_hair_parameters()


func _on_brow_density_changed(value: float) -> void:
	_brow_density = value
	_apply_hair_parameters()


func _on_eye_color_changed(color: Color) -> void:
	_eye_color = color
	_apply_eye_parameters()


func _on_eye_color_other_changed(color: Color) -> void:
	_eye_color_other = color
	_apply_eye_parameters()


func _on_different_eyes_toggled(pressed: bool) -> void:
	_different_eyes = pressed
	_second_eye_row.visible = pressed
	_apply_eye_parameters()


func _on_iris_changed(value: float) -> void:
	_iris_deg = value
	_apply_eye_parameters()


func _on_pupil_changed(value: float) -> void:
	_pupil = value
	_apply_eye_parameters()


func _on_sclera_changed(value: float) -> void:
	_sclera_tint = value
	_apply_eye_parameters()


func _on_veins_changed(value: float) -> void:
	_veins = value
	_apply_eye_parameters()


func _on_muscle_changed(value: float) -> void:
	_muscle = value
	_apply()


func _on_weight_changed(value: float) -> void:
	_weight = value
	_apply()


func _apply() -> void:
	if _mesh == null:
		return
	var tall: float = maxf(_height, 0.0) * HEIGHT_RANGE
	var short: float = maxf(-_height, 0.0) * HEIGHT_RANGE
	var heavy: float = maxf(_weight, 0.0) * WEIGHT_GAIN_HEAVY
	var light: float = maxf(-_weight, 0.0) * WEIGHT_GAIN_LIGHT
	_set_shape(&"height_tall", tall)
	_set_shape(&"height_short", short)
	_set_shape(&"weight_heavy", heavy)
	_set_shape(&"weight_light", light)
	_set_shape(&"muscle_high", maxf(_muscle, 0.0) * MUSCLE_GAIN_HIGH)
	_set_shape(&"muscle_low", maxf(-_muscle, 0.0) * MUSCLE_GAIN_LOW)
	_apply_face_shapes()
	if _cloth_sim and _clothes == "Villager":
		var key: String = _cloth_key({&"height_tall": tall, &"height_short": short, &"weight_heavy": heavy, &"weight_light": light,
			&"muscle_high": maxf(_muscle, 0.0) * MUSCLE_GAIN_HIGH, &"muscle_low": maxf(-_muscle, 0.0) * MUSCLE_GAIN_LOW})
		if key != _cloth_shape_key:
			_cloth_restart_ms = Time.get_ticks_msec() + 400   # (a slider being dragged: wait until it rests)
			for static_piece: MeshInstance3D in [_shirt_mesh, _pants_mesh]:
				if static_piece != null:
					static_piece.visible = true   # (the static clothes follow the slider meanwhile)
			for piece: MeshInstance3D in _cloth_pieces:
				if is_instance_valid(piece):
					piece.visible = false
	# The mesh's own bounding box spans every blend shape, so work the height out from the
	# base height and how far each height shape moves the head (measured in Blender).
	var height_m: float = float(BASE_HEIGHT[_gender]) + tall * HEIGHT_TALL_M + short * -HEIGHT_SHORT_M
	_readout.text = "%s   height %.2f m" % [_gender, height_m]
	if _hair_enabled and _hair_info != "":
		_readout.text += "\n" + _hair_info
	if _face_mode:
		# keep the camera on the eyes: eye height is 0.937 of the base height and moves with the head shapes
		_cam_y = float(BASE_HEIGHT[_gender]) * 0.937 + tall * 0.67 - short * 0.343 + (FACE_HAIR_LIFT if _face_hair else 0.0)
		# the age shapes move the head up/down (eye height from the landmarks: young -0.196 / -0.166 m, old -0.024 / -0.008 m, male / female)
		var age_dy: Dictionary = FACE_AGE_EYE_DY[_gender]
		_cam_y += float(_face_values.get(&"age_young", 0.0)) * float(age_dy["young"]) + float(_face_values.get(&"age_old", 0.0)) * float(age_dy["old"])
		_look_y = _cam_y - (BEARD_LOOK_DROP if _beard_view else 0.0)
		_cam_y = _look_y if _beard_view else _cam_y
		_update_camera()


func _set_shape(shape_name: StringName, value: float) -> void:
	for target: MeshInstance3D in [_mesh, _underwear_mesh, _eyes_mesh, _brows_mesh, _lashes_mesh, _hair_mesh, _body_hair_mesh, _shirt_mesh, _pants_mesh]:
		if target == null:
			continue
		var index: int = target.find_blend_shape_by_name(shape_name)
		if index < 0:
			push_error("missing blend shape " + String(shape_name))
			continue
		target.set_blend_shape_value(index, value)


func _update_camera() -> void:
	if _use_aim:
		# in close on a point: a little above and in front of it, looking at it
		_camera.position = _aim + (Vector3(0.0, 0.035, 0.05) * (_distance / 0.06)).rotated(Vector3.RIGHT, -_pitch)
		_camera.look_at(_aim)
		return
	var centre := Vector3(0.0, _look_y, 0.0)
	if _beard_view:
		# the body turns about its own axis, the beard is in front of it: look at the beard's place (10 cm in front of the axis, a little below the middle of the jaw) so it stays in the middle of the picture whatever the yaw
		centre = Vector3(0.0, _look_y + _beard_look_dy, 0.1).rotated(Vector3.UP, _yaw)
	_camera.position = centre + Vector3(0.0, _cam_y - _look_y, _distance).rotated(Vector3.RIGHT, -_pitch)
	_camera.look_at(centre)


# A debug log for the flashes seen while the body is turned (right-drag, --spin, --osc): every frame of a turn writes one line (time, yaw, camera, background,
# anti-aliasing, rebuilds, the picture's mean brightness and how much it changed), and a frame that jumps is saved as a PNG with the one before it.
# The files go to user://flash_debug (the path is printed and shown in the readout). Off by default: F8 or --flash-log (a turn then costs a screen read-back a frame).
const FLASH_DIR := "user://flash_debug"
const FLASH_JUMP := 6.0   # the mean change (0..255, on a 64 x 40 grey copy) a frame needs to count as a jump
const FLASH_MAX_SAVES := 24
var _flash_log_file: FileAccess = null
var _flash_prev_small: PackedFloat32Array = PackedFloat32Array()
var _flash_prev_image: Image = null
var _flash_saves: int = 0
var _flash_turning_frames: int = 0
var _flash_key_down: bool = false


var _flash_log_on: bool = OS.get_cmdline_user_args().has("--flash-log")   # F8 turns it on / off (off by default: the read-back costs frames)


func _flash_log_step(delta: float) -> void:
	if Input.is_physical_key_pressed(KEY_F8) != _flash_key_down:
		_flash_key_down = not _flash_key_down
		if _flash_key_down:
			_flash_log_on = not _flash_log_on
			if _readout != null:
				_readout.text += "\nFlash log %s (F8)" % ("ON: " + ProjectSettings.globalize_path(FLASH_DIR) if _flash_log_on else "off")
	var turning: bool = _flash_log_on and (Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or (_spin and _spin_time > 3.0 and _spin_time <= 7.0) or _osc_period > 0.0)
	if not turning:
		_flash_prev_small = PackedFloat32Array()
		_flash_prev_image = null
		_flash_turning_frames = 0
		return
	if _flash_log_file == null:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FLASH_DIR))
		_flash_log_file = FileAccess.open(FLASH_DIR + "/flash_log.txt", FileAccess.WRITE)
		if _flash_log_file == null:
			return
		_flash_log_file.store_line("frame\tms\tdelta_ms\tyaw_deg\tpitch_deg\tcam\tbackground\tmsaa\tssaa\ttaa\thair_dirty\thair_task\tlandmarks_dirty\tmean\tchange\tjump")
		var where: String = ProjectSettings.globalize_path(FLASH_DIR)
		print("FLASH_LOG writing to ", where)
		if _readout != null:
			_readout.text += "\nFlash log: " + where
	var image: Image = get_viewport().get_texture().get_image()
	var small: Image = image.duplicate() as Image
	small.resize(64, 40, Image.INTERPOLATE_BILINEAR)
	small.convert(Image.FORMAT_L8)
	var bytes: PackedByteArray = small.get_data()
	var values := PackedFloat32Array()
	values.resize(bytes.size())
	var total: float = 0.0
	for i in bytes.size():
		values[i] = float(bytes[i])
		total += values[i]
	var mean: float = total / maxf(float(bytes.size()), 1.0)
	var change: float = 0.0
	if _flash_prev_small.size() == values.size():
		for i in values.size():
			change += absf(values[i] - _flash_prev_small[i])
		change /= maxf(float(values.size()), 1.0)
	var jump: bool = change > FLASH_JUMP
	var frame: int = Engine.get_process_frames()
	if jump and _flash_saves < FLASH_MAX_SAVES and _flash_prev_image != null:
		_flash_saves += 1
		_flash_prev_image.save_png("%s/jump%02d_frame%d_before.png" % [FLASH_DIR, _flash_saves, frame - 1])
		image.save_png("%s/jump%02d_frame%d_after.png" % [FLASH_DIR, _flash_saves, frame])
	var cam: Vector3 = _camera.global_position if _camera != null else Vector3.ZERO
	_flash_log_file.store_line("%d\t%d\t%.1f\t%.1f\t%.1f\t%.2f,%.2f,%.2f\t%s\t%d\t%d\t%s\t%s\t%s\t%s\t%.1f\t%.2f\t%s" % [
		frame, Time.get_ticks_msec(), delta * 1000.0, rad_to_deg(_yaw), rad_to_deg(_pitch), cam.x, cam.y, cam.z, _background,
		get_viewport().msaa_3d, get_viewport().screen_space_aa, get_viewport().use_taa, _hair_dirty, _hair_task_running_text(), _landmarks_dirty_ms >= 0,
		mean, change, "JUMP" if jump else ""])
	_flash_log_file.flush()
	_flash_prev_small = values
	_flash_prev_image = image
	_flash_turning_frames += 1


func _hair_task_running_text() -> String:
	return "busy" if _hair_task_id >= 0 else "-"


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if (motion.button_mask & MOUSE_BUTTON_MASK_RIGHT) != 0 and _body != null:
			_yaw += motion.relative.x * 0.01
			_body.rotation.y = _yaw
			_pitch = clampf(_pitch + motion.relative.y * 0.01, -0.6, 1.5)   # drag down: look from above (to see the top of the head)
			_update_camera()
	elif event is InputEventMouseButton:
		var wheel := event as InputEventMouseButton
		if _panel != null and _panel.get_global_rect().has_point(wheel.position):
			return
		if wheel.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance = clampf(_distance * 0.9, 0.2, 8.0)
			_update_camera()
		elif wheel.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_distance = clampf(_distance / 0.9, 0.2, 8.0)
			_update_camera()


func _make_fps_label() -> void:
	# frames per second and the time the GPU and CPU spend on a frame: always visible (top right), even with the panel hidden
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	_fps_label = Label.new()
	_fps_label.anchor_left = 1.0
	_fps_label.anchor_right = 1.0
	_fps_label.offset_left = -330.0
	_fps_label.offset_right = -12.0
	_fps_label.offset_top = 8.0
	_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_fps_label.add_theme_color_override(&"font_color", Color(1, 1, 0.6))
	_fps_label.add_theme_color_override(&"font_outline_color", Color(0, 0, 0))
	_fps_label.add_theme_constant_override(&"outline_size", 5)
	layer.add_child(_fps_label)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)


func _update_fps_label(delta: float) -> void:
	_fps_accum += delta
	_fps_frames += 1
	if _fps_accum < 0.5:
		return
	var vp := get_viewport().get_viewport_rid()
	var gpu_ms: float = RenderingServer.viewport_get_measured_render_time_gpu(vp)
	var cpu_ms: float = RenderingServer.viewport_get_measured_render_time_cpu(vp)
	_fps_label_fps = _fps_frames / _fps_accum
	_fps_label.text = "%d fps  (%.1f ms)\nGPU %.1f ms   CPU %.1f ms" % [roundi(_fps_frames / _fps_accum), 1000.0 * _fps_accum / _fps_frames, gpu_ms, cpu_ms]
	_fps_accum = 0.0
	_fps_frames = 0
	if _bench_seconds > 0.0:
		_bench_time += 0.5
		if _bench_time > 3.0: # skip the first 3 s (shader compile, hair build)
			_bench_n += 1
			_bench_gpu += gpu_ms
			_bench_cpu += cpu_ms
			_bench_fps += _fps_label_fps
		if _bench_time >= 3.0 + _bench_seconds:
			print("HUMAN_LAB bench: %s | tip offset %.4f m | build %.0f ms | longest frame %.0f ms | avg %.0f fps  GPU %.2f ms  CPU %.2f ms" % [_hair_info, (_sim.get_mean_tip_offset() if _sim != null else -1.0), _hair_build_ms, _bench_spike, _bench_fps / maxi(_bench_n, 1), _bench_gpu / maxi(_bench_n, 1), _bench_cpu / maxi(_bench_n, 1)])
			get_tree().quit()


func _process(delta: float) -> void:
	_flash_log_step(delta)
	if _cloth_restart_ms >= 0 and Time.get_ticks_msec() >= _cloth_restart_ms:
		_restart_cloth()
	if _switch_gender_arg != "" and not _switch_gender_done and Time.get_ticks_msec() > 2500:
		_switch_gender_done = true
		_on_gender_button(_switch_gender_arg)
	if Time.get_ticks_msec() < _switch_watch_until_ms and delta > 0.05:
		print("GENDER_SWITCH slow frame %.0f ms (hair dirty %s, task %s, landmarks pending %s)" % [delta * 1000.0, _hair_dirty, _hair_task_id >= 0, _landmarks_dirty_ms >= 0])
	if _body_hair_dirty_ms >= 0 and Time.get_ticks_msec() - _body_hair_dirty_ms > 200:
		_body_hair_dirty_ms = -1
		_rebuild_body_hair()
	if _landmarks_dirty_ms >= 0 and Time.get_ticks_msec() - _landmarks_dirty_ms > 150:
		_landmarks_dirty_ms = -1
		if _flash_log_file != null:
			_flash_log_file.store_line("landmarks rebuilt at frame %d" % Engine.get_process_frames())
		_update_landmarks()
	if _fade_old != null:
		_fade_t = minf(1.0, _fade_t + delta / 0.45)
		var shown: float = _fade_hold if _fade_hold >= 0.0 else _fade_t
		_fade_old.set_instance_shader_parameter(&"lod_fade", 1.0 - shown)
		if _hair_mesh != null:
			_hair_mesh.set_instance_shader_parameter(&"lod_fade", shown)
		if _fade_t >= 1.0 and _fade_hold < 0.0:
			_fade_old.queue_free()
			_fade_old = null
	if _lod_switch_to >= 0 and Time.get_ticks_msec() > 4500:
		_lod_forced = _lod_switch_to
		_lod_switch_to = -1
	var wanted_lod: int = _lod_forced if _lod_forced >= 0 else _lod_for_distance(_distance)
	wanted_lod = clampi(wanted_lod, 0, HAIR_LODS.size() - 1)
	if wanted_lod != _lod and _hair_task_id < 0 and _hair_mesh != null:
		_strand_scale = clampf(_strand_scale * float(HAIR_LODS[wanted_lod][0]) / float(HAIR_LODS[_lod][0]), 0.08, 3.0)   # (the first guess for the new level; the build then corrects it)
		_lod = wanted_lod
		_fade_pending = true
		_hair_retry = 0
		_hair_dirty = true
	_slider_label_time += delta
	if _slider_label_time > 0.25:   # a preset or a style change moves sliders without a signal: keep the labels right
		_slider_label_time = 0.0
		for slider_key: StringName in _hair_slider_labels:
			_show_slider_value(slider_key)
	_update_fps_label(delta)
	if _bench_seconds > 0.0 and _bench_time > 2.0 and _bench_rebuilds < 6:
		# --bench: change the hair a few times (like dragging a slider) and keep the longest frame
		_bench_spike = maxf(_bench_spike, delta * 1000.0) if _bench_rebuilds > 0 else 0.0
		_bench_since += delta
		if _bench_since > 0.5:
			_bench_since = 0.0
			_bench_rebuilds += 1
			_hair_style[&"length"] = float(_hair_style[&"length"]) + 0.01
			_hair_dirty = true
	if _osc_period > 0.0 and _body != null:
		_spin_time += delta
		if _spin_time == delta:
			_osc_rng.seed = 7
		if _osc_pause > 0.0:
			_osc_pause -= delta
		elif _osc_t >= _osc_dur:
			# the next turn: 90 to 180 degrees, either way (a little more often to the right), speed set by --osc
			_osc_from = _osc_to
			var angle := _osc_rng.randf_range(PI * 0.5, PI) * (1.0 if _osc_rng.randf() < 0.55 else -1.0)
			_osc_to = _osc_from + angle
			_osc_dur = maxf(absf(angle) / PI * _osc_period, 0.05)
			_osc_t = 0.0
		if _osc_pause <= 0.0 and _osc_t < _osc_dur:
			_osc_t = minf(_osc_t + delta, _osc_dur)
			var k := _osc_t / _osc_dur
			_yaw = lerpf(_osc_from, _osc_to, k * k * (3.0 - 2.0 * k))
			_body.rotation.y = _yaw
			if _osc_t >= _osc_dur:
				_osc_pause = _osc_rng.randf_range(0.0, 0.5) # a short rest before the next turn
	if _spin and _body != null:
		_spin_time += delta
		if _spin_time > 3.0 and _spin_time <= 7.0:
			_yaw = 0.3 + TAU * (_spin_time - 3.0) / 4.0
			_body.rotation.y = _yaw
	_poll_hair_task()
	if _switch_preset != "" and not _switch_done and Time.get_ticks_msec() > 2500:
		_switch_done = true
		_on_hair_preset(_switch_preset)
	# while a hair slider is dragged, rebuild at most as often as the last build allows (it waits 4x as long as the build took), so the frame rate stays up; the last value is always built
	if _hair_dirty and Time.get_ticks_msec() >= _hair_next_build_ms:
		# while a slider is moving, build a cheap preview (a sixth of the hairs); a quarter of a second after the last move, the full hair
		var dragging: bool = Time.get_ticks_msec() - _hair_last_change_ms < 300 and not _beard_only_change   # (a beard change builds the full hair at once: the preview thinned the head hair out while the beard moved)
		_hair_preview = dragging
		_rebuild_hair()
		if dragging:
			_hair_dirty = true   # (the full build still has to come)
		_hair_next_build_ms = Time.get_ticks_msec() + int(_hair_build_ms * (1.5 if dragging else 2.0))
	if _capture_path == "":
		return
	_capture_frames += 1
	if _shake_on_capture and _capture_frames == 3:
		_on_shake_pressed()
	if _sim != null and _capture_path != "" and _capture_frames >= _capture_at - 4 and _capture_frames < _capture_at:
		var bz: Vector3 = _sim.get_busiest_guide()
		print("HUMAN_LAB trace ", _capture_frames, " ", _sim.get_guide_points(int(bz.y)) if bz.y >= 0.0 else [])
	if _capture_frames == _capture_at:
		get_viewport().get_texture().get_image().save_png(_capture_path)
		print("HUMAN_LAB readout: ", _readout.text.replace("\n", " | "))
		if _sim != null:
			print("HUMAN_LAB sim: guides ", _sim.get_guide_count(), " use_sim ", _head_hair_material.get_shader_parameter(&"use_sim"), " tex ", _head_hair_material.get_shader_parameter(&"sim_tex"), " hair ", _sim.hair, " material ", _sim.material, " tip ", _sim.get_mean_tip_vector(), " busiest ", _sim.get_busiest_guide())
		if _sim != null and _sim.hair != null:
			var busy: Vector3 = _sim.get_busiest_guide()
			var mesh_meta: ArrayMesh = (_sim.hair as MeshInstance3D).mesh as ArrayMesh
			if mesh_meta != null and busy.y >= 0.0 and mesh_meta.has_meta(&"hair_guides"):
				var gd: PackedVector3Array = mesh_meta.get_meta(&"hair_guides")
				var st: int = int(mesh_meta.get_meta(&"hair_guide_steps"))
				print("HUMAN_LAB busiest guide root ", gd[int(busy.y) * st], " tip ", gd[int(busy.y) * st + st - 1])
				print("HUMAN_LAB busiest rest ", gd.slice(int(busy.y) * st, int(busy.y) * st + st))
		get_tree().quit()
