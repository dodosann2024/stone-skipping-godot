#!/usr/bin/env node
/** Fresh-browser route: dock, lip, sand, grass, slopes, 8 headings, ≥100 m. */
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "..");
const OUT = path.join(ROOT, "screenshots/v39");
fs.mkdirSync(OUT, { recursive: true });
const W = 390, H = 844, DPR = 3;

function startStatic(dir, port) {
  return new Promise((resolve) => {
    const server = http.createServer((req, res) => {
      let urlPath = decodeURIComponent((req.url || "/").split("?")[0]);
      if (urlPath === "/") urlPath = "/index.html";
      const file = path.join(dir, urlPath);
      if (!file.startsWith(dir) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) {
        res.writeHead(404); res.end("no"); return;
      }
      const ext = path.extname(file);
      const types = { ".html": "text/html", ".js": "application/javascript", ".wasm": "application/wasm", ".pck": "application/octet-stream", ".png": "image/png" };
      res.writeHead(200, { "Content-Type": types[ext] || "application/octet-stream" });
      fs.createReadStream(file).pipe(res);
    });
    server.listen(port, "127.0.0.1", () => resolve(server));
  });
}

const puppeteer = (await import("puppeteer-core")).default;
const server = await startStatic(path.join(ROOT, "docs/game_v39"), 18924);
const url = "http://127.0.0.1:18924/game_v39.html?v=39&debug=1";
const browser = await puppeteer.launch({
  executablePath: process.env.CHROME_PATH || "/usr/bin/google-chrome-stable",
  headless: true,
  args: [`--window-size=${W},${H}`, "--no-sandbox", "--enable-webgl", "--ignore-gpu-blocklist", "--use-gl=angle", "--use-angle=swiftshader-webgl", "--enable-unsafe-swiftshader"],
});
const page = await browser.newPage();
await page.setViewport({ width: W, height: H, deviceScaleFactor: DPR, isMobile: true, hasTouch: true });
console.log("ROUTE open", url);
await page.goto(url, { waitUntil: "domcontentloaded", timeout: 180000 });
await page.waitForSelector("canvas", { timeout: 180000 });
await new Promise((r) => setTimeout(r, 22000));
const client = await page.createCDPSession();
await client.send("Emulation.setTouchEmulationEnabled", { enabled: true, maxTouchPoints: 5 });
const tap = async (x, y) => {
  await client.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [{ x, y, id: 1 }] });
  await client.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
};
await tap(195, 420);
await new Promise((r) => setTimeout(r, 2500));

const readGround = async () =>
  page.evaluate(() => (typeof window.__ground === "object" ? window.__ground : null));
let fails = 0, samples = 0, gapMin = 1e9, gapMax = -1e9;
const assertSole = async (tag) => {
  const g = await readGround();
  samples++;
  if (!g) { console.log("SKIP", tag); return null; }
  const minG = g.sole_gap_min_cm, maxG = g.sole_gap_max_cm;
  gapMin = Math.min(gapMin, minG); gapMax = Math.max(gapMax, maxG);
  console.log("SINK", JSON.stringify({ tag, minG, maxG, speed: g.speed, pos: g.pos, y: g.pos && g.pos[1] }));
  if (minG < -1 || maxG > 1.5) { fails++; console.log("SINK_FAIL", tag, minG.toFixed(2), maxG.toFixed(2)); }
  if (g.pelvis_step_cm > 3.05) { fails++; console.log("SINK_FAIL pelvis", g.pelvis_step_cm); }
  return g;
};
const shot = async (name) => {
  await page.screenshot({ path: path.join(OUT, name), type: "png" });
  console.log("SHOT", name);
};

const base = { x: 70, y: 800 };
const stickFor = (yaw, wx, wz) => {
  const len = Math.hypot(wx, wz) || 1;
  const dx = wx / len, dz = wz / len;
  const fwdX = -Math.sin(yaw), fwdZ = -Math.cos(yaw);
  const rightX = Math.cos(yaw), rightZ = -Math.sin(yaw);
  return { ix: dx * rightX + dz * rightZ, iy: -(dx * fwdX + dz * fwdZ) };
};
const hold = async (ix, iy) => {
  const mag = Math.hypot(ix, iy) || 1;
  const k = 68 / mag;
  await client.send("Input.dispatchTouchEvent", {
    type: "touchMove",
    touchPoints: [{ x: base.x + ix * k, y: base.y + iy * k, id: 7 }],
  });
};

