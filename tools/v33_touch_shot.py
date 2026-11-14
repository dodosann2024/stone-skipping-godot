#!/usr/bin/env python3
"""iPhone-emulated Playwright: real touch drag on the joystick of local game_v33."""
from __future__ import annotations

import asyncio
import http.server
import socketserver
import threading
import time
from pathlib import Path

from playwright.async_api import async_playwright

ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / "docs"
OUT = ROOT / "screenshots" / "v33"
OUT.mkdir(parents=True, exist_ok=True)
W, H = 390, 844


class Handler(http.server.SimpleHTTPRequestHandler):
	def __init__(self, *a, **k):
		super().__init__(*a, directory=str(DOCS), **k)

	def log_message(self, *_a):
		pass


def start_server():
	httpd = socketserver.TCPServer(("127.0.0.1", 0), Handler)
	port = httpd.server_address[1]
	threading.Thread(target=httpd.serve_forever, daemon=True).start()
	return httpd, port


async def wait_ready(page) -> None:
	for _ in range(90):
		await page.wait_for_timeout(1000)
		st = await page.evaluate(
			"""() => {
			const s = document.getElementById('status');
			const vis = s && getComputedStyle(s).visibility !== 'hidden'
				&& getComputedStyle(s).display !== 'none';
			const c = document.querySelector('canvas');
			return { status: !!vis, cw: c ? c.width : 0 };
		}"""
		)
		if (not st["status"]) and st["cw"] > 0:
			break
	await page.wait_for_timeout(800)
	await page.touchscreen.tap(W // 2, H // 2)
	await page.wait_for_timeout(2000)


async def main() -> int:
	httpd, port = start_server()
	url = f"http://127.0.0.1:{port}/game_v33/game_v33.html?v=33&debug=1"
	async with async_playwright() as p:
		b = await p.chromium.launch(
			executable_path="/usr/local/bin/google-chrome",
			headless=True,
			args=[
				"--use-gl=angle",
				"--use-angle=swiftshader",
				"--enable-unsafe-swiftshader",
				"--ignore-gpu-blocklist",
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
		await page.goto(url, wait_until="domcontentloaded", timeout=180000)
		await wait_ready(page)
		await page.screenshot(path=str(OUT / "01_boot_debug.png"))

		jx, jy = int(W * 0.18), int(H * 0.82)
		await page.screenshot(path=str(OUT / "02_before_drag.png"))

		await page.evaluate(
			"""([x, y]) => {
			const c = document.querySelector('canvas');
			const fire = (type, xx, yy, id = 1) => {
				const t = new Touch({
					identifier: id, target: c,
					clientX: xx, clientY: yy, pageX: xx, pageY: yy,
					screenX: xx, screenY: yy, radiusX: 8, radiusY: 8, force: 1,
				});
				const ev = new TouchEvent(type, {
					cancelable: true, bubbles: true,
					touches: type === 'touchend' ? [] : [t],
					targetTouches: type === 'touchend' ? [] : [t],
					changedTouches: [t],
				});
				c.dispatchEvent(ev);
			};
			window.__joyDrag = { fire };
			fire('touchstart', x, y);
		}""",
			[jx, jy],
		)
		t0 = time.time()
		for step in range(1, 9):
			yy = jy - step * 10
			await page.evaluate(
				"""([x, y]) => { window.__joyDrag.fire('touchmove', x, y); }""",
				[jx, yy],
			)
			await page.wait_for_timeout(30)
			if step == 3:
				await page.screenshot(path=str(OUT / "03_drag_early.png"))
			if step == 7:
				await page.screenshot(path=str(OUT / "04_drag_held.png"))

		for _ in range(10):
			await page.evaluate(
				"""([x, y]) => { window.__joyDrag.fire('touchmove', x, y); }""",
				[jx, jy - 80],
			)
			await page.wait_for_timeout(50)
		await page.screenshot(path=str(OUT / "05_drag_moving.png"))

		await page.evaluate(
			"""([x, y]) => { window.__joyDrag.fire('touchend', x, y); }""",
			[jx, jy - 80],
		)
		await page.wait_for_timeout(700)
		await page.screenshot(path=str(OUT / "06_after_release.png"))
		print(f"OK shots→{OUT} drag_span_ms={(time.time() - t0) * 1000:.0f}")
		await b.close()
	httpd.shutdown()
	return 0


if __name__ == "__main__":
	raise SystemExit(asyncio.run(main()))
