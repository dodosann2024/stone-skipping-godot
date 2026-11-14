#!/usr/bin/env python3
"""Plot boy/camera per-frame deltas from screenshots/v26/timing/*.csv"""
from __future__ import annotations

import csv
import glob
import os
import statistics

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt

ROOT = "/workspace/screenshots/v26/timing"


def load(path: str):
    frames, boy, cam = [], [], []
    with open(path, newline="") as f:
        r = csv.DictReader(f)
        for row in r:
            frames.append(int(row["frame"]))
            boy.append(float(row["boy_ds"]))
            cam.append(float(row["cam_ds"]))
    return frames, boy, cam


def main() -> None:
    os.makedirs(ROOT, exist_ok=True)
    csvs = sorted(glob.glob(os.path.join(ROOT, "*.csv")))
    if not csvs:
        raise SystemExit("no csv")
    summary = []
    for path in csvs:
        frames, boy, cam = load(path)
        base = os.path.basename(path).replace(".csv", "")
        fig, ax = plt.subplots(2, 1, figsize=(9, 5), sharex=True)
        ax[0].plot(frames, boy, lw=0.9, color="#1f6feb")
        ax[0].set_ylabel("boy screen Δpx")
        ax[0].set_title(base)
        ax[1].plot(frames, cam, lw=0.9, color="#d97706")
        ax[1].set_ylabel("camera Δm")
        ax[1].set_xlabel("frame")
        fig.tight_layout()
        out = os.path.join(ROOT, base + ".png")
        fig.savefig(out, dpi=120)
        plt.close(fig)
        b = [x for x in boy if x > 0]
        c = [x for x in cam if x > 0]
        def ratio(xs):
            if not xs:
                return 0.0, 0.0, 0.0
            med = statistics.median(xs)
            mx = max(xs)
            return med, mx, mx / max(med, 1e-9)
        bm, bx, br = ratio(b)
        cm, cx, cr = ratio(c)
        line = f"{base}: boy med={bm:.3f} max={bx:.3f} max/med={br:.2f} | cam med={cm:.4f} max={cx:.4f} max/med={cr:.2f}"
        summary.append(line)
        print(line)
    with open(os.path.join(ROOT, "summary.txt"), "w") as f:
        f.write("\n".join(summary) + "\n")


if __name__ == "__main__":
    main()