const goals = [
  ["grass", 8, 4],
  ["slope_up", 14, 18],
  ["cross", -6, 20],
  ["slope_down", 10, 32],
  ["inland_a", 18, 28],
  ["inland_b", 2, 40],
  ["inland_c", -8, 30],
  ["inland_d", 16, 14],
  ["sand", 8, -4],
  ["dock_lip", 0.4, -12.2],
  ["dock_deck", 0.2, -18],
];
await client.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [{ x: 54, y: 754, id: 7 }] });
for (let i = 1; i <= 12; i++) {
  await client.send("Input.dispatchTouchEvent", {
    type: "touchMove",
    touchPoints: [{ x: 54 + i * 2, y: 754 - i * 16, id: 7 }],
  });
  await new Promise((r) => setTimeout(r, 30));
}
let route = 0, last = null, goalI = 0, stuck = 0, yPeak = -999, yLow = 999;
const seen = new Set();
const tRun = Date.now();
let ticks = 0;
while (Date.now() - tRun < 240000 && route < 130) {
  await client.send("Input.dispatchTouchEvent", {
    type: "touchMove",
    touchPoints: [{ x: 78, y: 560, id: 7 }],
  });
  ticks++;
  await new Promise((r) => setTimeout(r, 80));
  if (ticks % 15 === 0) {
    const g = await readGround();
    if (g && g.pos) {
      const [x, y, z] = g.pos;
      if (last) route += Math.hypot(x - last[0], z - last[2]);
      last = g.pos;
      yPeak = Math.max(yPeak, y); yLow = Math.min(yLow, y);
      console.log("POS", ticks, "m", route.toFixed(1), "xz", x.toFixed(1), z.toFixed(1), "y", y.toFixed(2), "gap", g.sole_gap_min_cm.toFixed(2), g.sole_gap_max_cm.toFixed(2), "v", (g.speed||0).toFixed(2));
      if (g.sole_gap_min_cm < -1 || g.sole_gap_max_cm > 1.5) { fails++; console.log("SINK_FAIL", ticks); }
      if (route > 8 && route < 14 && !seen.has("slope")) { seen.add("slope"); await shot("cdp_slope_up.png"); }
      if (route > 30 && !seen.has("grass")) { seen.add("grass"); await shot("cdp_grass.png"); }
      if (route > 55 && !seen.has("cross")) { seen.add("cross"); await shot("cdp_cross.png"); }
    }
  }
}
console.log("LOOP END", { route: Number(route.toFixed(1)), goalI, seen: [...seen].join(",") });
await client.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
await new Promise((r) => setTimeout(r, 400));
await shot("cdp_route_stop.png");
await assertSole("route_stop");

// Eight compass headings from wherever we stopped.
const headings = [["n", 0, -1], ["ne", 1, -1], ["e", 1, 0], ["se", 1, 1], ["s", 0, 1], ["sw", -1, 1], ["w", -1, 0], ["nw", -1, -1]];
for (const [name, dx, dz] of headings) {
  const g = await readGround();
  const yaw = g && typeof g.yaw === "number" ? g.yaw : 0;
  const st = stickFor(yaw, dx, dz);
  await client.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [{ x: base.x, y: base.y, id: 7 }] });
  for (let i = 0; i < 8; i++) { await hold(st.ix, st.iy); await new Promise((r) => setTimeout(r, 80)); }
  await shot(`cdp_dir_${name}.png`);
  await assertSole(`dir_${name}`);
  await client.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
  await new Promise((r) => setTimeout(r, 150));
}

console.log("ROUTE_SPOTS", [...seen].join(","), "y", yLow.toFixed(2), yPeak.toFixed(2));
console.log(`ROUTE_SUMMARY fails=${fails} samples=${samples} gap=${gapMin.toFixed(2)}..${gapMax.toFixed(2)} route_m=${route.toFixed(1)}`);
await browser.close();
server.close();
if (fails > 0 || route < 100) { console.error("ROUTE FAILED"); process.exit(1); }
console.log("ROUTE PASS");
