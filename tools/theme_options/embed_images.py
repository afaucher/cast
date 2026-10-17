"""Make the theme-option pages self-contained: every `url(shots/NAME.png)` becomes `var(--img-NAME)`, and a
<style id="embedded-images"> block at the end of <head> defines each variable as a JPEG data URI (max 1280 wide).
Idempotent: re-run after re-rendering the shots.

    python tools/theme_options/embed_images.py tools/theme_options/menus.html tools/theme_options/backdrops.html
"""
import base64
import io
import os
import re
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
SHOTS = os.path.join(HERE, "shots")
BEGIN = '<style id="embedded-images">'
END = "</style><!--/embedded-images-->"


def data_uri(name: str, max_w: int) -> str:
    im = Image.open(os.path.join(SHOTS, name + ".png")).convert("RGB")
    if im.width > max_w:
        im = im.resize((max_w, round(im.height * max_w / im.width)), Image.LANCZOS)
    buf = io.BytesIO()
    im.save(buf, "JPEG", quality=80, optimize=True, progressive=True)
    return "data:image/jpeg;base64," + base64.b64encode(buf.getvalue()).decode("ascii")


def process(path: str) -> None:
    with open(path, encoding="utf-8") as f:
        html = f.read()
    html = re.sub(r"url\(shots/([A-Za-z0-9_]+)\.png\)", r"var(--img-\1)", html)
    names = sorted(set(re.findall(r"var\(--img-([A-Za-z0-9_]+)\)", html)))
    html = re.sub(re.escape(BEGIN) + r".*?" + re.escape(END), "", html, flags=re.S)
    rules = []
    for n in names:
        max_w = 520 if n.startswith("crop_") else 1280
        rules.append("--img-%s:url(%s);" % (n, data_uri(n, max_w)))
    block = BEGIN + ":root{" + "".join(rules) + "}" + END
    html = html.replace("</head>", block + "\n</head>", 1)
    with open(path, "w", encoding="utf-8") as f:
        f.write(html)
    print("%s: %d images, %.1f MB" % (os.path.basename(path), len(names), len(html) / 1e6))


if __name__ == "__main__":
    for p in sys.argv[1:]:
        process(p)
