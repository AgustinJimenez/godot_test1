"""A vision-model judge for a fitted surface (AGENT_TASKS/090, step 6): it looks at the photograph and the generated picture and lists
what differs, in a fixed JSON shape, so a loop (or a person) can act on it without opening every picture.

  python judge.py <picture.png> [--what "pitted rock height"] [--out result.json]

The picture is a side-by-side made by compare_torch.py / square_compare (photograph left, generated right; more panels are fine, say so with
--panels "photo | current | fitted"). Two backends, tried in this order:
  1. ANTHROPIC_API_KEY set: the Messages API over HTTPS (no package needed); model from JUDGE_MODEL (default claude-sonnet-5-5).
  2. the `claude` command line (print mode, the Read tool only): uses the logged-in Claude Code account.
Output (printed and written to --out): {"verdict": "close|different|wrong", "score": 0-10, "differences": [{"what", "photo", "generated", "fix"}], "keep": [...]}.
The numbers are a vision model's opinion: use them to rank candidates and to pick what to change next, not as a measurement.
"""
import base64
import json
import os
import re
import subprocess
import sys
import urllib.request

PROMPT = """You are judging a procedural texture against the photograph it must imitate.
The image is a side-by-side: {panels}. It shows {what}.
Compare them as a texture artist would: scale and density of the features, their shapes and edges, the contrast and where the dark and bright
areas sit, the colour, the fine detail, repetition and anything that looks artificial. Be concrete and short.
Reply with ONLY a JSON object, no other text:
{{"verdict": "close" | "different" | "wrong",
  "score": 0-10 (10 = indistinguishable),
  "differences": [{{"what": "the feature", "photo": "how it looks in the photograph", "generated": "how it looks in the generated picture",
                    "fix": "one concrete change to the generator or its numbers"}}],
  "keep": ["what already matches and must not change"]}}
List the 3 to 5 most important differences, most important first."""


def api_judge(path, prompt):
    data = base64.standard_b64encode(open(path, "rb").read()).decode()
    body = {"model": os.environ.get("JUDGE_MODEL", "claude-sonnet-5-5"), "max_tokens": 1500, "messages": [{"role": "user", "content": [
        {"type": "image", "source": {"type": "base64", "media_type": "image/png", "data": data}}, {"type": "text", "text": prompt}]}]}
    request = urllib.request.Request("https://api.anthropic.com/v1/messages", data=json.dumps(body).encode(), headers={
        "x-api-key": os.environ["ANTHROPIC_API_KEY"], "anthropic-version": "2023-06-01", "content-type": "application/json"})
    with urllib.request.urlopen(request, timeout=180) as response:
        return json.load(response)["content"][0]["text"]


def cli_judge(path, prompt):
    command = ["claude", "-p", "Read the image file " + os.path.abspath(path) + " and then answer.\n" + prompt,
               "--allowedTools", "Read", "--output-format", "text"]
    result = subprocess.run(command, capture_output=True, text=True, timeout=300, cwd=os.path.dirname(os.path.abspath(path)))
    if result.returncode != 0:
        raise RuntimeError("claude -p failed: " + (result.stderr or result.stdout)[:500])
    return result.stdout


def judge(path, what="a procedural surface", panels="left: the photograph, right: the generated picture"):
    prompt = PROMPT.format(what=what, panels=panels)
    text = api_judge(path, prompt) if os.environ.get("ANTHROPIC_API_KEY") else cli_judge(path, prompt)
    match = re.search(r"\{.*\}", text, re.S)
    if not match:
        raise ValueError("no JSON in the reply: " + text[:300])
    return json.loads(match.group(0))


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    args = sys.argv[2:]
    option = lambda name, default: args[args.index(name) + 1] if name in args else default
    result = judge(sys.argv[1], option("--what", "a procedural surface"), option("--panels", "left: the photograph, right: the generated picture"))
    text = json.dumps(result, indent=1)
    print(text)
    if "--out" in args:
        open(option("--out", ""), "w").write(text)
