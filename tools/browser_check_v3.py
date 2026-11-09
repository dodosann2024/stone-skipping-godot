"""Headless iPhone-like check for v3: tap-to-start audio unlock (AudioContext state), sound toggle,
view mode orbit/pinch, back to throw, throw. Usage: browser_check_v3.py URL OUTPREFIX"""
import sys, asyncio, json
from playwright.async_api import async_playwright
URL, OUT = sys.argv[1], sys.argv[2]
W, H = 390, 844
INIT = """
(() => {
  window.__ctxs = [];
  for (const name of ['AudioContext', 'webkitAudioContext']) {
    const C = window[name];
    if (!C) continue;
    const W = function(...a) { const c = new C(...a); window.__ctxs.push(c); return c; };
    W.prototype = C.prototype;
    Object.setPrototypeOf(W, C);
    window[name] = W;
  }
})();
"""
STATE = "JSON.stringify(window.__ctxs.map(c => ({state: c.state, rate: c.sampleRate, t: Math.round(c.currentTime*10)/10})))"

async def touch(cdp, typ, pts):
    await cdp.send("Input.dispatchTouchEvent", {"type": typ, "touchPoints": [{"x": x, "y": y, "id": i} for i, (x, y) in enumerate(pts)]})

async def tap(cdp, page, x, y):
    await touch(cdp, "touchStart", [(x, y)]); await page.wait_for_timeout(110); await touch(cdp, "touchEnd", [])

async def main():
    async with async_playwright() as p:
        b = await p.chromium.launch(executable_path="/usr/bin/google-chrome", headless=True,
            args=["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"])
        ctx = await b.new_context(viewport={"width": W, "height": H}, device_scale_factor=2, is_mobile=True, has_touch=True,
            user_agent="Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1")
        await ctx.add_init_script(INIT)
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
        print("AUDIO before tap:", await page.evaluate(STATE))
        await page.screenshot(path=OUT + "_1_tap_to_start.png")
        await tap(cdp, page, 195, 420)
        await page.wait_for_timeout(2500)
        print("AUDIO after tap:", await page.evaluate(STATE))
        await page.screenshot(path=OUT + "_2_started.png")
        await tap(cdp, page, 335, 68)   # sound off
        await page.wait_for_timeout(1500)
        await page.screenshot(path=OUT + "_3_sound_off.png")
        print("AUDIO after mute:", await page.evaluate(STATE))
        await tap(cdp, page, 335, 68)   # sound on again
        await page.wait_for_timeout(1500)
        print("AUDIO after unmute:", await page.evaluate(STATE))
        await tap(cdp, page, 335, 30)   # view mode
        await page.wait_for_timeout(2500)
        await touch(cdp, "touchStart", [(300, 450)])
        for i in range(1, 16):
            await touch(cdp, "touchMove", [(300 - i * 14, 450 - i * 3)]); await page.wait_for_timeout(40)
        await touch(cdp, "touchEnd", [])
        await page.wait_for_timeout(2000)
        await page.screenshot(path=OUT + "_4_view_orbit.png")
        await touch(cdp, "touchStart", [(120, 400), (270, 500)])
        for i in range(1, 12):
            await touch(cdp, "touchMove", [(120 + i * 6, 400 + i * 4), (270 - i * 6, 500 - i * 4)]); await page.wait_for_timeout(40)
        await touch(cdp, "touchEnd", [])
        await page.wait_for_timeout(2000)
        await page.screenshot(path=OUT + "_5_pinched.png")
        await tap(cdp, page, 335, 30)   # back to throw
        await page.wait_for_timeout(3000)
        await page.screenshot(path=OUT + "_6_throw_mode.png")
        await touch(cdp, "touchStart", [(195, 600)])
        for i in range(1, 6):
            await touch(cdp, "touchMove", [(195, 600 + i * 2)]); await page.wait_for_timeout(60)
        await page.wait_for_timeout(500)
        await page.screenshot(path=OUT + "_7_charging.png")
        await touch(cdp, "touchEnd", [])
        await page.wait_for_timeout(350)
        await page.screenshot(path=OUT + "_8_thrown.png")
        await page.wait_for_timeout(7000)
        await page.screenshot(path=OUT + "_9_after.png")
        print("AUDIO end:", await page.evaluate(STATE))
        print("\n".join(logs))
        print("RESPONSES:", ", ".join(r for r in resp if any(k in r for k in ("game_v3", "index", "?v"))))
        await b.close()
asyncio.run(main())
