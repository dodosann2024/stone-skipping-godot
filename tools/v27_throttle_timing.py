#!/usr/bin/env python3
"""Phone-proxy web timing: Chromium 390x844 DPR3 + CPU 4x (+ SwiftShader).
Collects ~120 rAF samples after Godot boots (faster than a full 10s under soft-GL).

Usage:
  python3 tools/v27_throttle_timing.py URL OUT_DIR --tag=walk_path_before
"""
import asyncio
import sys
from pathlib import Path
from playwright.async_api import async_playwright

URL = sys.argv[1]
OUT = Path(sys.argv[2])
TAG = "boot"
for a in sys.argv[3:]:
    if a.startswith("--tag="):
        TAG = a.split("=", 1)[1]
OUT.mkdir(parents=True, exist_ok=True)
W, H, DPR = 390, 844, 3
N_FRAMES = 120  # ~2s at 60fps; under soft-GL still finishes in <2 min


async def main() -> None:
    async with async_playwright() as p:
        browser = await p.chromium.launch(
            executable_path="/usr/bin/google-chrome",
            headless=True,
            args=[
                "--use-gl=angle",
                "--use-angle=swiftshader",
                "--enable-unsafe-swiftshader",
                "--ignore-gpu-blocklist",
                "--autoplay-policy=no-user-gesture-required",
            ],
        )
        ctx = await browser.new_context(
            viewport={"width": W, "height": H},
            device_scale_factor=DPR,
            is_mobile=True,
            has_touch=True,
            user_agent=(
                "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) "
                "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 "
                "Mobile/15E148 Safari/604.1"
            ),
        )
        page = await ctx.new_page()
        logs: list[str] = []
        booted = asyncio.Event()

        def on_console(m):
            t = m.text
            if m.type in ("error", "warning"):
                logs.append(f"[{m.type}] {t}")
            if "Godot Engine" in t or "OpenGL API" in t:
                booted.set()

        page.on("console", on_console)
        page.on("pageerror", lambda e: logs.append(f"[pageerror] {e}"))
        await page.goto(URL, wait_until="load", timeout=180000)
        cdp = await ctx.new_cdp_session(page)
        await cdp.send("Emulation.setCPUThrottlingRate", {"rate": 4})
        try:
            await asyncio.wait_for(booted.wait(), timeout=120)
        except asyncio.TimeoutError:
            logs.append("[warn] Godot boot console line not seen; continuing")
        await page.wait_for_timeout(4000)
        await cdp.send(
            "Input.dispatchTouchEvent",
            {"type": "touchStart", "touchPoints": [{"x": W * 0.5, "y": H * 0.5, "id": 0}]},
        )
        await page.wait_for_timeout(100)
        await cdp.send("Input.dispatchTouchEvent", {"type": "touchEnd", "touchPoints": []})
        await page.wait_for_timeout(2000)

        if "walk" in TAG or "run" in TAG:
            jx, jy = 90, H - 160
            dy = -80 if "walk" in TAG else -120
            await cdp.send(
                "Input.dispatchTouchEvent",
                {"type": "touchStart", "touchPoints": [{"x": jx, "y": jy, "id": 1}]},
            )
            await cdp.send(
                "Input.dispatchTouchEvent",
                {"type": "touchMove", "touchPoints": [{"x": jx, "y": jy + dy, "id": 1}]},
            )
        elif "orbit" in TAG:
            await cdp.send(
                "Input.dispatchTouchEvent",
                {"type": "touchStart", "touchPoints": [{"x": W * 0.75, "y": H * 0.45, "id": 2}]},
            )
            for i in range(20):
                await cdp.send(
                    "Input.dispatchTouchEvent",
                    {
                        "type": "touchMove",
                        "touchPoints": [{"x": W * 0.75 - i * 6, "y": H * 0.45, "id": 2}],
                    },
                )
                await page.wait_for_timeout(40)

        dts = await page.evaluate(
            f"""() => new Promise(resolve => {{
              const out = [];
              let last = performance.now();
              let n = 0;
              const N = {N_FRAMES};
              function tick(now) {{
                out.push(now - last);
                last = now;
                n++;
                if (n < N) requestAnimationFrame(tick);
                else resolve(out);
              }}
              requestAnimationFrame(tick);
            }})"""
        )
        await cdp.send("Input.dispatchTouchEvent", {"type": "touchEnd", "touchPoints": []})
        await page.screenshot(path=str(OUT / f"{TAG}_frame.png"))
        await browser.close()

    dts_f = [float(x) for x in dts[10:]]
    ordered = sorted(dts_f)

    def pct(p: float) -> float:
        return ordered[min(len(ordered) - 1, int(len(ordered) * p))]

    med, p95, p99, mx = pct(0.5), pct(0.95), pct(0.99), ordered[-1]
    hitches = sum(1 for x in dts_f if x > 33.0)
    stats = (
        f"tag={TAG} n={len(dts_f)} note=softGL_cpu4x_short\n"
        f"dt_ms median={med:.3f} p95={p95:.3f} p99={p99:.3f} max={mx:.3f} hitches_gt33={hitches}\n"
    )
    (OUT / f"{TAG}_stats.txt").write_text(stats)
    (OUT / f"{TAG}.csv").write_text(
        "frame,dt_ms\n" + "\n".join(f"{i},{v:.3f}" for i, v in enumerate(dts_f)) + "\n"
    )
    (OUT / f"{TAG}_console.txt").write_text("\n".join(logs))
    print(stats, end="")


asyncio.run(main())
