"""v20 hat check in the real web build on a phone viewport (Chrome + swiftshader, iPhone UA, touch).
The page runs with ?hatprobe=1: every drawn frame main.gd compares the hat with the seat boy.gd keeps it in on
the head bone and publishes the worst offset per game state in window.__hat. Drives the game with real touches:
walk, sharp joystick turns, run; then, each from a fresh load with &at=..., swipe throws at the dock end
(cheer / oops), the hammock (睡觉), the beach towel (晒太阳) and the bench (坐下 -> 躺下 -> 起来).
Usage: browser_check_v6.py BASE_URL OUTPREFIX [W H]"""
import sys, asyncio, json
from playwright.async_api import async_playwright
URL, OUT = sys.argv[1], sys.argv[2]
W, H = (int(sys.argv[3]), int(sys.argv[4])) if len(sys.argv) > 4 else (390, 844)
S = min(W, H) / 720.0
K = S / (390 / 720.0)
PAD_B = 196.0
HAT = "JSON.stringify(window.__hat || null)"


async def touch(cdp, typ, pts):
    await cdp.send("Input.dispatchTouchEvent", {"type": typ, "touchPoints": [{"x": x, "y": y, "id": i} for i, (x, y) in enumerate(pts)]})


async def tap(cdp, page, x, y):
    await touch(cdp, "touchStart", [(x, y)]); await page.wait_for_timeout(110); await touch(cdp, "touchEnd", [])


async def hat(page):
    return json.loads(await page.evaluate(HAT))


def line(tag, h):
    if not h:
        return f"{tag:24s} no probe data"
    return f"{tag:24s} frames {h['frames']:5d}  worst offset {h['max_mm']:.3f} mm / {h['max_deg']:.4f} deg ({h['worst'] or '-'})  " \
           f"off-head frames outside rest {h['off_head_frames']}  now {h['state']} hat_s {h['hat_s']:.2f}"


async def session(b, at, steps):
    ctx = await b.new_context(viewport={"width": W, "height": H}, device_scale_factor=2, is_mobile=True, has_touch=True,
        user_agent="Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1")
    page = await ctx.new_page()
    logs = []
    page.on("pageerror", lambda e: logs.append(f"[pageerror] {e}"))
    await page.goto(URL + "?hatprobe=1" + (f"&at={at}" if at else ""), wait_until="load", timeout=120000)
    await page.wait_for_timeout(30000)
    cdp = await ctx.new_cdp_session(page)
    await tap(cdp, page, W * 0.5, H * 0.5)
    await page.wait_for_timeout(2500)
    await until(page, lambda h: h["frames"] > 0, 30000)
    print(f"--- {at or 'play'}: act at start '{(await hat(page)).get('act')}'", flush=True)
    out = []
    for name, fn in steps:
        await fn(cdp, page)
        await page.screenshot(path=f"{OUT}_{name}.png")
        h = await hat(page)
        out.append(line(name, h))
        print(out[-1], flush=True)
    h = await hat(page)
    await ctx.close()
    return h, out, logs


async def until(page, cond, timeout):
    """poll window.__hat until cond(h) (game time runs slow under swiftshader)"""
    t = 0
    while t < timeout:
        h = await hat(page)
        if h and cond(h):
            return True
        await page.wait_for_timeout(250); t += 250
    print("   (timed out)", flush=True)
    return False


def stick(dx, dy, hold, cond=None, timeout=90000):
    async def f(cdp, page):
        jx, jy = 185 * S, H - 228 * S
        await touch(cdp, "touchStart", [(jx, jy)])
        for i in range(1, 7):
            await touch(cdp, "touchMove", [(jx + dx * i / 6 * K, jy + dy * i / 6 * K)]); await page.wait_for_timeout(40)
        await page.wait_for_timeout(hold)
        if cond:
            await until(page, cond, timeout)
        await touch(cdp, "touchEnd", [])
        await page.wait_for_timeout(600)
    return f


def zigzag(n=6):
    async def f(cdp, page):
        jx, jy = 185 * S, H - 228 * S
        await touch(cdp, "touchStart", [(jx, jy)])
        for k in range(n):
            sx = 60 if k % 2 == 0 else -60
            for i in range(1, 5):
                await touch(cdp, "touchMove", [(jx + sx * i / 4 * K, jy - 30 * K)]); await page.wait_for_timeout(30)
            await page.wait_for_timeout(900)
        for i in range(1, 5):   # flick back: full reversal
            await touch(cdp, "touchMove", [(jx, jy + 60 * i / 4 * K)]); await page.wait_for_timeout(30)
        await page.wait_for_timeout(1500)
        await touch(cdp, "touchEnd", [])
        await page.wait_for_timeout(600)
    return f


