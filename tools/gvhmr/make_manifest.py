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

entries = []
for category, clips in CLIPS.items():
    for name, action in clips:
        entries.append({
            "name": name, "category": category, "prompt": FRAME.format(action=action),
            "frames": 97, "steps": 8, "resolution": "832x448", "seed": -1, "status": "pending",
        })
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(entries, handle, indent=2)
print("wrote", len(entries), "clips ->", sys.argv[1])
