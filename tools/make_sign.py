"""Bakes the dock signpost board: weathered grey-brown planks, cracks, a nail, and a charcoal doodle of a kid
on a dock skipping a stone (no text). Top half = front, bottom half = back (plain weathered wood).
Run: python3 tools/make_sign.py  ->  textures/sign_board.png"""
import math, os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
W, H = 512, 192          # one face
rng = np.random.default_rng(20261110)


def vnoise(shape, scale, seed):
    r = np.random.default_rng(seed)
    gh, gw = int(shape[0] / scale[0]) + 3, int(shape[1] / scale[1]) + 3
    g = r.random((gh, gw))
    y = np.arange(shape[0])[:, None] / scale[0]
    x = np.arange(shape[1])[None, :] / scale[1]
    iy, ix = np.floor(y).astype(int), np.floor(x).astype(int)
    fy, fx = y - iy, x - ix
    fy, fx = fy * fy * (3 - 2 * fy), fx * fx * (3 - 2 * fx)
    a, b = g[iy, ix], g[iy, ix + 1]
    c, d = g[iy + 1, ix], g[iy + 1, ix + 1]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


def wood(seed, h=H, w=W):
    yy, xx = np.mgrid[0:h, 0:w].astype(float)
    warp = vnoise((h, w), (40, 160), seed) * 9.0 + vnoise((h, w), (12, 50), seed + 1) * 2.5
    grain = np.sin((yy + warp) * 0.55) * 0.5 + 0.5
    grain = grain ** 3
    fine = vnoise((h, w), (1.5, 30), seed + 2)
    blotch = vnoise((h, w), (50, 90), seed + 3)
    # faded, sun-bleached grey-brown with darker late wood lines and grey weathered patches
    base = np.array([0.56, 0.51, 0.44])
    dark = np.array([0.33, 0.28, 0.23])
    grey = np.array([0.66, 0.65, 0.62])
    col = base[None, None, :] * (1 - 0.55 * grain[..., None]) + dark[None, None, :] * 0.55 * grain[..., None]
    col = col * (0.88 + 0.2 * fine[..., None])
    col = col * (1 - 0.45 * blotch[..., None]) + grey[None, None, :] * 0.45 * blotch[..., None]
    # planks: two boards with a dark seam
    seam = np.exp(-((yy - h * 0.52) / 1.6) ** 2)
    col *= (1 - 0.6 * seam[..., None])
    # darker, dirtier edges
    ex = np.minimum(xx, w - 1 - xx) / 26.0
    ey = np.minimum(yy, h - 1 - yy) / 16.0
    edge = np.clip(np.minimum(ex, ey), 0, 1)
    col *= (0.7 + 0.3 * edge[..., None])
    # a knot
    kx, ky = w * 0.18, h * 0.27
    r = np.hypot((xx - kx) / 1.9, yy - ky)
    knot = np.clip(1 - r / 9, 0, 1) + 0.35 * (np.sin(r * 1.3) * 0.5 + 0.5) * np.clip(1 - r / 20, 0, 1)
    col = col * (1 - 0.5 * knot[..., None]) + dark[None, None, :] * 0.5 * knot[..., None]
    return np.clip(col, 0, 1)


def to_img(a):
    return Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8), "RGB")


def stroke(d, pts, w, col):
    for a, b in zip(pts, pts[1:]):
        d.line([a, b], fill=col, width=w)
    for p in pts:
        d.ellipse([p[0] - w / 2, p[1] - w / 2, p[0] + w / 2, p[1] + w / 2], fill=col)


def wobble(pts, amt, seed):
    r = np.random.default_rng(seed)
    return [(x + r.normal(0, amt), y + r.normal(0, amt)) for x, y in pts]


