"""Load live Pages builds in WebKit (iPhone) and Chromium (optional force-ETC2).
Usage: ios_boot_compare.py LABEL URL OUTDIR [--force-etc2] [--browser webkit|chromium]
"""
import sys, asyncio, json, re
from pathlib import Path
from playwright.async_api import async_playwright

LABEL = sys.argv[1]
URL = sys.argv[2]
OUT = Path(sys.argv[3])
FORCE_ETC2 = "--force-etc2" in sys.argv
BROWSER = "webkit"
for a in sys.argv[4:]:
	if a.startswith("--browser="):
		BROWSER = a.split("=", 1)[1]
OUT.mkdir(parents=True, exist_ok=True)
W, H = 390, 844

ETC2_HIDE_S3TC = """
(() => {
  const hide = (arr) => (arr || []).filter(e => e && e.indexOf('s3tc') < 0 && e.indexOf('S3TC') < 0 && e.indexOf('bptc') < 0 && e.indexOf('BPTC') < 0 && e.indexOf('rgtc') < 0);
  const wrap = (proto) => {
    if (!proto || proto.__etc2patched) return;
    const gse = proto.getSupportedExtensions;
    const ge = proto.getExtension;
    proto.getSupportedExtensions = function() {
      return hide(gse.apply(this, arguments));
    };
    proto.getExtension = function(name) {
      if (!name) return ge.apply(this, arguments);
      const n = String(name);
      if (/s3tc|S3TC|bptc|BPTC|rgtc|RGTC/i.test(n)) return null;
      return ge.apply(this, arguments);
    };
    proto.__etc2patched = true;
  };
  wrap(WebGLRenderingContext && WebGLRenderingContext.prototype);
  wrap(WebGL2RenderingContext && WebGL2RenderingContext.prototype);
  const oc = HTMLCanvasElement.prototype.getContext;
  HTMLCanvasElement.prototype.getContext = function(type, attrs) {
    const ctx = oc.call(this, type, attrs);
    if (ctx) wrap(Object.getPrototypeOf(ctx));
    return ctx;
  };
  window.__forceEtc2 = true;
})();
"""


async def main():
	async with async_playwright() as p:
		launcher = p.webkit if BROWSER == "webkit" else p.chromium
		kwargs = {}
		if BROWSER == "chromium":
			kwargs["executable_path"] = "/usr/bin/google-chrome"
			kwargs["args"] = [
				"--use-gl=angle", "--use-angle=swiftshader",
				"--enable-unsafe-swiftshader", "--ignore-gpu-blocklist",
			]
		b = await launcher.launch(headless=True, **kwargs)
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
		if FORCE_ETC2:
			await ctx.add_init_script(ETC2_HIDE_S3TC)
		page = await ctx.new_page()
		logs, errors, fails = [], [], []
		page.on("console", lambda m: logs.append(f"[{m.type}] {m.text}"))
		page.on("pageerror", lambda e: errors.append(str(e)))
		page.on("requestfailed", lambda r: fails.append(f"{r.url.split('/')[-1]} {r.failure}"))

		print(f"=== {LABEL} {BROWSER} force_etc2={FORCE_ETC2} ===", flush=True)
		print(f"goto {URL}", flush=True)
		try:
			await page.goto(URL, wait_until="load", timeout=180000)
		except Exception as e:
			print(f"GOTO_ERR {e}", flush=True)
		# Wait 90s as requested
		for i in range(18):
			await page.wait_for_timeout(5000)
			state = await page.evaluate("""() => ({
				href: location.href,
				canvas: !!document.querySelector('canvas'),
				body: (document.body && document.body.innerText || '').slice(0, 200),
				status: (document.getElementById('status') && document.getElementById('status').innerText) || '',
				statusNotice: (document.getElementById('status-notice') && document.getElementById('status-notice').innerText) || '',
				forceEtc2: !!window.__forceEtc2,
				exts: (() => {
					try {
						const c = document.createElement('canvas');
						const gl = c.getContext('webgl2') || c.getContext('webgl');
						return gl ? (gl.getSupportedExtensions() || []).filter(e => /s3tc|etc|astc|bptc/i.test(e)) : [];
					} catch (e) { return ['err:'+e]; }
				})(),
			})""")
			print(f"t={(i+1)*5}s canvas={state['canvas']} status={state['status']!r} notice={state['statusNotice'][:80]!r}", flush=True)
			if state["statusNotice"]:
				print(f"  NOTICE: {state['statusNotice'][:300]}", flush=True)

		await page.screenshot(path=str(OUT / f"{LABEL}_{BROWSER}{'_etc2' if FORCE_ETC2 else ''}.png"), full_page=False)
		final = await page.evaluate("""() => ({
			href: location.href,
			canvas: !!document.querySelector('canvas'),
			cw: (document.querySelector('canvas')||{}).width || 0,
			ch: (document.querySelector('canvas')||{}).height || 0,
			body: (document.body && document.body.innerText || '').slice(0, 400),
			status: (document.getElementById('status') && document.getElementById('status').innerText) || '',
			notice: (document.getElementById('status-notice') && document.getElementById('status-notice').innerText) || '',
			hasStart: /点击开始|点一下开始|开始/.test(document.body && document.body.innerText || ''),
			exts: (() => {
				try {
					const c = document.createElement('canvas');
					const gl = c.getContext('webgl2') || c.getContext('webgl');
					return gl ? (gl.getSupportedExtensions() || []).filter(e => /s3tc|etc|astc|bptc/i.test(e)) : [];
				} catch (e) { return []; }
			})(),
		})""")
		# Look for Godot boot / shader errors
		godot = [l for l in logs if "Godot" in l or "ERROR" in l or "error" in l.lower() or "shader" in l.lower() or "Failed" in l or "failed" in l]
		result = {
			"label": LABEL,
			"browser": BROWSER,
			"force_etc2": FORCE_ETC2,
			"url": URL,
			"final": final,
			"pageerrors": errors,
			"reqfails": fails[:30],
			"console_error": [l for l in logs if l.startswith("[error]")],
			"godotish": godot[-40:],
			"log_tail": logs[-40:],
		}
		(OUT / f"{LABEL}_{BROWSER}{'_etc2' if FORCE_ETC2 else ''}.json").write_text(json.dumps(result, indent=2, ensure_ascii=False))
		print(json.dumps(result, indent=2, ensure_ascii=False)[:4000])
		await ctx.close()
		await b.close()


if __name__ == "__main__":
	asyncio.run(main())
