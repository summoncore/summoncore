#!/usr/bin/env python3
"""Renders the intro's art without Windows: the same page, patch, sheets and BLP files as render_intro.ps1.

    python3 tools/intro/render_intro.py [--style lines|storybook] [--scenes 1,2,3] [--work DIR] [--png-only]

It reads the page patch and the styles out of render_intro.ps1 (and lines.css), so the two cannot drift apart; takes the
stills with Playwright's Chromium (render_shots.js; needs node and playwright); packs each scene's three frames into a
2048x1024 sheet and writes Media/intro_<n>.blp or intro_l<n>.blp (BLP2, DXT1, no alpha, full mipmap chain). Needs numpy
and Pillow.
"""
import argparse, os, re, struct, subprocess, tempfile
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
SCENES = list(range(1, 33)) + list(range(34, 60))  # 33 is "The Index today", which has no picture of its own
CELL_W, CELL_H, W, H = 1024, 512, 2048, 1024


def build_page(work):
    ps = open(os.path.join(HERE, "render_intro.ps1"), encoding="utf-8-sig").read()
    html = open(os.path.join(HERE, "source.html"), encoding="utf-8").read()
    patch = re.search(r"\$patch = @'\n(.*?)\n'@", ps, re.S).group(1)

    def joined(var):  # a PowerShell '...' + '...' expression, comments skipped
        body = re.search(r"\$" + var + r" = (.*?)\n\$", ps, re.S).group(1)
        out = ""
        for line in body.split("\n"):
            if not line.strip().startswith("#"):
                out += "".join(s.replace("''", "'") for s in re.findall(r"'((?:[^']|'')*)'", line))
        return out

    css = "<style>" + joined("baseCss") + joined("lineCss") + open(os.path.join(HERE, "lines.css")).read() + "</style></head>"
    tail = re.compile(r"update\(0\);\s*requestAnimationFrame\(loop\);\s*\}\)\(\);")
    if not tail.search(html):
        raise SystemExit("source.html changed: could not find the start-up code to patch")
    page = os.path.join(work, "render.html")
    open(page, "w", encoding="utf-8").write(tail.sub(lambda m: patch, html).replace("</head>", css))
    return page


def compose(frames):
    sheet = Image.new("RGB", (W, H), (0, 0, 0))
    for i, path in enumerate(frames):
        img = Image.open(path).convert("RGB")
        # crop the edges, as the PowerShell script does: the wobble filter smears the page background in there
        img = img.crop((8, 6, img.width - 8, img.height - 6)).resize((CELL_W, CELL_H), Image.BICUBIC)
        sheet.paste(img, ((i % 2) * CELL_W, (i // 2) * CELL_H))
    return np.asarray(sheet, dtype=np.int32)


def unpack565(c):
    r, g, b = (c >> 11) & 31, (c >> 5) & 63, c & 31
    return np.stack([(r << 3) | (r >> 2), (g << 2) | (g >> 4), (b << 3) | (b >> 2)], axis=-1)


def dxt1(px):
    """px: h x w x 3 (RGB). The same fit as render_intro.ps1: the block's bounding box, inset a little."""
    h, w = px.shape[:2]
    if w < 4 or h < 4:  # pad tiny levels by edge replication so a block can be read
        px = px[np.minimum(np.arange(4), h - 1)][:, np.minimum(np.arange(4), w - 1)]
        h = w = 4
    blocks = px.reshape(h // 4, 4, w // 4, 4, 3).transpose(0, 2, 1, 3, 4).reshape(-1, 16, 3)
    lo, hi = blocks.min(axis=1), blocks.max(axis=1)
    inset = (hi - lo) >> 4
    top, bottom = np.minimum(255, hi - inset), np.maximum(0, lo + inset)
    pack = lambda c: ((c[:, 0] >> 3) << 11) | ((c[:, 1] >> 2) << 5) | (c[:, 2] >> 3)
    c0, c1 = pack(top), pack(bottom)
    c0, c1 = np.maximum(c0, c1), np.minimum(c0, c1)
    p0, p1 = unpack565(c0), unpack565(c1)
    pal = np.stack([p0, p1, (2 * p0 + p1) // 3, (p0 + 2 * p1) // 3], axis=1)  # n x 4 x 3
    dist = ((blocks[:, :, None, :] - pal[:, None, :, :]) ** 2).sum(axis=-1)  # n x 16 x 4
    best = dist.argmin(axis=-1).astype(np.uint32)
    idx = (best << (2 * np.arange(16, dtype=np.uint32))).sum(axis=1, dtype=np.uint32)
    idx[c0 == c1] = 0
    out = np.zeros(len(blocks), dtype=[("c0", "<u2"), ("c1", "<u2"), ("idx", "<u4")])
    out["c0"], out["c1"], out["idx"] = c0, c1, idx
    return out.tobytes()


def half(px):
    h, w = px.shape[:2]
    nh, nw = max(1, h // 2), max(1, w // 2)
    ys, xs = np.arange(nh) * 2, np.arange(nw) * 2
    y1, x1 = np.minimum(h - 1, ys + 1), np.minimum(w - 1, xs + 1)
    total = px[ys][:, xs] + px[ys][:, x1] + px[y1][:, xs] + px[y1][:, x1]
    return (total + 2) // 4


def write_blp(px, path):
    h, w = px.shape[:2]
    levels = []
    while True:
        levels.append(dxt1(px))
        if px.shape[0] == 1 and px.shape[1] == 1:
            break
        px = half(px)
    header = 4 + 4 + 4 + 4 + 4 + 64 + 64 + 1024
    offsets, off = [], header
    for lv in levels:
        offsets.append(off)
        off += len(lv)
    pad = [0] * (16 - len(levels))
    with open(path, "wb") as f:
        f.write(b"BLP2" + struct.pack("<I4B2I", 1, 2, 0, 0, 1, w, h))  # texture, DXT, no alpha, DXT1, mipmaps
        f.write(struct.pack("<16I", *(offsets + pad)) + struct.pack("<16I", *([len(lv) for lv in levels] + pad)))
        f.write(bytes(1024))  # unused palette
        for lv in levels:
            f.write(lv)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--style", choices=["lines", "storybook"], default="lines")
    ap.add_argument("--scenes", default=",".join(map(str, SCENES)))
    ap.add_argument("--work", default=os.path.join(tempfile.gettempdir(), "summoncore_intro"))
    ap.add_argument("--png-only", action="store_true")
    ap.add_argument("--skip-render", action="store_true")
    a = ap.parse_args()
    os.makedirs(a.work, exist_ok=True)
    scenes = [int(s) for s in re.split(r"[,\s]+", a.scenes) if s]
    if not a.skip_render:
        subprocess.run(["node", os.path.join(HERE, "render_shots.js"), build_page(a.work), a.work, a.style, ",".join(map(str, scenes))],
                       check=True)
    if a.png_only:
        return print("frames are in", a.work)
    prefix = "intro_l" if a.style == "lines" else "intro_"
    for n in scenes:
        frames = [os.path.join(a.work, "%s_s%d_f%d.png" % (a.style, n - 1, f)) for f in range(3)]
        path = os.path.join(ROOT, "Media", "%s%d.blp" % (prefix, n))
        write_blp(compose(frames), path)
        print("%s  %.2f MB" % (os.path.basename(path), os.path.getsize(path) / 1048576))


if __name__ == "__main__":
    main()