def doodle(img):
    """charcoal doodle drawn on a separate layer, then roughened so it reads as drawn on wood"""
    lay = Image.new("L", img.size, 0)
    d = ImageDraw.Draw(lay)
    ink = 235
    # water: wavy lines
    for k, yb in enumerate([160, 173]):
        pts = [(x, yb + 2.5 * math.sin(x * 0.08 + k * 1.7)) for x in range(168 + k * 20, 486 - k * 16, 4)]
        stroke(d, wobble(pts, 0.4, 10 + k), 3, ink)
    # dock: deck plank and posts going into the water
    stroke(d, wobble([(30, 128), (166, 126)], 0.6, 20), 6, ink)
    stroke(d, wobble([(30, 137), (166, 135)], 0.6, 21), 3, ink)
    for px in (44, 100, 156):
        stroke(d, wobble([(px, 137), (px + 1, 178)], 0.6, px), 5, ink)
    # the kid, mid-throw, side-on to the water: stride, body leaning in, throwing arm reaching forward
    S = 1.35
    ox, oy = 96, 124          # front foot on the deck

    def P(x, y):
        return (ox + x * S, oy + y * S)
    hx, hy = P(4, -64)
    hr = 9 * S
    d.ellipse([hx - hr, hy - hr, hx + hr, hy + hr], outline=ink, width=4)
    stroke(d, [P(-11, -71), P(18, -73)], 4, ink)                                   # hat brim
    stroke(d, [P(-3, -72), P(-1, -79), P(9, -79), P(11, -73)], 4, ink)
    hip = P(-6, -26)
    stroke(d, wobble([P(2, -55), P(-1, -42), hip], 0.3, 31), 5, ink)              # body leaning in
    stroke(d, wobble([hip, P(6, -14), P(12, -1)], 0.3, 32), 5, ink)               # front leg
    stroke(d, wobble([hip, P(-17, -14), P(-30, -2)], 0.3, 33), 5, ink)            # back leg, on the toes
    sh = P(1, -48)
    stroke(d, wobble([sh, P(17, -44), P(36, -42)], 0.3, 34), 5, ink)              # throwing arm reaching forward
    stroke(d, wobble([sh, P(-13, -54), P(-24, -62)], 0.3, 35), 5, ink)            # other arm back for balance
    # stone just left the hand, then skip arcs shrinking towards the horizon with splash ticks
    sx0, sy0 = P(43, -42)
    d.ellipse([sx0 - 4, sy0 - 4, sx0 + 4, sy0 + 4], fill=ink)
    water = 156
    arcs = [(sx0 + 4, 74, 0), (None, 66, 30), (None, 54, 20), (None, 42, 12), (None, 32, 7), (None, 24, 4)]
    x = arcs[0][0]
    for i, (_, wdt, ht) in enumerate(arcs):
        pts = []
        for k in range(17):
            u = k / 16
            if i == 0:
                y = sy0 + (water - sy0) * u * u - 10 * math.sin(math.pi * u)
            else:
                y = water - ht * math.sin(math.pi * u)
            pts.append((x + wdt * u, y))
        for k in range(0, 16, 2):
            stroke(d, [pts[k], pts[k + 1]], 3, ink)      # dashed flight path
        x += wdt
        for sg in (-1, 1):
            stroke(d, [(x + sg * 2, water - 1), (x + sg * 8, water - 9)], 3, ink)
    # a little sun in the corner
    sx, sy = 440, 40
    d.ellipse([sx - 14, sy - 14, sx + 14, sy + 14], outline=ink, width=3)
    for k in range(8):
        a = k * math.pi / 4 + 0.2
        stroke(d, [(sx + math.cos(a) * 20, sy + math.sin(a) * 20), (sx + math.cos(a) * 28, sy + math.sin(a) * 28)], 3, ink)
    # roughen: charcoal skips on the grain
    m = np.asarray(lay).astype(float) / 255.0
    tooth = vnoise(m.shape, (1.2, 4.0), 77)
    m = m * np.clip(0.55 + 0.7 * tooth, 0, 1)
    m = np.asarray(Image.fromarray((m * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.5))).astype(float) / 255.0
    a = np.asarray(img).astype(float) / 255.0
    charcoal = np.array([0.1, 0.08, 0.07])
    a = a * (1 - 0.85 * m[..., None]) + charcoal * 0.85 * m[..., None]
    return to_img(a)


def cracks(img, seed, nail_holes):
    d = ImageDraw.Draw(img)
    r = np.random.default_rng(seed)
    # a long split along the grain from the broken right end, and a short one at the chipped corner
    for (x, y, dx, n) in [(W - 4, 112, -1, 26), (W - 50, 8, -1, 9), (8, 150, 1, 7)]:
        pts = [(x, y)]
        for i in range(n):
            x += dx * r.uniform(6, 12)
            y += r.normal(0, 1.6)
            pts.append((x, y))
        for i, (a, b) in enumerate(zip(pts, pts[1:])):
            wdt = max(1, int(3.2 * (1 - i / n)) + 1)
            d.line([a, b], fill=(28, 22, 18), width=wdt)
    for (nx, ny, loose) in nail_holes:
        if loose:
            d.ellipse([nx - 4, ny - 4, nx + 4, ny + 4], fill=(20, 16, 13))
        else:
            # rust halo, then the nail head
            for k in range(10, 3, -1):
                c = (int(120 - k * 4), int(70 - k * 3), int(40 - k * 2))
                d.ellipse([nx - k, ny - k * 0.8, nx + k, ny + k * 1.3], fill=c)
            d.ellipse([nx - 5, ny - 5, nx + 5, ny + 5], fill=(70, 66, 62))
            d.ellipse([nx - 3, ny - 4, nx + 2, ny + 1], fill=(130, 126, 120))
    return img


def main():
    front = to_img(wood(5))
    front = doodle(front)
    front = cracks(front, 9, [(30, 40, False), (30, 150, True)])
    back = to_img(wood(17))
    back = cracks(back, 11, [(W - 30, 40, False), (W - 30, 150, True)])
    out = Image.new("RGB", (W, H * 2))
    out.paste(front, (0, 0))
    out.paste(back, (0, H))
    os.makedirs(os.path.join(ROOT, "textures"), exist_ok=True)
    out.save(os.path.join(ROOT, "textures", "sign_board.png"), optimize=True)
    print("wrote textures/sign_board.png")


if __name__ == "__main__":
    main()
