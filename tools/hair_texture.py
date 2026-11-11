"""Strand atlas for the boy's hair cards: textures/hair_strands.png (1024 x 1024, four 256 px wide columns;
v19 doubled it so single strands stay smooth within 20 cm of the camera).

Every column is one card variant, root at the top (v = 0) and tip at the bottom (v = 1):
  0 dense clump, 1 clump with split tips, 2 sparse wisps (outer layer), 3 flyaways.
Strands hardly converge and end at spread-out lengths, each thinning to a fine point over its last third,
so a card's tip frays into separate strands instead of closing into a pointed clump (short cards at the
nape read as scales otherwise).
Channels (linear data, not colour): R per-strand brightness, G depth inside the clump (back strands
darker), B per-strand shift of the highlight, A coverage. Colour is chosen in shaders/hair.gdshader.

python3 tools/hair_texture.py [OUT.png]
"""
import sys
import numpy as np
from PIL import Image

W, H, COLS = 256, 1024, 4
PX = W / 128.0                 # strand widths below are in 128-px-column pixels
rng = np.random.default_rng(17)


def strands(kind):
    """list of strand dicts for one column"""
    out = []
    n = {0: 270, 1: 200, 2: 85, 3: 9}[kind]
    for i in range(n):
        s = {}
        # a tuft, not a tile: strands thin out towards the column's sides, and the ones there start later and
        # end sooner, so neither the root edge nor the sides of a card read as straight lines
        s["x0"] = rng.triangular(0.05, 0.5, 0.95)
        edge = abs(s["x0"] - 0.5) * 2.0
        s["v0"] = rng.uniform(0.0, 0.3) ** 1.2 + 0.12 * edge * rng.random()
        if kind == 3:
            s["v1"] = rng.uniform(0.75, 0.99)
            s["conv"] = rng.uniform(-0.3, 0.3)
            s["wave"] = rng.uniform(0.03, 0.08)
            s["freq"] = rng.uniform(0.8, 2.0)
            s["w"] = rng.uniform(0.8, 1.1)
            s["drift"] = rng.uniform(-0.35, 0.35)
        else:
            # lengths spread over the last half: the clump thins out gradually towards the tip
            u = rng.random()
            s["v1"] = {0: 0.99 - 0.48 * u ** 1.4, 1: 0.98 - 0.5 * u ** 1.2, 2: 0.98 - 0.45 * u}[kind]
            s["conv"] = {0: rng.uniform(0.12, 0.38), 1: rng.uniform(0.05, 0.32), 2: rng.uniform(0.0, 0.25)}[kind]
            s["wave"] = rng.uniform(0.0, 0.025) + (0.03 if kind == 2 else 0.0)
            s["freq"] = rng.uniform(1.5, 4.0)
            s["w"] = rng.uniform(0.9, 1.7)
            s["drift"] = rng.uniform(-0.06, 0.06)
            # split ends: a few strands leave the clump towards the tip
            if kind == 1 and rng.random() < 0.3:
                s["drift"] = rng.choice([-1, 1]) * rng.uniform(0.12, 0.3)
        if kind != 3:
            s["v1"] -= 0.18 * edge ** 1.5 * rng.random()
        s["ph"] = rng.uniform(0, 6.283)
        s["bright"] = rng.uniform(0.0, 1.0)
        s["shift"] = rng.uniform(0.0, 1.0)
        s["depth"] = 0.45 + 0.55 * i / max(n - 1, 1)     # drawn back to front
        out.append(s)
    return out


def column(kind):
    rgba = np.zeros((H, W, 4), np.float32)
    acc_a = np.zeros((H, W), np.float32)
    xs = np.arange(W, dtype=np.float32) + 0.5
    for s in strands(kind):
        v = (np.arange(H, dtype=np.float32) + 0.5) / H
        t = np.clip((v - s["v0"]) / (s["v1"] - s["v0"]), 0.0, 1.0)
        on = (v >= s["v0"]) & (v <= s["v1"])
        conv = s["conv"] * (t ** 1.3)
        x = s["x0"] + (0.5 - s["x0"]) * conv + s["wave"] * np.sin(s["freq"] * 6.283 * t + s["ph"]) * t + s["drift"] * t * t
        xc = x * W
        # thinning to a fine point over the last third, and fading the last bit out
        half = 0.5 * s["w"] * PX * (1.0 - 0.8 * np.clip((t - 0.6) / 0.4, 0.0, 1.0) ** 1.2) * (1.0 - 0.15 * t)
        fade = np.clip(t / 0.2, 0, 1) * np.clip((1.0 - t) / 0.3, 0, 1) ** 1.3
        a = np.clip(half[:, None] + 0.5 - np.abs(xs[None, :] - xc[:, None]), 0.0, 1.0) * (fade * on)[:, None]
        a = np.minimum(a, 1.0) * (0.92 if kind != 3 else 0.85)
        for c, val in ((0, s["bright"]), (1, s["depth"]), (2, s["shift"])):
            rgba[..., c] = rgba[..., c] * (1.0 - a) + val * a
        acc_a = 1.0 - (1.0 - acc_a) * (1.0 - a)
    rgba[..., 3] = acc_a
    # un-premultiply the attribute channels so filtering at strand edges keeps their values
    cov = np.maximum(acc_a, 1e-4)[..., None]
    rgba[..., :3] = np.where(acc_a[..., None] > 1e-3, np.clip(rgba[..., :3] / cov, 0.0, 1.0), 0.5)
    return rgba


def bleed(img):
    """fill fully transparent texels with the nearest strand's attributes (no dark fringes in mips)"""
    rgb = img[..., :3].copy()
    known = img[..., 3] > 0.02
    for _ in range(24):
        if known.all():
            break
        acc = np.zeros_like(rgb)
        cnt = np.zeros(known.shape, np.float32)
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            k = np.roll(known, (dy, dx), (0, 1))
            acc += np.roll(rgb, (dy, dx), (0, 1)) * k[..., None]
            cnt += k
        new = (~known) & (cnt > 0)
        rgb[new] = acc[new] / cnt[new][:, None]
        known = known | new
    img[..., :3] = rgb
    return img


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "textures/hair_strands.png"
    atlas = np.concatenate([bleed(column(k)) for k in range(COLS)], axis=1)
    Image.fromarray((np.clip(atlas, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA").save(out)
    cov = atlas[..., 3].reshape(H, COLS, W).mean(axis=(0, 2))
    print("HAIR_TEX", out, "coverage per column", np.round(cov, 3))


if __name__ == "__main__":
    main()