def press(x, y, cond, timeout=60000, after=0):
    async def f(cdp, page):
        await tap(cdp, page, x, y)
        await until(page, cond, timeout)
        await page.wait_for_timeout(after)
    return f


def swipe(dx, dy):
    async def f(cdp, page):
        px, py = W * 0.5, H - PAD_B * S
        await touch(cdp, "touchStart", [(px, py)])
        for i in range(1, 9):
            await touch(cdp, "touchMove", [(px + dx * i / 8 * K, py + dy * i / 8 * K)]); await page.wait_for_timeout(50)
        await page.wait_for_timeout(900)
        await page.screenshot(path=f"{OUT}_charge_{dx}_{dy}.png")
        for i in range(1, 4):
            await touch(cdp, "touchMove", [(px + dx * (1 + i / 8) * K, py + dy * (1 + i / 8) * K)]); await page.wait_for_timeout(16)
        await touch(cdp, "touchEnd", [])
        await until(page, lambda h: h["state"] in ("throw/throw", "throw/react"), 15000)
        await page.wait_for_timeout(700)
        await page.screenshot(path=f"{OUT}_throw_{dx}_{dy}.png")
        await until(page, lambda h: h["state"] == "throw/react", 40000)
        await page.wait_for_timeout(1200)
        await page.screenshot(path=f"{OUT}_react_{dx}_{dy}.png")
        await until(page, lambda h: h["state"] == "throw/idle", 40000)
    return f


ACT = (W - 119 * S, H - 103 * S)
LIE = (W - 119 * S, H - 206 * S)


async def main():
    async with async_playwright() as p:
        b = await p.chromium.launch(executable_path="/usr/bin/google-chrome", headless=True,
            args=["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"])
        res = {}
        play = [("01_walk", stick(0, -36, 3000)), ("02_turns", zigzag()), ("03_turn_back", stick(0, 60, 2500)),
                ("04_run", stick(0, -110, 6000))]
        res["play"] = await session(b, "", play)
        res["dock"] = await session(b, "dock", [
            ("06_throw_mode", press(*ACT, lambda h: h["state"] == "throw/idle", 60000, 2000)),
            ("07_throw_a", swipe(-72, -136)), ("08_throw_b", swipe(10, -150)), ("09_throw_c", swipe(0, -45))])
        res["hammock"] = await session(b, "hammock", [
            ("h1_sleep", press(*ACT, lambda h: h["state"] == "rest/sleep" and h["hat_s"] >= 1.0, 90000, 2500)),
            ("h2_get_up", press(W * 0.5, H * 0.4, lambda h: h["state"].startswith("explore/"), 90000, 1000)),
            ("h3_walk_off", stick(0, -60, 3000))])
        res["towel"] = await session(b, "towel", [
            ("t1_sun", press(*ACT, lambda h: h["state"] == "rest/sun" and h["hat_s"] >= 1.0, 90000, 2500)),
            ("t2_get_up", press(W * 0.5, H * 0.4, lambda h: h["state"].startswith("explore/"), 90000, 1000)),
            ("t3_walk_off", stick(0, -60, 3000))])
        res["bench"] = await session(b, "bench", [
            ("b1_sit", press(*ACT, lambda h: h["state"] == "rest/seat" and h["rest_phase"] == 4, 90000, 1500)),
            ("b2_lie", press(*LIE, lambda h: h["hat_s"] >= 1.0, 90000, 2500)),
            ("b3_get_up", press(*ACT, lambda h: h["state"].startswith("explore/"), 90000, 1000)),
            ("b4_walk_off", stick(0, -60, 3000))])
        print("\n==== hat vs head bone, real web build %dx%d ====" % (W, H))
        for k, (h, out, logs) in res.items():
            print(line(k + " TOTAL", h))
            if h:
                for st, v in sorted(h["states"].items()):
                    print("    %-22s %5d frames  max %.3f mm  hat_s max %.2f" % (st, v[0], v[1], v[2]))
            for l in logs[:5]:
                print("   ", l)
        await b.close()
asyncio.run(main())
