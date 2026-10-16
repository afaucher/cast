"""Generate character concept art with Gemini image generation.

    set GEMINI_API_KEY=...            (PowerShell: $env:GEMINI_API_KEY = "...")
    python tools/concept_art.py                 # every prompt in PROMPTS
    python tools/concept_art.py pebble crew     # just these
    python tools/concept_art.py --n 3 dagna     # 3 variations each

Images land in docs/design/concepts/<name>_<i>.png. The key is read from the
environment only; it is never written anywhere.
"""
import base64
import json
import os
import sys
import urllib.request

MODEL = os.environ.get("GEMINI_IMAGE_MODEL", "gemini-2.5-flash-image")
OUT = os.path.join(os.path.dirname(__file__), "..", "docs", "design", "concepts")

STYLE = (
    "Hand-inked comic book illustration, gritty and textured, bold confident black ink lines, "
    "cross-hatched shadows, painted muted color with worn and weathered materials, warm amber "
    "underlighting as if lit from glowing cracks in the floor, cool shadows. Characterful, slightly "
    "exaggerated proportions (about 4 heads tall), chunky and grounded, readable silhouette. "
    "Game character concept art. No text, no logos, no chef hats, no aprons, no kitchen items."
)
SHEET = "Full-body character turnaround sheet: front, three-quarter and back views side by side on a plain warm grey background."

CREW = (
    "A scrappy crew of hired contract sorcerers from different races: a hulking living-stone golem, "
    "a stout bearded dwarf woman with a heavy hammer, a lanky human archer-wizard in a crooked hat with "
    "a taped-up wand and bow, and an empty suit of battered armor with a dark void where the face should be."
)

PROMPTS = {
    "pebble": SHEET + " Pebble: a hulking golem made of pale sandstone boulders with moss growing on its "
              "shoulders and back, small head, huge stone fists, carries a round boulder on its shoulder to bowl "
              "at enemies, a dented work hard hat and a strip of reflective tape as crew gear. Gentle giant.",
    "dagna": SHEET + " Dagna: a short, very wide dwarf woman, huge braided ginger beard, faded denim work "
             "clothes with leather straps, a dented hard hat pushed back, a massive two-handed sledgehammer "
             "that she spins in a whirlwind. Grumpy and competent.",
    "larkin": SHEET + " Larkin: a lanky, nervous human archer-wizard, huge crooked floppy wizard hat with a "
              "headlamp strapped to it, patched plum coat, a bow made from bent tent poles, quiver of mismatched "
              "arrows, a wand wrapped in duct tape.",
    "sir_rattles": SHEET + " Sir Rattles: a suit of battered, tarnished, mismatched plate armor with nobody inside, "
                   "the helmet floats slightly above the collar over a pitch-dark empty void, mustard yellow tabard "
                   "and plume, dented kite shield, notched sword. Pompous and loyal.",
    "crew": CREW + " Group shot of all four standing together, full bodies, in a warm-lit luxury underground "
            "bunker with dark slate hexagonal floor tiles whose seams glow molten amber, wooden crates around.",
    "crew_iso": CREW + " Shown small from a high isometric game camera (about 60 degrees down), fighting little "
                "imp demons on dark slate hexagonal floor tiles with glowing amber seams, wooden crates as raised "
                "platforms. Diablo-like action game screenshot mockup, clear readable silhouettes at small size.",
}


def generate(name: str, prompt: str, index: int, key: str) -> str:
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{MODEL}:generateContent"
    body = {
        "contents": [{"parts": [{"text": STYLE + " " + prompt}]}],
        "generationConfig": {"responseModalities": ["IMAGE", "TEXT"]},
    }
    req = urllib.request.Request(url, data=json.dumps(body).encode(), method="POST",
                                 headers={"Content-Type": "application/json", "x-goog-api-key": key})
    with urllib.request.urlopen(req, timeout=180) as r:
        data = json.load(r)
    for cand in data.get("candidates", []):
        for part in cand.get("content", {}).get("parts", []):
            inline = part.get("inlineData") or part.get("inline_data")
            if inline and inline.get("data"):
                path = os.path.join(OUT, f"{name}_{index}.png")
                with open(path, "wb") as f:
                    f.write(base64.b64decode(inline["data"]))
                return path
    raise RuntimeError(f"no image returned for {name}: {json.dumps(data)[:400]}")


def main(argv: list) -> int:
    key = os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY")
    if not key:
        print("Set GEMINI_API_KEY first.", file=sys.stderr)
        return 2
    n = 1
    if "--n" in argv:
        i = argv.index("--n")
        n = int(argv[i + 1])
        del argv[i:i + 2]
    names = argv or list(PROMPTS)
    os.makedirs(OUT, exist_ok=True)
    for name in names:
        for i in range(n):
            try:
                print("wrote", generate(name, PROMPTS[name], i, key))
            except Exception as e:  # keep going: one failed prompt shouldn't stop the batch
                print(f"FAILED {name} #{i}: {e}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
