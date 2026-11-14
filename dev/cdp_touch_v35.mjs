#!/usr/bin/env node
/**
 * Exact CDP touch sequence against the exported web build (iPhone 390×844):
 *   tap (195,420) → touchStart joy (54,754) → 10 moves up+right over 300 ms → hold.
 * Asserts the boy is not buried (screenshot + optional debug HUD scrape).
 *
 *   node dev/cdp_touch_v35.mjs [url]
 * Default URL: local static server of docs/game_v35/ or docs/game_v34/
 */
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { spawn } from "node:child_process";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "..");
const OUT = path.join(ROOT, "screenshots/v35");
fs.mkdirSync(OUT, { recursive: true });

const W = 390;
const H = 844;

function contentType(p) {
  if (p.endsWith(".html")) return "text/html";
  if (p.endsWith(".js")) return "application/javascript";
  if (p.endsWith(".wasm")) return "application/wasm";
  if (p.endsWith(".pck")) return "application/octet-stream";
  if (p.endsWith(".png")) return "image/png";
  if (p.endsWith(".jpg") || p.endsWith(".jpeg")) return "image/jpeg";
  return "application/octet-stream";
}

function startStatic(dir, port) {
  return new Promise((resolve) => {
    const server = http.createServer((req, res) => {
      let urlPath = decodeURIComponent((req.url || "/").split("?")[0]);
      if (urlPath === "/") urlPath = "/index.html";
      const file = path.join(dir, urlPath);
      if (!file.startsWith(dir) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) {
        res.writeHead(404);
        res.end("not found");
        return;
      }
      res.writeHead(200, { "Content-Type": contentType(file) });
      fs.createReadStream(file).pipe(res);
    });
    server.listen(port, "127.0.0.1", () => resolve(server));
  });
}

