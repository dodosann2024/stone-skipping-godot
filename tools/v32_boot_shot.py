#!/usr/bin/env python3
"""Boot + debug HUD still of local game_v32."""
from __future__ import annotations

import asyncio
import http.server
import socketserver
import threading
from pathlib import Path

from playwright.async_api import async_playwright

ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / "docs"
OUT = ROOT / "screenshots" / "v32"
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
	t = threading.Thread(target=httpd.serve_forever, daemon=True)
	t.start()
	return httpd, port


async def main() -> int:
	httpd, port = start_server()
	url = f"http://127.0.0.1:{port}/game_v32/game_v32.html?v=32&debug=1"
	async with async_playwright() as p:
		b = await p.chromium.launch(
			executable_path="/usr/local/bin/google-chrome",
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
		await page.goto(url, wait_until="domcontentloaded", timeout=180000)
		for _ in range(90):
			await page.wait_for_timeout(1000)
			st = await page.evaluate("""() => ({
				status: !!(document.getElementById('status') &&
					getComputedStyle(document.getElementById('status')).visibility !== 'hidden'),
				cw: (document.querySelector('canvas')||{}).width || 0,
			})""")
			if (not st["status"]) and st["cw"] > 0:
				break
		await page.wait_for_timeout(1500)
		await page.mouse.click(W // 2, H // 2)
		await page.wait_for_timeout(2500)
		await page.screenshot(path=str(OUT / "boot_debug.png"))
		# Nudge stick region for a short walk pose.
		await page.mouse.move(int(W * 0.14), int(H * 0.86))
		await page.mouse.down()
		await page.mouse.move(int(W * 0.14), int(H * 0.70), steps=8)
		await page.wait_for_timeout(1800)
		await page.screenshot(path=str(OUT / "walk_stick.png"))
		await page.mouse.up()
		await page.wait_for_timeout(800)
		await page.screenshot(path=str(OUT / "after_walk.png"))
		await b.close()
	httpd.shutdown()
	print("OK", OUT)
	return 0


if __name__ == "__main__":
	raise SystemExit(asyncio.run(main()))
