"""Writes a batch_generate.py manifest (E:/repo/unity/unityTest1/Pipeline/wan2gp/batch_generate.py) for the animation pack.

Usage: python tools/gvhmr/make_manifest.py <out.json>
Every clip: one full-body person on a plain white studio floor, static camera, plain clothes, no props unless the action needs one
(GVHMR wants one continuous shot with the whole body in frame). Variants change the manner, not the framing.
Statuses are pending; re-running the batch skips done entries.
"""
import json
import sys

FRAME = ("A person wearing simple, plain neutral clothing, with a plain sleeveless top and trousers, on an empty, seamless white "
         "studio floor. The camera holds a static medium wide shot facing them, framing their whole body from head to feet "
         "throughout, with no cuts and no slow motion. Bright, even, soft studio lighting, no harsh shadows. "
         "{action} The background is a clean, minimal white backdrop with no text, signage or clutter.")

# category -> list of (name, action sentence). Locomotion moves toward / across the camera so the body stays in frame.
CLIPS = {
    "Idle": [
        ("Idle_Relaxed", "They stand relaxed, weight evenly on both feet, arms loose, breathing gently, with tiny natural sways."),
        ("Idle_Alert", "They stand alert with knees slightly bent and hands raised a little, glancing around."),
        ("Idle_Tired", "They stand tired, shoulders slumped, shifting weight from foot to foot and exhaling."),
        ("Idle_LookAround", "They stand and slowly turn their head left and right, looking around curiously, feet planted."),
    ],
    "Walk": [
        ("Walk_Forward", "They walk steadily and calmly toward the camera at a normal pace, arms swinging naturally."),
        ("Walk_Slow", "They walk slowly and carefully toward the camera, cautious steps."),
        ("Walk_Confident", "They walk confidently toward the camera with a relaxed, wide stride."),
        ("Walk_Left", "They walk across the frame from right to left, seen from the side, at a normal pace."),
        ("Walk_Right", "They walk across the frame from left to right, seen from the side, at a normal pace."),
        ("Walk_Backward", "They walk backward away from the camera, facing it, with small careful steps."),
    ],
    "Run": [
        ("Run_Forward", "They jog toward the camera at a steady pace, arms pumping."),
        ("Run_Fast", "They run fast toward the camera in a full sprint, leaning forward."),
        ("Run_Left", "They run across the frame from right to left, seen from the side."),
        ("Run_Right", "They run across the frame from left to right, seen from the side."),
    ],
    "Jump": [
        ("Jump_InPlace", "They crouch slightly, jump straight up with arms swinging, and land softly on both feet."),
        ("Jump_Forward", "They take a step and leap forward, landing on both feet and stopping."),
        ("Jump_Long", "They run two steps and make a long jump forward, landing in a crouch."),
    ],
    "Crouch": [
        ("Crouch_Enter", "They stand, then lower smoothly into a low crouch and hold still."),
        ("Crouch_Idle", "They stay in a low crouch, breathing quietly, looking around."),
        ("Crouch_Walk", "They crouch low and sneak forward toward the camera with small careful steps."),
        ("Crouch_Exit", "They rise from a low crouch to a standing position and relax."),
    ],
    "Turn": [
        ("Turn_Left", "They stand and turn in place to the left, pivoting a quarter turn on their feet, then stop."),
        ("Turn_Right", "They stand and turn in place to the right, pivoting a quarter turn on their feet, then stop."),
        ("Turn_Around", "They stand and turn around in place a half turn with small steps, then stop."),
    ],
    "Climb": [
        ("Climb_Ledge", "They face a low waist-high wall edge, place both hands on top and pull themselves up and over onto it."),
        ("Climb_Vault", "They run two steps and vault over a waist-high wall with a hand on top, landing on the far side."),
    ],
    "Crawl": [
        ("Crawl_Forward", "They crawl forward on their hands and knees toward the camera, one limb at a time."),
        ("Crawl_Low", "They crawl low on their elbows and knees toward the camera, body close to the floor."),
    ],
    "Sword": [
        ("Sword_SlashDown", "They hold a plain straight sword in the right hand and swing it in a strong overhead slash, then recover."),
        ("Sword_SlashSide", "They hold a plain straight sword in the right hand and swing it in a wide horizontal slash, then recover."),
        ("Sword_Thrust", "They hold a plain straight sword in the right hand and lunge forward with a thrust, then step back."),
        ("Sword_Block", "They hold a plain straight sword in the right hand and raise it in a quick defensive block, then lower it."),
    ],
    "Hurt": [
        ("Hurt_Stagger", "They are hit from the front, flinch and stagger back a step, grabbing their chest, then recover."),
        ("Hurt_Fall", "They are struck, stumble backward and drop to one knee, holding their side."),
        ("Hurt_Flinch", "They flinch sharply as if struck on the shoulder, then straighten up."),
    ],
    "Object": [
        ("Object_PickUp", "They bend down, pick up a plain cardboard box from the floor with both hands and hold it against their chest."),
        ("Object_Push", "They push a large plain wooden crate across the floor with both hands, leaning into it."),
        ("Object_Carry", "They carry a plain cardboard box in both arms and walk toward the camera."),
    ],
}

