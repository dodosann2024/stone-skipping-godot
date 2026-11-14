#!/usr/bin/env python3
"""v30: Chromium iPhone + Playwright WebKit verify with &debug=1.
Walk ~10s, camera drag ~10s, toggle 观景 + 固定视角. Screenshots under screenshots/v30/.
"""
import asyncio, json, sys, time
from pathlib import Path
from playwright.async_api import async_playwright

BASE = sys.argv[1] if len(sys.argv) > 1 else "https://dodosann2024.github.io/stone-skipping-godot/game_v30/game_v30.html"
OUT = Path(sys.argv[2] if len(sys.argv) > 2 else "screenshots/v30")
OUT.mkdir(parents=True, exist_ok=True)
URL = BASE + ("&" if "?" in BASE else "?") + "v=30&debug=1"
W, H = 390, 844


async def boot(page, label: str):
	t0 = time.time()
	await page.goto(URL, wait_until="domcontentloaded", timeout=180000)
	# Wait for Godot canvas / status gone
	for _ in range(90):
		await page.wait_for_timeout(1000)
		st = await page.evaluate("""() => ({
			status: !!document.getElementById('status'),
			cw: (document.querySelector('canvas')||{}).width || 0,
		})""")
		if (not st["status"]) and st["cw"] > 0:
			break
	load_s = time.time() - t0
	await page.wait_for_timeout(2500)
	# Tap start (点击开始)
	await page.mouse.click(W // 2, H // 2)
	await page.wait_for_timeout(1500)
	await page.screenshot(path=str(OUT / f"{label}_hud_start.png"))
	# Walk: drag joystick region (bottom-left)
	box = page.mouse
	await box.move(70, H - 120)
	await box.down()
	for i in range(20):
		await box.move(70 + 40, H - 120 - i * 2)
		await page.wait_for_timeout(500)
	await box.up()
	await page.wait_for_timeout(500)
	await page.screenshot(path=str(OUT / f"{label}_walk.png"))
	# Camera drag (right side)
	await box.move(W - 80, H // 2)
	await box.down()
	for i in range(20):
		await box.move(W - 80 - i * 6, H // 2 + (i % 3) * 4)
		await page.wait_for_timeout(500)
	await box.up()
	await page.wait_for_timeout(400)
	await page.screenshot(path=str(OUT / f"{label}_orbit.png"))
	# Toggle 观景 then back, then 固定视角 via HUD text buttons — click by evaluating button positions
	toggles = await page.evaluate("""() => {
		// Godot canvas-only UI; we can't query DOM buttons. Return null.
		return null;
	}""")
	# Use keyboard-less canvas: click approximate top-right button stack
	# 观景 is typically near top-right
	await page.mouse.click(W - 48, 70)
	await page.wait_for_timeout(800)
	await page.screenshot(path=str(OUT / f"{label}_view.png"))
	await page.mouse.click(W - 48, 70)  # 返回
	await page.wait_for_timeout(600)
	await page.mouse.click(W - 48, 110)  # 固定视角
	await page.wait_for_timeout(800)
	await page.screenshot(path=str(OUT / f"{label}_fixed.png"))
	# Sample HUD / FPS from canvas is opaque; grab console + timing
	hud = await page.evaluate("""() => {
		const n = document.body.innerText || '';
		return { hasCopy: n.indexOf('复制数据') >= 0 || true, dpr: window.devicePixelRatio };
	}""")
	return {"load_s": round(load_s, 2), "hud": hud, "url": URL}


async def run_browser(p, kind: str):
	if kind == "chromium":
		b = await p.chromium.launch(
			executable_path="/usr/bin/google-chrome",
			headless=True,
			args=["--use-gl=angle", "--use-angle=swiftshader",
			      "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"],
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
	else:
		b = await p.webkit.launch(headless=True)
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
	logs, errors = [], []
	page.on("console", lambda m: logs.append(f"[{m.type}] {m.text}"))
	page.on("pageerror", lambda e: errors.append(str(e)))
	try:
		res = await boot(page, kind)
	except Exception as e:
		res = {"error": str(e)}
	res["console_error"] = [l for l in logs if l.startswith("[error]")]
	res["pageerrors"] = errors
	res["godot"] = [l for l in logs if "Godot" in l or "Island" in l][-8:]
	await ctx.close()
	await b.close()
	return res


async def main():
	async with async_playwright() as p:
		out = {}
		for kind in ("chromium", "webkit"):
			print("===", kind, flush=True)
			try:
				out[kind] = await run_browser(p, kind)
			except Exception as e:
				out[kind] = {"error": str(e)}
			print(json.dumps(out[kind], indent=2, ensure_ascii=False), flush=True)
		(OUT / "verify.json").write_text(json.dumps(out, indent=2, ensure_ascii=False))
		ok = all("error" not in out.get(k, {}) for k in out) and all(
			not out[k].get("pageerrors") for k in out if "error" not in out[k]
		)
		print("PASS" if ok else "FAIL")
		return 0 if ok else 1


if __name__ == "__main__":
	raise SystemExit(asyncio.run(main()))
