#!/usr/bin/env python3
"""Leaf textures for the bushes (CC0, drawn here from scratch).

textures/leaf_cluster.png: two twigs of slender pointed leaves side by side (left / right half of the
image), RGB nearly white-green so each instance's colour tints it, A = leaf coverage. The midrib and the
edge are a little darker, the tips a little lighter, the leaves further back a little darker.

    python3 tools/make_leaves.py
"""
import math
import random
from PIL import Image, ImageDraw, ImageFilter

S = 4                 # supersampling
W, H = 512, 256
OUT = "textures/leaf_cluster.png"


def leaf(dr, base, ang, length, width, shade, rnd):
    """one lanceolate leaf from `base` pointing at `ang`, drawn as a polygon with a midrib"""
    ca, sa = math.cos(ang), math.sin(ang)
    pts_l, pts_r = [], []
    n = 14
    for i in range(n + 1):
        t = i / n
        # widest a third of the way up, a drawn-out tip
        w = width * (math.sin(math.pi * min(1.0, t * 1.15)) ** 0.8) * (1.0 - 0.25 * t)
        bend = 0.08 * length * t * t * rnd
        x = t * length
        pts_l.append((x, w * 0.5 + bend))
        pts_r.append((x, -w * 0.5 + bend))
    poly = pts_l + pts_r[::-1]
    def tr(p):
        return (base[0] + (p[0] * ca - p[1] * sa) * S, base[1] + (p[0] * sa + p[1] * ca) * S)
    c = int(200 * shade), int(235 * shade), int(185 * shade)
    dr.polygon([tr(p) for p in poly], fill=c + (255,))
    # lighter towards the tip, darker midrib
    for i in range(6):
        t0 = 0.55 + i * 0.07
        seg = [p for p in poly if p[0] >= t0 * length]
        if len(seg) > 2:
            k = min(1.0, shade * (1.03 + i * 0.012))
            dr.polygon([tr(p) for p in seg], fill=(int(205 * k), int(240 * k), int(190 * k), 255))
    rib = [tr((t * length * 0.95, 0.08 * length * t * t * rnd)) for t in [i / 10 for i in range(11)]]
    dr.line(rib, fill=(int(150 * shade), int(185 * shade), int(130 * shade), 255), width=max(1, int(1.2 * S)))
    dr.line([tr(p) for p in poly] + [tr(poly[0])], fill=(int(180 * shade), int(215 * shade), int(165 * shade), 255), width=S)


def twig(dr, ox, seed):
    rnd = random.Random(seed)
    cx, by = ox + 128 * S, 246 * S
    stems = []
    main = [(cx + math.sin(i / 11 * 2.2 + seed) * 8 * S, by - i / 11 * 170 * S) for i in range(12)]
    stems.append((main, 1.0))
    # two side twigs forking off low and spreading out
    for side, at in [(-1, 4), (1, 6)]:
        p0 = main[at]
        ang = -math.pi / 2 + side * rnd.uniform(0.7, 0.95)
        pts = [(p0[0] + math.cos(ang) * i / 7 * 95 * S, p0[1] + math.sin(ang) * i / 7 * 95 * S - (i / 7) ** 2 * 18 * S) for i in range(8)]
        stems.append((pts, 0.8))
    leaves = []
    for pts, sc in stems:
        n = len(pts)
        for i in range(int(14 * sc)):
            t = 0.15 + 0.85 * i / max(1, int(14 * sc) - 1)
            p = pts[min(int(t * (n - 1)), n - 1)]
            q = pts[min(int(t * (n - 1)) + 1, n - 1)]
            d = math.atan2(q[1] - p[1], q[0] - p[0]) if q != p else -math.pi / 2
            side = 1 if i % 2 else -1
            ang = d + side * rnd.uniform(0.75, 1.25) * (1.15 - 0.45 * t)
            length = rnd.uniform(52, 70) * sc * (1.0 - 0.3 * t)
            width = length * rnd.uniform(0.24, 0.32)
            leaves.append((rnd.random(), p, ang, length, width, rnd.uniform(0.74, 1.0), side * rnd.uniform(0.4, 1.0)))
        leaves.append((0.99, pts[-1], math.atan2(pts[-1][1] - pts[-2][1], pts[-1][0] - pts[-2][0]), 50 * sc, 14 * sc, 1.0, 0.3))
    for pts, sc in stems:
        dr.line(pts, fill=(120, 100, 75, 255), width=int(3 * S * sc))
    for _, p, ang, length, width, shade, bend in sorted(leaves):
        leaf(dr, p, ang, length, width, shade, bend)


def main():
    im = Image.new("RGBA", (W * S, H * S), (150, 175, 130, 0))
    dr = ImageDraw.Draw(im)
    twig(dr, 0, 3)
    twig(dr, 256 * S, 11)
    im = im.resize((W, H), Image.LANCZOS)
    # bleed the leaf colour into the transparent texels so mipmaps / filtering do not halo dark
    rgb = im.convert("RGB").filter(ImageFilter.MaxFilter(5))
    a = im.getchannel("A")
    bg = Image.merge("RGBA", (*rgb.split(), Image.new("L", im.size, 0)))
    bg.paste(im, (0, 0), a)
    bg.putalpha(a)
    bg.save(OUT)
    print("wrote", OUT, im.size)


if __name__ == "__main__":
    main()
