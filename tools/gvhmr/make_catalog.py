"""Writes assets/animation/gvhmr_pack/catalog.json (GvhmrPack.catalog) from the clips in the pack and the ratings below.

Usage: python tools/gvhmr/make_catalog.py
Ratings come from AGENT_TASKS/089_gvhmr_animation_pack.md's Results (ok / usable / weak / failed); update RATINGS after a retry.
A clip with no entry in RATINGS is listed as "unrated". Flags per clip name prefix mirror tools/gvhmr/run_clip.py's choices.
"""
import json
import os

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "assets", "animation", "gvhmr_pack")

RATINGS = {
    "ok": ["Idle_Relaxed", "Idle_Alert", "Idle_Tired", "Walk_Slow", "Walk_Backward", "Walk_Right", "Run_Forward", "Run_Fast",
           "Run_Right", "Crouch_Enter", "Crouch_Exit", "Jump_Long", "Turn_Left", "Turn_Right", "Turn_Around",
           "Sword_SlashDown", "Sword_Block", "Sword_Thrust", "Hurt_Flinch", "Object_PickUp",
           "Jump_Forward2", "Jump_InPlace2", "Crouch_Idle2", "Crawl_Low", "Crawl_Forward"],
    "usable": ["Idle_LookAround", "Walk_Forward", "Walk_Confident", "Walk_Left", "Run_Left", "Jump_InPlace", "Crouch_Idle",
               "Crouch_Walk", "Climb_Vault", "Sword_SlashSide", "Hurt_Fall", "Hurt_Stagger",
               "Object_Push", "Object_Carry", "Climb_Ledge2"],
    "weak": ["Jump_Forward", "Object_Carry2"],
    "failed": ["Climb_Ledge"],
}
LOOPING_PREFIXES = ("Idle", "Walk", "Run", "Crouch_Idle", "Crouch_Walk", "Crawl")
IN_PLACE_PREFIXES = ("Idle", "Turn", "Crouch_Idle", "Crouch_Enter", "Crouch_Exit", "Jump_InPlace")
SPEEDS = [("Walk_Slow", 0.9), ("Crouch_Walk", 0.9), ("Crawl", 0.5), ("Walk", 1.4), ("Run_Fast", 5.0), ("Run", 3.6)]
FIST_PREFIXES = ("Sword", "Object")

rating_of = {name: rating for rating, names in RATINGS.items() for name in names}
entries = []
for file in sorted(os.listdir(os.path.join(ROOT, "json"))):
    if not file.endswith(".json") or file.endswith("_contacts.json"):
        continue
    name = file[:-5]
    in_place = name.startswith(IN_PLACE_PREFIXES + LOOPING_PREFIXES)  # (loops are cropped to a cycle and made in place)
    entries.append({
        "name": name,
        "category": name.split("_")[0],
        "rating": rating_of.get(name, "unrated"),
        "loop": name.startswith(LOOPING_PREFIXES),
        "in_place": in_place,
        "speed": next((v for prefix, v in SPEEDS if name.startswith(prefix)), 0.0),  # (m/s the controller should move at)
        "hands": "fist" if name.startswith(FIST_PREFIXES) else "relaxed",
    })
json.dump(entries, open(os.path.join(ROOT, "catalog.json"), "w"), indent=1)
print(len(entries), "clips;", {r: sum(1 for e in entries if e["rating"] == r) for r in ("ok", "usable", "weak", "failed", "unrated")})