# second pass: retries of the weak/failed clips with sharper wording, plus more variants per category
CLIPS_V2 = {
    "Retry": [
        ("Climb_Ledge2", "A waist-high plain grey stone wall stands in front of them. They step up to it, put both forearms on top, "
                        "kick up one knee, pull their whole body up onto the top of the wall and kneel there."),
        ("Jump_Forward2", "They crouch deeply, then spring forward with a powerful jump, both feet clearly leaving the floor for a "
                          "moment with arms swinging up, and land with both feet in a bent-knee landing."),
        ("Jump_InPlace2", "They bend their knees deeply, then explode upward in a big vertical jump with both feet high off the floor "
                          "and arms thrown up, then land and absorb the impact with bent knees."),
        ("Crouch_Idle2", "From the very first frame they are already in a deep crouch, knees bent low and body lowered, staying in "
                         "the crouch and looking around slowly without standing up."),
        ("Object_Carry2", "They hold a large plain cardboard box against their chest with both arms wrapped around it in front of "
                          "their body and walk slowly toward the camera, carrying it."),
        ("Run_Left2", "They run in a straight line across the frame from right to left at a steady pace, seen from the side, "
                      "feet always touching the floor."),
        ("Crawl_Low2", "They crawl on their hands and knees along the floor toward the camera, torso low, one hand and the opposite "
                       "knee moving together, steady slow rhythm."),
    ],
    "Idle": [
        ("Idle_Stretch", "They stand and stretch, raising both arms overhead, arching slightly and then relaxing the arms down."),
        ("Idle_CheckWatch", "They stand and glance at their left wrist, then look up and shift their weight, bored."),
        ("Idle_Combat", "They stand in a combat-ready stance, knees bent, weight forward, fists raised near the chest, swaying slightly."),
    ],
    "Walk": [
        ("Walk_Limp", "They walk toward the camera with a limp, favouring their right leg, one shoulder dropped."),
        ("Walk_Sneak", "They sneak toward the camera on tiptoe with careful quiet steps, body slightly hunched."),
        ("Walk_Heavy", "They trudge toward the camera with heavy tired steps and hanging arms."),
        ("Walk_Armed", "They walk toward the camera holding a plain straight sword low in the right hand, alert."),
    ],
    "Run": [
        ("Run_Tired", "They jog toward the camera slowly with heavy tired strides, head down."),
        ("Run_Armed", "They run toward the camera holding a plain straight sword in the right hand, arm swinging less."),
    ],
    "Sword": [
        ("Sword_Combo", "They hold a plain straight sword in the right hand and perform a quick two-hit combo: a diagonal slash then a "
                        "back-hand slash, then return to guard."),
        ("Sword_Parry", "They hold a plain straight sword in the right hand and parry sharply to the left then return to guard."),
        ("Sword_Kick", "They hold a plain straight sword in the right hand, kick forward with the right foot and return to guard."),
    ],
    "Hurt": [
        ("Hurt_Knockback", "They are hit hard from the front, are thrown backward a few steps with arms flung out and stumble to a stop."),
        ("Hurt_GrabArm", "They clutch their left upper arm with the right hand, grimace and hunch over, then slowly straighten."),
    ],
    "Object": [
        ("Object_Drag", "They grab a heavy plain sack on the floor with both hands and drag it backward toward the camera, leaning back."),
        ("Object_Throw", "They pick up a small plain ball and throw it forward overhand, following through, then lower the arm."),
        ("Object_OpenDoor", "They reach out, grab a door handle on a plain white door in front of them, pull the door open toward them "
                            "and step back."),
    ],
    "Misc": [
        ("GetUp", "They lie on their back on the floor, then roll over and push themselves up to a standing position."),
        ("Roll", "They run two steps and dive into a forward roll, coming up to a crouch."),
        ("Climb_Ladder", "A plain vertical wooden ladder stands in front of them. They climb up it hand over hand and foot over foot."),
    ],
}

entries = []
if len(sys.argv) > 2 and sys.argv[2] == "v2":
    CLIPS = CLIPS_V2
for category, clips in CLIPS.items():
    for name, action in clips:
        entries.append({
            "name": name, "category": category, "prompt": FRAME.format(action=action),
            "frames": 97, "steps": 8, "resolution": "832x448", "seed": -1, "status": "pending",
        })
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(entries, handle, indent=2)
print("wrote", len(entries), "clips ->", sys.argv[1])
