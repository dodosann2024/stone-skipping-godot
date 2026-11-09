import sys, asyncio
from playwright.async_api import async_playwright
URL = sys.argv[1]
OUT = sys.argv[2]
async def main():
    async with async_playwright() as p:
        b = await p.chromium.launch(executable_path="/usr/bin/google-chrome", headless=True,
            args=["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"])
        ctx = await b.new_context(viewport={"width": 390, "height": 844}, device_scale_factor=2, is_mobile=True, has_touch=True,
            user_agent="Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1")
        page = await ctx.new_page()
        logs = []
        page.on("console", lambda m: logs.append(f"[{m.type}] {m.text}"))
        page.on("pageerror", lambda e: logs.append(f"[pageerror] {e}"))
        page.on("requestfailed", lambda r: logs.append(f"[reqfail] {r.url} {r.failure}"))
        await page.goto(URL, wait_until="load", timeout=120000)
        await page.wait_for_timeout(25000)
        await page.screenshot(path=OUT + "_loaded.png")
        # simulate a throw: press, drag a little, hold, release
        await page.mouse.move(195, 500)
        await page.mouse.down()
        await page.mouse.move(185, 490, steps=5)
        await page.wait_for_timeout(700)
        await page.screenshot(path=OUT + "_aiming.png")
        await page.mouse.up()
        await page.wait_for_timeout(1500)
        await page.screenshot(path=OUT + "_thrown.png")
        await page.wait_for_timeout(5000)
        await page.screenshot(path=OUT + "_after.png")
        print("\n".join(logs))
        await b.close()
asyncio.run(main())
