"""Headless mobile boot check for live Pages v27.
Confirms: redirect/?v=27 loads game_v27, canvas boots, helpers present,
mobile MID tier (scale≈0.78 / console FPS tier=1), no pageerrors.
Usage: browser_check_v27_boot.py [URL] [OUTDIR]
"""
import sys, asyncio, json, re
from pathlib import Path
from playwright.async_api import async_playwright

URL = sys.argv[1] if len(sys.argv) > 1 else "https://dodosann2024.github.io/stone-skipping-godot/?v=27"
OUT = Path(sys.argv[2] if len(sys.argv) > 2 else "/tmp/v27_boot")
OUT.mkdir(parents=True, exist_ok=True)
W, H = 390, 844


async def touch(cdp, typ, pts):
	await cdp.send("Input.dispatchTouchEvent", {
		"type": typ,
		"touchPoints": [{"x": x, "y": y, "id": i} for i, (x, y) in enumerate(pts)],
	})


async def tap(cdp, page, x, y):
	await touch(cdp, "touchStart", [(x, y)])
	await page.wait_for_timeout(120)
	await touch(cdp, "touchEnd", [])


async def main():
	async with async_playwright() as p:
		b = await p.chromium.launch(
			executable_path="/usr/bin/google-chrome",
			headless=True,
			args=[
				"--use-gl=angle", "--use-angle=swiftshader",
				"--enable-unsafe-swiftshader", "--ignore-gpu-blocklist",
				"--autoplay-policy=user-gesture-required",
			],
		)
		ctx = await b.new_context(
			viewport={"width": W, "height": H},
			device_scale_factor=2,
			is_mobile=True,
			has_touch=True,
			user_agent=(
				"Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) "
				"AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 "
				"Mobile/15E148 Safari/604.1"
			),
		)
		page = await ctx.new_page()
		logs, errors, fails = [], [], []
		page.on("console", lambda m: logs.append(f"[{m.type}] {m.text}"))
		page.on("pageerror", lambda e: errors.append(str(e)))
		page.on("requestfailed", lambda r: fails.append(f"{r.url} {r.failure}"))

		# Force fps overlay so Godot prints tier/scale to console.
		sep = "&" if "?" in URL else "?"
		await page.goto(URL + f"{sep}fps=1", wait_until="load", timeout=180000)
		await page.wait_for_timeout(8000)
		# Wait for Godot canvas / Engine
		for _ in range(60):
			ready = await page.evaluate(
				"""() => !!(window.Engine || document.querySelector('canvas'))"""
			)
			if ready:
				break
			await page.wait_for_timeout(1000)
		await page.wait_for_timeout(25000)

		helpers = await page.evaluate(
			"""() => ({
				unlock: typeof window.__unlockAudio === 'function',
				safe: typeof window.__safeArea === 'function',
				href: location.href,
				canvas: !!document.querySelector('canvas'),
				canvasWH: (() => { const c=document.querySelector('canvas');
					return c ? [c.width, c.height] : null; })(),
			})"""
		)
		cdp = await ctx.new_cdp_session(page)
		await tap(cdp, page, W * 0.5, H * 0.5)
		await page.wait_for_timeout(8000)
		await page.screenshot(path=str(OUT / "boot.png"), full_page=False)

		# Parse Godot FPS console lines: "FPS … tier N … scale S"
		# Mobile starts at MID (tier=1, scale=0.78); adaptive may step down on slow GL.
		samples = []
		for line in logs:
			m = re.search(r"tier\s+(\d+).*scale\s+([0-9.]+)", line)
			if m:
				samples.append((int(m.group(1)), float(m.group(2))))
		tier = samples[-1][0] if samples else None
		scale = samples[-1][1] if samples else None
		first = samples[0] if samples else (None, None)
		# Mobile ladder activated if we ever saw MID (1/0.78) or any non-HIGH tier.
		saw_mid = any(t == 1 and 0.74 <= s <= 0.82 for t, s in samples)
		mobile_on = saw_mid or (first[0] is not None and first[0] >= 1)

		result = {
			"url": helpers["href"],
			"helpers": helpers,
			"tier": tier,
			"scale": scale,
			"first_tier": first[0],
			"first_scale": first[1],
			"samples": samples,
			"pageerrors": errors,
			"reqfails": [f for f in fails if "favicon" not in f][:20],
			"console_error": [l for l in logs if l.startswith("[error]")],
			"booted": bool(helpers.get("canvas")),
			"is_v27": "game_v27" in helpers["href"],
			"mid_ok": mobile_on,
			"saw_mid": saw_mid,
		}
		(OUT / "result.json").write_text(json.dumps(result, indent=2))
		print("RESULT", json.dumps(result, indent=2))
		print("LOG_TAIL:")
		for l in logs[-30:]:
			print(l)
		ok = (
			result["booted"]
			and result["is_v27"]
			and helpers["unlock"]
			and helpers["safe"]
			and result["mid_ok"]
			and not errors
			and not result["console_error"]
		)
		print("PASS" if ok else "FAIL")
		await ctx.close()
		await b.close()
		return 0 if ok else 1


if __name__ == "__main__":
	raise SystemExit(asyncio.run(main()))
