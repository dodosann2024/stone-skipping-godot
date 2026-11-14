"""iPhone emulation + slow-3G throttle boot check for live v29.
Captures mid-load + start screenshots. Usage: v29_throttle_boot.py [URL] [OUTDIR]
"""
import sys, asyncio, time, json
from pathlib import Path
from playwright.async_api import async_playwright

URL = sys.argv[1] if len(sys.argv) > 1 else "https://dodosann2024.github.io/stone-skipping-godot/game_v29/game_v29.html?v=29"
OUT = Path(sys.argv[2] if len(sys.argv) > 2 else "screenshots/v29")
OUT.mkdir(parents=True, exist_ok=True)
W, H = 390, 844


async def main():
	async with async_playwright() as p:
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
		page = await ctx.new_page()
		cdp = await ctx.new_cdp_session(page)
		# Slow 3G-ish: 1.5 Mbps down/up, 300 ms RTT
		await cdp.send("Network.emulateNetworkConditions", {
			"offline": False,
			"latency": 300,
			"downloadThroughput": 1.5 * 1024 * 1024 / 8,
			"uploadThroughput": 1.5 * 1024 * 1024 / 8,
			"connectionType": "cellular3g",
		})
		logs, errors = [], []
		page.on("console", lambda m: logs.append(f"[{m.type}] {m.text}"))
		page.on("pageerror", lambda e: errors.append(str(e)))

		t0 = time.time()
		print(f"goto {URL}", flush=True)
		await page.goto(URL, wait_until="domcontentloaded", timeout=180000)
		# Mid-load screenshot after a short wait (loader should be visible)
		await page.wait_for_timeout(2500)
		await page.screenshot(path=str(OUT / "loading_mid.png"))
		loader = await page.evaluate("""() => ({
			sub: (document.getElementById('load-sub')||{}).textContent || '',
			bytes: (document.getElementById('load-bytes')||{}).textContent || '',
			visible: (document.getElementById('status')||{}).style.visibility,
			retry: (document.getElementById('retry-btn')||{}).style.display,
		})""")
		print("loader", loader, flush=True)

		# Wait until Godot hides status / canvas has content / 点击开始
		reached = False
		for i in range(120):  # up to ~120s under throttle
			await page.wait_for_timeout(1000)
			st = await page.evaluate("""() => ({
				status: !!document.getElementById('status'),
				canvas: !!document.querySelector('canvas'),
				cw: (document.querySelector('canvas')||{}).width || 0,
				notice: (document.getElementById('status-notice')||{}).textContent || '',
				bytes: (document.getElementById('load-bytes')||{}).textContent || '',
			})""")
			elapsed = time.time() - t0
			print(f"t={elapsed:.1f}s status={st['status']} canvas={st['cw']} bytes={st['bytes']!r}", flush=True)
			# status removed => game started
			if (not st["status"]) and st["cw"] > 0:
				reached = True
				break
			if st["notice"]:
				print("NOTICE", st["notice"][:300], flush=True)
				break
		load_s = time.time() - t0
		await page.wait_for_timeout(3000)
		await page.screenshot(path=str(OUT / "start_screen.png"))
		# Check for 点击开始 via yellow/white overlay is canvas-only; rely on status gone + island log
		godot = [l for l in logs if "Godot" in l or "Island" in l or "ERROR" in l or l.startswith("[error]")]
		result = {
			"url": URL,
			"load_seconds": round(load_s, 2),
			"reached_game": reached,
			"pageerrors": errors,
			"console_error": [l for l in logs if l.startswith("[error]")],
			"godotish": godot[-20:],
			"loader_mid": loader,
		}
		(OUT / "throttle_boot.json").write_text(json.dumps(result, indent=2, ensure_ascii=False))
		print(json.dumps(result, indent=2, ensure_ascii=False))
		print("PASS" if reached and not errors and not result["console_error"] else "FAIL")
		await ctx.close()
		await b.close()
		return 0 if reached and not errors else 1


if __name__ == "__main__":
	raise SystemExit(asyncio.run(main()))
