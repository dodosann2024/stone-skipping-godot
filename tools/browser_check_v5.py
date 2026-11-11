"""Headless iPhone-like check for v15 (swipe throws; otherwise as v4; Chrome + swiftshader, autoplay policy = user gesture required).
Proves that sound is really produced, not just that the AudioContext is 'running':
  * counts AudioBufferSourceNode.start() calls with real (non 1-sample) buffers
  * taps everything connected to ctx.destination into an AnalyserNode and measures RMS.
Then walks with the virtual joystick, runs to the dock end, enters throw mode, switches to half-kneeling,
throws by swipe, pushes the elevation slider to a steep launch, cancels a swipe, and leaves the dock. Usage: browser_check_v5.py URL OUTPREFIX [W H]
(v19: any CSS viewport, e.g. 375 667 / 320 568 for an iPhone SE: touch points are placed in UI units from the
edge each control is anchored to, the way main.gd lays them out at 720 units across the short side)"""
import sys, asyncio, json, math
from playwright.async_api import async_playwright
URL, OUT = sys.argv[1], sys.argv[2]
PAD_B, EL_R, KNOB_B = 196.0, 165.0, 241.5  # UI units from the bottom / right: stone pad centre, elevation slider column, its knob at 4 deg
W, H = (int(sys.argv[3]), int(sys.argv[4])) if len(sys.argv) > 4 else (390, 844)
S = min(W, H) / 720.0          # CSS px per UI unit
K = S / (390 / 720.0)          # gesture lengths relative to the 390 x 844 originals
INIT = """
(() => {
  window.__t = {ctxs: [], starts: 0, realStarts: 0, an: []};
  const T = window.__t;
  for (const name of ['AudioContext', 'webkitAudioContext']) {
    const C = window[name];
    if (!C) continue;
    const Wr = function(...a) { const c = new C(...a); T.ctxs.push(c); return c; };
    Wr.prototype = C.prototype;
    Object.setPrototypeOf(Wr, C);
    window[name] = Wr;
  }
  const st = AudioBufferSourceNode.prototype.start;
  AudioBufferSourceNode.prototype.start = function(...a) {
    T.starts++;
    if (this.buffer && this.buffer.length > 64) T.realStarts++;
    return st.apply(this, a);
  };
  const cn = AudioNode.prototype.connect;
  AudioNode.prototype.connect = function(dst, ...rest) {
    const r = cn.call(this, dst, ...rest);
    try {
      if (dst instanceof AudioDestinationNode) {
        const c = this.context;
        if (!c.__an) {
          c.__an = c.createAnalyser(); c.__an.fftSize = 2048;
          const z = c.createGain(); z.gain.value = 0;
          cn.call(c.__an, z); cn.call(z, c.destination);
          T.an.push(c.__an);
        }
        cn.call(this, c.__an);
      }
    } catch (e) {}
    return r;
  };
})();
"""
STATE = """JSON.stringify({ctx: window.__t.ctxs.map(c => ({state: c.state, rate: c.sampleRate, t: Math.round(c.currentTime*10)/10})),
  starts: window.__t.starts, realStarts: window.__t.realStarts, unlocked: window.__audioUnlocked === true,
  chime: window.__chimePlayed || 0, session: (navigator.audioSession ? navigator.audioSession.type : 'n/a')})"""
RMS = """(() => { let best = 0; for (const a of window.__t.an) { const d = new Float32Array(a.fftSize); a.getFloatTimeDomainData(d);
  let s = 0; for (const v of d) s += v * v; best = Math.max(best, Math.sqrt(s / d.length)); } return best; })()"""

async def touch(cdp, typ, pts):
    await cdp.send("Input.dispatchTouchEvent", {"type": typ, "touchPoints": [{"x": x, "y": y, "id": i} for i, (x, y) in enumerate(pts)]})

async def tap(cdp, page, x, y):
    await touch(cdp, "touchStart", [(x, y)]); await page.wait_for_timeout(110); await touch(cdp, "touchEnd", [])

async def rms(page, n=10):
    vals = []
    for _ in range(n):
        vals.append(await page.evaluate(RMS)); await page.wait_for_timeout(100)
    m = max(vals)
    return round(m, 5), (round(20 * math.log10(m), 1) if m > 0 else None)

