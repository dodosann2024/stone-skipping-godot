#!/usr/bin/env python3
"""v26 vs v27 night still composites + numeric match table."""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

OUT = Path(sys.argv[1] if len(sys.argv) > 1 else "screenshots/v27/compare")
OUT.mkdir(parents=True, exist_ok=True)

PAIRS = [
    (
        "beach",
        "screenshots/v26/night_beach_boy.png",
        "screenshots/v27/night_beach.png",
        {
            "feet": (0.62, 0.78, 0.35, 0.65),
            "far": (0.45, 0.58, 0.05, 0.35),
            "torso": (0.42, 0.58, 0.38, 0.62),
        },
    ),
    (
        "campfire",
        "screenshots/v26/night_campfire.png",
        "screenshots/v27/night_campfire.png",
        {
            "feet": (0.70, 0.88, 0.35, 0.70),
            "far": (0.35, 0.50, 0.55, 0.95),
            "torso": (0.40, 0.58, 0.35, 0.65),
        },
    ),
    (
        "forest",
        "screenshots/v26/night_forest_path.png",
        "screenshots/v27/night_forest_path.png",
        {
            "feet": (0.62, 0.78, 0.35, 0.65),
            "far": (0.35, 0.50, 0.55, 0.95),
            "torso": (0.38, 0.55, 0.35, 0.65),
        },
    ),
]


def region_stats(img: np.ndarray, r: tuple[float, float, float, float]) -> tuple[float, float]:
    h, w, _ = img.shape
    y0, y1, x0, x1 = r
    g = img[int(h * y0) : int(h * y1), int(w * x0) : int(w * x1)]
    m = g.mean(axis=(0, 1))
    return float(m.mean()), float(m[0] - m[2])


rows = [
    "shot,region,v26_L,v26_RB,v27_L,v27_RB,L_ratio,RB_delta,boy_ground_v26,boy_ground_v27"
]

for name, a_path, b_path, regions in PAIRS:
    a = np.array(Image.open(a_path).convert("RGB"), dtype=float)
    b = np.array(Image.open(b_path).convert("RGB"), dtype=float)
    ha, wa = a.shape[:2]
    hb, wb = b.shape[:2]
    h = min(ha, hb)
    a_img = Image.fromarray(a.astype(np.uint8)).resize(
        (int(wa * h / ha), h), Image.Resampling.LANCZOS
    )
    b_img = Image.fromarray(b.astype(np.uint8)).resize(
        (int(wb * h / hb), h), Image.Resampling.LANCZOS
    )
    gap = 8
    canvas = Image.new("RGB", (a_img.width + b_img.width + gap, h + 36), (20, 22, 28))
    canvas.paste(a_img, (0, 36))
    canvas.paste(b_img, (a_img.width + gap, 36))
    dr = ImageDraw.Draw(canvas)
    dr.text((8, 8), f"v26 {name}", fill=(220, 220, 230))
    dr.text((a_img.width + gap + 8, 8), f"v27 {name}", fill=(220, 220, 230))
    out_path = OUT / f"night_{name}_v26_vs_v27.png"
    canvas.save(out_path)
    print("WROTE", out_path)

    sa: dict[str, tuple[float, float]] = {}
    sb: dict[str, tuple[float, float]] = {}
    for k, r in regions.items():
        sa[k] = region_stats(a, r)
        sb[k] = region_stats(b, r)
        La, rba = sa[k]
        Lb, rbb = sb[k]
        rows.append(
            f"{name},{k},{La:.1f},{rba:.1f},{Lb:.1f},{rbb:.1f},"
            f"{Lb / max(La, 1):.3f},{rbb - rba:.1f},,"
        )
    bg26 = sa["torso"][0] / max(sa["feet"][0], 1)
    bg27 = sb["torso"][0] / max(sb["feet"][0], 1)
    rows.append(f"{name},boy_ground_ratio,,,,,,,{bg26:.3f},{bg27:.3f}")

table = OUT / "night_match_table.csv"
table.write_text("\n".join(rows) + "\n")
print("WROTE", table)
for r in rows:
    print(r)
