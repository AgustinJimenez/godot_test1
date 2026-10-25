"""Review sheet and journal for an AGENT that judges a fitted surface (AGENT_TASKS/090). No model is called from here: the agent (Claude Code,
or a person) looks at the picture itself, answers the checklist, and records the verdict, so the loop costs nothing extra and needs no key.

  python review.py sheet <surface> [picture]    labelled sheet (photo | generated, header cut off) + the checklist, printed with the picture path
  python review.py record <surface> <score 0-10> "<what differs, most important first>" ["<what to keep>"]   append to the journal
  python review.py history <surface>            the journal for a surface (newest last): did the last change help?

The sheet defaults to the last `pipeline.py match` picture (E:/Temp/tx/n<index>.png). The journal is tools/bark/fits/review_log.jsonl
(one JSON object per line: time, surface, score, differences, keep, git head). An agent should: make the sheet, Read the png, answer the
checklist honestly (a score of 7 or more means "would pass for the photograph at a glance"), record it, change ONE thing, rebuild, review again,
and stop when the score stops rising twice in a row.
"""
import json
import os
import subprocess
import sys
import time

import cv2

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
LOG = os.path.join(ROOT, "tools", "bark", "fits", "review_log.jsonl")
PICTURES = os.environ.get("PIPELINE_OUT", "E:/Temp/tx")
CHECKLIST = """Checklist (answer each in one line, photograph vs generated):
 1. Scale and density of the main features (plates, flakes, stones): same size and count?
 2. Shape and edges: same outline (angular/round, long/short), crisp or soft, cracks thin or fat, open or closed?
 3. Relief: do they read as raised and stepped, or flat? Where are the deepest darks?
 4. Contrast and large-scale layout: bright and dark areas where the photograph has them, or an even wash / a repeating tile?
 5. Colour: hue, saturation and spread (one tone or several), stains, lichen, patches.
 6. Fine detail: grain, pits, specks: same amount and size, or noise/confetti?
 7. Anything that looks artificial at a glance (tiling, grid, blobs, stripes).
 Then: score 0-10, the 3 most important differences (most important first, each with one concrete change), and what must not change."""


def head():
    try:
        return subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=ROOT, capture_output=True, text=True).stdout.strip()
    except OSError:
        return ""


def sheet(surface, picture=None):
    sys.path.insert(0, os.path.join(ROOT, "tools", "bark"))
    import pipeline  # (for the surface index)
    picture = picture or "%s/n%d.png" % (PICTURES, pipeline.SURFACES[surface][1])
    image = cv2.imread(picture)
    if image is None:
        sys.exit("no picture at " + picture + " (run `python tools/bark/pipeline.py match %s` first)" % surface)
    image = image[75:] if image.shape[0] > 800 and image.shape[1] > 1500 else image  # (square_compare's UI header)
    out = "%s/review_%s.png" % (PICTURES, surface)
    width = image.shape[1]
    for text, x in (("PHOTOGRAPH", 10), ("GENERATED", width // 2 + 30)):
        cv2.putText(image, text, (x, 28), cv2.FONT_HERSHEY_SIMPLEX, 0.9, (255, 255, 255), 4)
        cv2.putText(image, text, (x, 28), cv2.FONT_HERSHEY_SIMPLEX, 0.9, (0, 0, 0), 1)
    cv2.imwrite(out, image)
    print("REVIEW SHEET:", out)
    print(CHECKLIST)
    last = history(surface, quiet=True)
    if last:
        print("\nLast review of this surface: score %s at %s: %s" % (last["score"], last["head"], last["differences"]))
    return out


def record(surface, score, differences, keep=""):
    entry = {"time": time.strftime("%Y-%m-%d %H:%M:%S"), "surface": surface, "score": float(score), "differences": differences, "keep": keep, "head": head()}
    with open(LOG, "a", encoding="utf-8") as handle:
        handle.write(json.dumps(entry) + "\n")
    print("recorded:", entry["score"], "for", surface)


def history(surface, quiet=False):
    if not os.path.exists(LOG):
        return None if quiet else print("no journal yet")
    rows = [json.loads(line) for line in open(LOG, encoding="utf-8") if line.strip()]
    rows = [r for r in rows if r["surface"] == surface]
    if quiet:
        return rows[-1] if rows else None
    for r in rows:
        print("%s  score %-4s %s  %s" % (r["time"], r["score"], r["head"], r["differences"]))
    if len(rows) >= 2:
        print("trend: %+.1f since the previous review" % (rows[-1]["score"] - rows[-2]["score"]))


if __name__ == "__main__":
    if len(sys.argv) < 3 or sys.argv[1] not in ("sheet", "record", "history"):
        print(__doc__)
        sys.exit(1)
    if sys.argv[1] == "sheet":
        sheet(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else None)
    elif sys.argv[1] == "record":
        record(sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5] if len(sys.argv) > 5 else "")
    else:
        history(sys.argv[2])
