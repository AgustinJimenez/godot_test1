"""Measures how each bake's colour differs from its photograph and writes ColourMatch.FITS (systems/world_gen/colour_match.gd).

Usage: python tools/bark/colour_match.py <folder with the raw bakes allbake_<surface>.png>
Make the raw bakes with square_compare --no-match --surface=<i> --save-bake=<folder>/allbake_<i>.png (all surfaces).
Per surface: the mean per channel, and the strength of the coarse patches (a 3 cm box) and of the fine detail
(the rest) as the photograph's std over the bake's, on the luminance.
"""
import re, sys, os
import numpy as np
from PIL import Image
from scipy.ndimage import uniform_filter

root = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..')
folder = sys.argv[1]
src = open(os.path.join(root, 'tests/manual/world/square_compare.gd')).read()
rows = re.findall(r'\["([^"]+)", "([^"]+)", "([^"]+)", "([^"]*)"\]', src)[:15]
SKIP = {'rock_boulder_dry'}  # (already fitted to the photograph by hand)
KEY_PREFIX = {'plate': 'plate_'}


def load(path):
    return np.asarray(Image.open(path).convert('RGB').resize((1024, 1024), Image.BILINEAR), float) / 255


def parts(a):
    lum = a @ np.array([0.3, 0.59, 0.11])
    low = uniform_filter(lum, 32, mode='wrap')
    return float(low.std()), float((lum - low).std())


out = {}
for i, (label, photo, kind, baked) in enumerate(rows):
    if photo in SKIP:
        continue
    pp = os.path.join(root, 'tools/bark/bark_downloads/%s_diff.jpg' % photo)
    bp = os.path.join(folder, 'allbake_%d.png' % i)
    if not (os.path.exists(pp) and os.path.exists(bp)):
        continue
    a, b = load(pp), load(bp)
    ma, mb = a.reshape(-1, 3).mean(0), b.reshape(-1, 3).mean(0)
    la, da = parts(a)
    lb, db = parts(b)
    low = float(np.clip(la / max(lb, 1e-4), 0.3, 1.6))
    detail = float(np.clip(da / max(db, 1e-4), 0.4, 1.6))
    key = KEY_PREFIX.get(kind, '') + (baked or photo)
    out[key] = (mb, ma / mb, low, detail)
    print(i, key, 'gain', (ma / mb).round(3), 'low %.2f detail %.2f' % (low, detail))

path = os.path.join(root, 'systems/world_gen/colour_match.gd')
text = open(path, newline='').read()
nl = '\r\n' if '\r\n' in text else '\n'
lines = ['const FITS := {']
for key, (mean, gain, low, detail) in out.items():
    lines.append('\t"%s": {"mean": Vector3(%.4f, %.4f, %.4f), "gain": Vector3(%.4f, %.4f, %.4f), "low": %.3f, "detail": %.3f},'
                 % ((key,) + tuple(mean) + tuple(gain) + (low, detail)))
lines.append('}')
block = nl.join(lines)
text = re.sub(r'const FITS := \{.*?\n\}', lambda m: block, text, count=1, flags=re.S)
open(path, 'w', newline='').write(text)