async def main():
    async with async_playwright() as p:
        b = await p.chromium.launch(executable_path="/usr/bin/google-chrome", headless=True,
            args=["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist",
                  "--autoplay-policy=user-gesture-required"])
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
        res = {}
        res["before_tap"] = json.loads(await page.evaluate(STATE)); res["before_tap_rms"] = await rms(page, 3)
        await page.screenshot(path=OUT + "_1_tap_to_start.png")
        await tap(cdp, page, W * 0.5, H * 0.5)
        await page.wait_for_timeout(1200)
        res["after_tap"] = json.loads(await page.evaluate(STATE)); res["after_tap_rms"] = await rms(page)
        await page.wait_for_timeout(1500)
        await page.screenshot(path=OUT + "_2_started_tip.png")
        # walk (light push) then run (full push) with the joystick: up = forward, toward the dock
        s0 = (await page.evaluate("window.__t.realStarts"))
        jx, jy = 185 * S, H - 228 * S
        await touch(cdp, "touchStart", [(jx, jy)])
        for i in range(1, 6):
            await touch(cdp, "touchMove", [(jx, jy - i * 8 * K)]); await page.wait_for_timeout(50)
        await page.wait_for_timeout(2500)
        await page.screenshot(path=OUT + "_3_walk.png")
        res["walk_starts"] = (await page.evaluate("window.__t.realStarts")) - s0
        for i in range(1, 8):
            await touch(cdp, "touchMove", [(jx, jy - 40 * K - i * 10 * K)]); await page.wait_for_timeout(40)
        await page.wait_for_timeout(1500)
        await page.screenshot(path=OUT + "_4_run.png")
        await page.wait_for_timeout(9000)
        await touch(cdp, "touchEnd", [])
        await page.wait_for_timeout(1200)
        await page.screenshot(path=OUT + "_5_dock_end.png")
        res["after_run"] = json.loads(await page.evaluate(STATE)); res["after_run_rms"] = await rms(page, 5)
        # camera drag with one finger in the upper half
        await touch(cdp, "touchStart", [(W * 0.77, H * 0.355)])
        for i in range(1, 12):
            await touch(cdp, "touchMove", [(W * 0.77 - i * 10 * K, H * 0.355)]); await page.wait_for_timeout(40)
        await touch(cdp, "touchEnd", [])
        await page.wait_for_timeout(1500)
        await page.screenshot(path=OUT + "_6_cam_drag.png")
        await tap(cdp, page, W - 119 * S, H - 103 * S)   # 打水漂 (only shown at the dock end)
        await page.wait_for_timeout(4500)   # he walks to the throwing spot first; the stone pad shows when he is set
        await page.screenshot(path=OUT + "_7_throw_mode.png")
        # throw by swipe from the stone pad (bottom centre): up-left, rest on the aim, flick and let go
        px, py = W * 0.5, H - PAD_B * S
        await touch(cdp, "touchStart", [(px, py)])
        for i in range(1, 9):
            await touch(cdp, "touchMove", [(px - i * 9 * K, py - i * 17 * K)]); await page.wait_for_timeout(50)
        await page.wait_for_timeout(700)
        await page.screenshot(path=OUT + "_8_swipe_aim.png")
        s1 = (await page.evaluate("window.__t.realStarts"))
        for i in range(1, 4):
            await touch(cdp, "touchMove", [(px - (72 + i * 9) * K, py - (136 + i * 17) * K)]); await page.wait_for_timeout(16)
        await touch(cdp, "touchEnd", [])
        await page.wait_for_timeout(2500)
        await page.screenshot(path=OUT + "_9_thrown.png")
        await page.wait_for_timeout(9000)
        res["throw_starts"] = (await page.evaluate("window.__t.realStarts")) - s1
        res["after_throw_rms"] = await rms(page, 5)
        await page.screenshot(path=OUT + "_10_result.png")
        # elevation slider (left of the two, bottom right): drag the knob up to a steep launch
        sx, sy = W - EL_R * S, H - KNOB_B * S
        await touch(cdp, "touchStart", [(sx, sy)])
        for i in range(1, 9):
            await touch(cdp, "touchMove", [(sx, sy - i * 12 * K)]); await page.wait_for_timeout(40)
        await touch(cdp, "touchEnd", [])
        await page.wait_for_timeout(800)
        await page.screenshot(path=OUT + "_10b_slider_steep.png")
        await touch(cdp, "touchStart", [(px, py)])
        for i in range(1, 9):
            await touch(cdp, "touchMove", [(px + i * 2 * K, py - i * 20 * K)]); await page.wait_for_timeout(50)
        await page.wait_for_timeout(500)
        await touch(cdp, "touchEnd", [])
        await page.wait_for_timeout(9000)
        await page.screenshot(path=OUT + "_10c_steep_result.png")
        # and a cancel: swipe up then pull back down past the pad
        await touch(cdp, "touchStart", [(px, py)])
        for i in range(1, 7):
            await touch(cdp, "touchMove", [(px, py - i * 15 * K)]); await page.wait_for_timeout(40)
        for i in range(1, 9):
            await touch(cdp, "touchMove", [(px, py - (90 - i * 14) * K)]); await page.wait_for_timeout(40)
        await page.screenshot(path=OUT + "_10d_cancel.png")
        await touch(cdp, "touchEnd", [])
        await page.wait_for_timeout(1500)
        res["after_cancel"] = await page.evaluate("1")
        await tap(cdp, page, W - 96 * S, 299 * S)   # 离开码头
        await page.wait_for_timeout(2500)
        await page.screenshot(path=OUT + "_11_left_dock.png")
        await tap(cdp, page, W - 96 * S, 170 * S)    # 夜晚
        await page.wait_for_timeout(9000)
        await page.screenshot(path=OUT + "_12_night.png")
        res["end"] = json.loads(await page.evaluate(STATE))
        print(json.dumps(res, ensure_ascii=False, indent=1))
        print("\n".join(l for l in logs if "WebGL" not in l)[:4000])
        print("RESPONSES:", ", ".join(r for r in resp if any(k in r for k in ("game_v", "index", "?v"))))
        await b.close()
asyncio.run(main())