async function main() {
  const argUrl = process.argv[2];
  let url = argUrl;
  let server = null;
  if (!url) {
    const candidates = ["docs/game_v35", "docs/game_v34"];
    let dir = null;
    let html = null;
    for (const c of candidates) {
      const d = path.join(ROOT, c);
      const files = fs.existsSync(d) ? fs.readdirSync(d) : [];
      const h = files.find((f) => f.endsWith(".html") && f.startsWith("game_"));
      if (h) {
        dir = d;
        html = h;
        break;
      }
    }
    if (!dir) throw new Error("no docs/game_v35 or game_v34 export found");
    server = await startStatic(dir, 18901);
    url = `http://127.0.0.1:18901/${html}?v=35&debug=1`;
  }

  // Dynamic import puppeteer-core (may need npm install).
  let puppeteer;
  try {
    puppeteer = await import("puppeteer-core");
  } catch {
    console.log("Installing puppeteer-core…");
    await new Promise((res, rej) => {
      const p = spawn("npm", ["install", "--no-save", "puppeteer-core@23"], {
        cwd: ROOT,
        stdio: "inherit",
      });
      p.on("exit", (c) => (c === 0 ? res() : rej(new Error("npm install failed"))));
    });
    puppeteer = await import("puppeteer-core");
  }

  const browser = await puppeteer.default.launch({
    executablePath: process.env.CHROME_PATH || "/usr/bin/google-chrome-stable",
    headless: true,
    args: [
      `--window-size=${W},${H}`,
      "--no-sandbox",
      "--enable-webgl",
      "--ignore-gpu-blocklist",
      "--use-gl=angle",
      "--use-angle=swiftshader-webgl",
      "--enable-unsafe-swiftshader",
    ],
  });
  const page = await browser.newPage();
  await page.setViewport({ width: W, height: H, deviceScaleFactor: 2, isMobile: true, hasTouch: true });
  console.log("CDP open", url);
  await page.goto(url, { waitUntil: "domcontentloaded", timeout: 120000 });
  // Wait for Godot canvas.
  await page.waitForSelector("canvas", { timeout: 180000 });
  await page.waitForFunction(() => {
    const c=document.querySelector('canvas');
    return c && c.width>100 && c.height>100;
  }, { timeout: 180000 });
  await new Promise((r) => setTimeout(r, 10000));
  const bodyText = await page.evaluate(() => document.body.innerText);
  if (bodyText.includes("加载失败") || bodyText.includes("WebGL")) {
    await page.screenshot({ path: path.join(OUT, "cdp_boot_fail.png"), type: "png" });
    throw new Error("Godot failed to boot: " + bodyText.slice(0, 200));
  }

  const client = await page.createCDPSession();
  await client.send("Emulation.setTouchEmulationEnabled", { enabled: true, maxTouchPoints: 5 });

  const tap = async (x, y) => {
    await client.send("Input.dispatchTouchEvent", {
      type: "touchStart",
      touchPoints: [{ x, y, id: 1 }],
    });
    await client.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
  };

  // Walk inland toward the forest grass slope (user's burial spot) before the drag.
  // Stick: up-right from joystick center for ~2.5 s so we leave the dock/sand.
  await tap(195, 420);
  await new Promise((r) => setTimeout(r, 300));
  await client.send("Input.dispatchTouchEvent", {
    type: "touchStart",
    touchPoints: [{ x: 54, y: 754, id: 9 }],
  });
  for (let i = 1; i <= 16; i++) {
    const t = i / 16;
    await client.send("Input.dispatchTouchEvent", {
      type: "touchMove",
      touchPoints: [{ x: 54 + t * 30, y: 754 - t * 90, id: 9 }],
    });
    await new Promise((r) => setTimeout(r, 80));
  }
  await new Promise((r) => setTimeout(r, 1800));
  await client.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
  await new Promise((r) => setTimeout(r, 400));

  // 1) Tap center-ish (dismiss / unlock)
  await tap(195, 420);
  await new Promise((r) => setTimeout(r, 400));

  // 2) Joystick drag: start (54,754), 10 moves up+right over 300 ms, hold
  const x0 = 54;
  const y0 = 754;
  await client.send("Input.dispatchTouchEvent", {
    type: "touchStart",
    touchPoints: [{ x: x0, y: y0, id: 2 }],
  });
  const moves = 10;
  const dt = 300 / moves;
  for (let i = 1; i <= moves; i++) {
    const t = i / moves;
    const x = x0 + t * 40; // right
    const y = y0 - t * 70; // up
    await client.send("Input.dispatchTouchEvent", {
      type: "touchMove",
      touchPoints: [{ x, y, id: 2 }],
    });
    await new Promise((r) => setTimeout(r, dt));
  }
  // Hold ~0.6 s into drag (user's d34_a_zoom timing)
  await new Promise((r) => setTimeout(r, 300));
  const shot1 = path.join(OUT, "cdp_drag_0p6.png");
  await page.screenshot({ path: shot1, type: "png" });
  console.log("SHOT", shot1);

  await new Promise((r) => setTimeout(r, 800));
  const shot2 = path.join(OUT, "cdp_drag_hold.png");
  await page.screenshot({ path: shot2, type: "png" });
  console.log("SHOT", shot2);

  await client.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
  await new Promise((r) => setTimeout(r, 500));
  const shot3 = path.join(OUT, "cdp_after_release.png");
  await page.screenshot({ path: shot3, type: "png" });

  // Pixel heuristic via PNG decode: below yellow shorts there must be skin/brown
  // (legs/sandals), not an immediate grass cut at the hem (v34 burial signature).
  for (const s of [shot1, shot2, shot3]) {
    const st = fs.statSync(s);
    if (st.size < 20000) throw new Error(`screenshot too small: ${s}`);
  }
  const { spawnSync } = await import("node:child_process");
  const py = `
from PIL import Image
import numpy as np, sys
im=np.array(Image.open(sys.argv[1]).convert('RGB'))
h,w=im.shape[:2]
# Strict yellow shorts (avoid sand)
yel=np.where((im[:,:,0]>200)&(im[:,:,1]>170)&(im[:,:,1]<225)&(im[:,:,2]<110)&(im[:,:,1]>im[:,:,2]+60))
if len(yel[0]) < 80:
  yel=np.where((im[:,:,0]>185)&(im[:,:,1]>155)&(im[:,:,2]<125)&(im[:,:,1]>im[:,:,2]+35))
if len(yel[0]) < 40:
  print('NO_SHORTS'); sys.exit(2)
y_lo=int(np.percentile(yel[0], 88))
x_mid=int(np.median(yel[1]))
# Under the shorts hem: need sandal brown or leg skin before grass dominates.
sandal=skin=grass=0
for y in range(y_lo, min(h-2, y_lo+140)):
  for x in range(max(0,x_mid-55), min(w, x_mid+56), 2):
    r,g,b=map(int, im[y,x])
    if g>r+15 and g>50 and g>b+4: grass+=1
    elif r>130 and 55<g<125 and b<75 and r>g+25: sandal+=1
    elif r>155 and g>115 and b>85 and abs(r-g)<55 and r<240: skin+=1
print(f'shorts_lo={y_lo} x={x_mid} skin={skin} sandal={sandal} grass={grass}')
# Burial signature: grass immediately under shorts, almost no feet.
if sandal + skin < 25:
  print('BURIAL_LOOK'); sys.exit(3)
if grass > (sandal+skin)*8 and sandal < 15:
  print('BURIAL_LOOK_GRASS'); sys.exit(3)
print('FEET_OK')
`
  const chk = spawnSync("python3", ["-c", py, shot1], { encoding: "utf8" });
  console.log(chk.stdout.trim());
  if (chk.status !== 0) {
    throw new Error("CDP burial pixel check failed: " + (chk.stdout || chk.stderr));
  }

  await browser.close();
  if (server) server.close();
  console.log("CDP_TOUCH PASS");
}

main().catch((e) => {
  console.error("CDP_TOUCH FAIL", e);
  process.exit(1);
});
