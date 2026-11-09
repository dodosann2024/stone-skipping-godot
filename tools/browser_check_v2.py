"""Headless iPhone-like check: load page, toggle 观景 mode, one-finger orbit, pinch, back to 投石, throw."""
import sys, asyncio
from playwright.async_api import async_playwright
URL, OUT = sys.argv[1], sys.argv[2]
W, H = 390, 844

async def touch(cdp, typ, pts):
    await cdp.send("Input.dispatchTouchEvent", {"type": typ, "touchPoints": [{"x": x, "y": y, "id": i} for i, (x, y) in enumerate(pts)]})

async def main():
    async with async_playwright() as p:
        b = await p.chromium.launch(executable_path="/usr/bin/google-chrome", headless=True,
            args=["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"])
        ctx = await b.new_context(viewport={"width": W, "height": H}, device_scale_factor=2, is_mobile=True, has_touch=True,
            user_agent="Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1")
        page = await ctx.new_page()
        logs = []
        page.on("console", lambda m: logs.append(f"[{m.type}] {m.text}"))
        page.on("pageerror", lambda e: logs.append(f"[pageerror] {e}"))
        page.on("requestfailed", lambda r: logs.append(f"[reqfail] {r.url} {r.failure}"))
        resp = []
        page.on("response", lambda r: resp.append(f"{r.status} {r.url.split('/')[-1]}"))
        await page.goto(URL, wait_until="load", timeout=120000)
        await page.wait_for_timeout(30000)
        cdp = await ctx.new_cdp_session(page)
        await page.screenshot(path=OUT + "_1_loaded.png")
        # tap the mode button (top-right)
        await touch(cdp, "touchStart", [(335, 30)]); await page.wait_for_timeout(120); await touch(cdp, "touchEnd", [])
        await page.wait_for_timeout(2500)
        await page.screenshot(path=OUT + "_2_view_mode.png")
        # one-finger orbit drag
        await touch(cdp, "touchStart", [(300, 450)])
        for i in range(1, 16):
            await touch(cdp, "touchMove", [(300 - i * 14, 450 - i * 3)]); await page.wait_for_timeout(40)
        await touch(cdp, "touchEnd", [])
        await page.wait_for_timeout(2500)
        await page.screenshot(path=OUT + "_3_orbited.png")
        # pinch out (zoom out): fingers move together
        await touch(cdp, "touchStart", [(120, 400), (270, 500)])
        for i in range(1, 12):
            await touch(cdp, "touchMove", [(120 + i * 6, 400 + i * 4), (270 - i * 6, 500 - i * 4)]); await page.wait_for_timeout(40)
        await touch(cdp, "touchEnd", [])
        await page.wait_for_timeout(2500)
        await page.screenshot(path=OUT + "_4_pinched.png")
        # back to throw mode
        await touch(cdp, "touchStart", [(335, 30)]); await page.wait_for_timeout(120); await touch(cdp, "touchEnd", [])
        await page.wait_for_timeout(3000)
        await page.screenshot(path=OUT + "_5_throw_mode.png")
        # rotate back to sea-facing aim and throw: hold ~0.8s
        await touch(cdp, "touchStart", [(195, 600)])
        for i in range(1, 6):
            await touch(cdp, "touchMove", [(195, 600 + i * 2)]); await page.wait_for_timeout(60)
        await page.wait_for_timeout(500)
        await page.screenshot(path=OUT + "_6_aiming.png")
        await touch(cdp, "touchEnd", [])
        await page.wait_for_timeout(1800)
        await page.screenshot(path=OUT + "_7_thrown.png")
        await page.wait_for_timeout(6000)
        await page.screenshot(path=OUT + "_8_after.png")
        print("\n".join(logs))
        print("RESPONSES:", ", ".join(r for r in resp if any(k in r for k in ("index", "?v"))))
        await b.close()
asyncio.run(main())
