"""The `weight_heavy` body shape: MakeHuman's max-weight macro plus fat and girth targets (shared by make_bodies.py and make_rig.py).

Why: MakeHuman's weight macro alone is mild (at 1.0 it moves the body at most 2.8 cm male / 2.1 cm female), so the editor pushed it to 3x, and a
pushed shape exaggerates its small local bumps: hard lumps on the flanks with a crease above them, a flat profile, thin arms and legs. The targets
below are MakeHuman core targets (CC0), each made to be used at full weight, fitted by eye against front / side photos of obese bodies. Used at 1.0
in Godot.

Men and women store fat in different places, so each has its own mix:
- male (android, "apple"): a round belly that starts under the chest and pushes forward, deep torso, fuller chest, smooth wide sides, thick upper
  arms, thighs, neck and cheeks;
- female (gynoid, "pear"): wide hips and outer thighs, a big seat, a lower belly, heavier upper arms and bust (cup size up), less on the upper torso.
  (The male thigh fat at full weight bulged above the female knee: her thighs widen with the upper-leg scale targets instead.)
"""

MALE_TARGETS = {
    "stomach-pregnant-incr": 0.5,
    "stomach-navel-down": 0.3,
    "measure-waist-circ-incr": 1.0,
    "measure-hips-circ-incr": 0.6,
    "torso-scale-depth-incr": 0.8,
    "measure-underbust-circ-incr": 0.6,
    "measure-bust-circ-incr": 0.6,
    "buttocks-volume-incr": 0.6,
    "l-upperarm-fat-incr": 1.0, "r-upperarm-fat-incr": 1.0,
    "l-lowerarm-fat-incr": 0.6, "r-lowerarm-fat-incr": 0.6,
    "l-upperleg-fat-incr": 1.0, "r-upperleg-fat-incr": 1.0,
    "l-lowerleg-fat-incr": 0.5, "r-lowerleg-fat-incr": 0.5,
    "neck-double-incr": 0.7,
    "measure-neck-circ-incr": 0.6,
    "l-cheek-volume-incr": 0.5, "r-cheek-volume-incr": 0.5,
}
FEMALE_TARGETS = {
    "stomach-pregnant-incr": 0.35,
    "stomach-navel-down": 0.6,
    "measure-waist-circ-incr": 0.7,
    "measure-hips-circ-incr": 1.0,
    "hip-scale-horiz-incr": 0.5,
    "torso-scale-depth-incr": 0.4,
    "measure-underbust-circ-incr": 0.3,
    "measure-bust-circ-incr": 0.9,
    "buttocks-volume-incr": 1.0,
    "l-upperarm-fat-incr": 1.0, "r-upperarm-fat-incr": 1.0,
    "l-lowerarm-fat-incr": 0.5, "r-lowerarm-fat-incr": 0.5,
    "l-upperleg-scale-horiz-incr": 0.6, "r-upperleg-scale-horiz-incr": 0.6,
    "l-upperleg-scale-depth-incr": 0.5, "r-upperleg-scale-depth-incr": 0.5,
    "l-upperleg-fat-incr": 0.5, "r-upperleg-fat-incr": 0.5,
    "l-lowerleg-fat-incr": 0.4, "r-lowerleg-fat-incr": 0.4,
    "neck-double-incr": 0.5,
    "measure-neck-circ-incr": 0.4,
    "l-cheek-volume-incr": 0.5, "r-cheek-volume-incr": 0.5,
}
FEMALE_MACROS = {"cupsize": 0.7}   # (MakeHuman's cup-size macro, 0.5 in the base: a heavy woman's bust is fuller)


def targets_for(gender):
    """The heavy targets and weights for a gender (MPFB gender: 0 female, 1 male)."""
    return dict(FEMALE_TARGETS if gender < 0.5 else MALE_TARGETS)


def macros_for(gender):
    """Macro values that differ from the base for the heavy shape (on top of weight 1.0)."""
    return dict(FEMALE_MACROS) if gender < 0.5 else {}


def load_heavy(human, gender, target_service):
    """Loads the heavy targets onto an MPFB human made with the weight macro at 1.0 (and macros_for(gender))."""
    for target, weight in targets_for(gender).items():
        path = target_service.target_full_path(target)
        assert path, "target not found: " + target
        target_service.load_target(human, path, weight=weight)
