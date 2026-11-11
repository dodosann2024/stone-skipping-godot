"""Tileable fabric micro-structure for the boy's clothes: textures/fabric.png (256 x 256, linear data).

R jersey knit (tank top): columns of V-shaped loops
G linen plain weave (vest): over-under threads with slubs (uneven thickness along the yarn)
B cotton twill (shorts): 2/1 diagonal ribs
A fibre noise (fuzz, colour variation)
Used as height for bump mapping and a little albedo variation in shaders/cloth.gdshader.

python3 tools/fabric_texture.py [OUT.png]
"""
import sys
import numpy as np
from PIL import Image

N = 256
rng = np.random.default_rng(31)
u, v = np.meshgrid((np.arange(N) + 0.5) / N, (np.arange(N) + 0.5) / N)


def tile_noise(cells, octaves=3):
    """tileable value noise in 0..1"""
    out = np.zeros((N, N))
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        c = cells * 2 ** o
        g = rng.random((c, c))
        x = u * c
        y = v * c
        x0 = np.floor(x).astype(int) % c
        y0 = np.floor(y).astype(int) % c
        fx = x - np.floor(x)
        fy = y - np.floor(y)
        fx = fx * fx * (3 - 2 * fx)
        fy = fy * fy * (3 - 2 * fy)
        a = g[y0, x0]
        b = g[y0, (x0 + 1) % c]
        cc = g[(y0 + 1) % c, x0]
        d = g[(y0 + 1) % c, (x0 + 1) % c]
        out += amp * ((a * (1 - fx) + b * fx) * (1 - fy) + (cc * (1 - fx) + d * fx) * fy)
        tot += amp
        amp *= 0.5
    return out / tot


def jersey():
    cols, rows = 32, 40
    x = (u * cols) % 1.0
    y = (v * rows) % 1.0
    hl = np.exp(-((x - (0.27 + 0.18 * y)) / 0.14) ** 2)
    hr = np.exp(-((x - (0.73 - 0.18 * y)) / 0.14) ** 2)
    h = np.maximum(hl, hr) * (0.7 + 0.3 * np.sin(np.pi * y))
    return h * (0.85 + 0.3 * tile_noise(16, 2))


def plain_weave():
    n = 32
    x = u * n
    y = v * n
    i = np.floor(x).astype(int)
    j = np.floor(y).astype(int)
    fx = x % 1.0
    fy = y % 1.0
    slub_w = 0.75 + 0.5 * tile_noise(8, 2)              # thickness along the warp (varies with v)
    slub_f = 0.75 + 0.5 * tile_noise(8, 2).T
    warp = np.cos((fx - 0.5) * np.pi) ** 1.5 * slub_w
    weft = np.cos((fy - 0.5) * np.pi) ** 1.5 * slub_f
    over = ((i + j) % 2) == 0
    # the yarn on top bulges in the middle of its float
    h = np.where(over, warp * (0.75 + 0.25 * np.sin(np.pi * fy)), weft * (0.75 + 0.25 * np.sin(np.pi * fx)))
    return h


def twill():
    n = 48
    x = u * n
    y = v * n
    i = np.floor(x).astype(int)
    j = np.floor(y).astype(int)
    fx = x % 1.0
    fy = y % 1.0
    warp_up = ((i + j) % 3) != 0
    warp = np.cos((fx - 0.5) * np.pi) ** 1.2
    weft = np.cos((fy - 0.5) * np.pi) ** 1.2
    h = np.where(warp_up, warp, weft * 0.8)
    return h * (0.9 + 0.2 * tile_noise(16, 2))


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "textures/fabric.png"
    ch = [jersey(), plain_weave(), twill(), 0.55 * tile_noise(32, 3) + 0.45 * rng.random((N, N))]
    img = np.stack([(c - c.min()) / (c.max() - c.min()) for c in ch], axis=-1)
    Image.fromarray((img * 255 + 0.5).astype(np.uint8), "RGBA").save(out)
    print("FABRIC_TEX", out)


if __name__ == "__main__":
    main()
