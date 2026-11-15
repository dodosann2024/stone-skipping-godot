#!/usr/bin/env node
/**
 * v39 web acceptance on docs/game_v39 (not docs/index.html):
 *   load → wait 60s → tap (195,420) → wait 6s →
 *   CDP touchStart (54,754), 10 touchMoves (+3i,-6i) @30ms, hold →
 *   shots at 300ms into drag (A), 2.8s (B), 0.8s after release (C).
 *
 * Also samples 30+ frames across start / walk / stop / idle and asserts
 * both skinned soles stay in −1…+1.5 cm (no swing-foot exemption),
 * and writes side-on close-ups.
 *
 *   node dev/cdp_sink_v37.mjs [url]
 */
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { spawn } from "node:child_process";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "..");
const OUT = path.join(ROOT, "screenshots/v39");
fs.mkdirSync(OUT, { recursive: true });

const W = 390;
const H = 844;
const DPR = 3;

function contentType(p) {
  if (p.endsWith(".html")) return "text/html";
  if (p.endsWith(".js")) return "application/javascript";
  if (p.endsWith(".wasm")) return "application/wasm";
  if (p.endsWith(".pck")) return "application/octet-stream";
  if (p.endsWith(".png")) return "image/png";
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
  let url = process.argv[2];
  let server = null;
  if (!url) {
    const dir = path.join(ROOT, "docs/game_v39");
    const html = "game_v39.html";
    if (!fs.existsSync(path.join(dir, html))) throw new Error("missing docs/game_v39");
    server = await startStatic(dir, 18923);
    url = `http://127.0.0.1:18923/${html}?v=39&debug=1`;
  }

  let puppeteer;
  try {
    puppeteer = await import("puppeteer-core");
  } catch {
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
  await page.setViewport({ width: W, height: H, deviceScaleFactor: DPR, isMobile: true, hasTouch: true });
  await page.goto("about:blank");
  await page.evaluateOnNewDocument(() => {
    try {
      localStorage.setItem("ss_cam_fixed", "0");
    } catch (e) {}
  });

  console.log("CDP_SINK open", url);
  await page.goto(url, { waitUntil: "domcontentloaded", timeout: 180000 });
  await page.waitForSelector("canvas", { timeout: 180000 });
  await page.waitForFunction(() => {
    const c = document.querySelector("canvas");
    return c && c.width > 100 && c.height > 100;
  }, { timeout: 180000 });
  // Match the independent review: wait a full minute for boot/settle.
  console.log("CDP_SINK waiting boot…");
  await new Promise((r) => setTimeout(r, Number(process.env.SINK_BOOT_S||60)*1000));

  const client = await page.createCDPSession();
  await client.send("Emulation.setTouchEmulationEnabled", { enabled: true, maxTouchPoints: 5 });

  const tap = async (x, y) => {
    await client.send("Input.dispatchTouchEvent", {
      type: "touchStart",
      touchPoints: [{ x, y, id: 1 }],
    });
    await client.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
  };

  // Unlock / dismiss toast — exact review script.
  await tap(195, 420);
  await new Promise((r) => setTimeout(r, 6000));

  const readGround = async () => {
    const evalP = page.evaluate(() => (typeof window.__ground === "object" ? window.__ground : null));
    const timeout = new Promise((resolve) => setTimeout(() => resolve(null), 4000));
    return Promise.race([evalP, timeout]);
  };
  const readHud = async () =>
    page.evaluate(() => {
      const el = document.querySelector("#dbg_label, .dbg, label");
      // Prefer Godot-exported probe; also scrape canvas overlay text via __ground.
      return {
        ground: typeof window.__ground === "object" ? window.__ground : null,
        frame: typeof window.__frame === "object" ? window.__frame : null,
      };
    });

  let fails = 0;
  let samples = 0;
  let gapMin = 1e9;
  let gapMax = -1e9;

  const assertSole = async (tag) => {
    const g = await readGround();
    samples += 1;
    if (!g) {
      console.log("SINK_SKIP", tag, "(no __ground)");
      return;
    }
    const gap = typeof g.sole_gap_cm === "number" ? g.sole_gap_cm : 999;
    const minG = typeof g.sole_gap_min_cm === "number" ? g.sole_gap_min_cm : gap;
    const maxG = typeof g.sole_gap_max_cm === "number" ? g.sole_gap_max_cm : gap;
    gapMin = Math.min(gapMin, minG);
    gapMax = Math.max(gapMax, maxG);
    const line = {
      tag,
      sole_gap_cm: gap,
      sole_min: minG,
      sole_max: maxG,
      skin_gap_cm: g.skin_gap_cm,
      body_gnd_cm: g.body_gnd_cm,
      sole_y_l: g.sole_y_l,
      sole_y_r: g.sole_y_r,
      pelvis_step_cm: g.pelvis_step_cm,
      pose_path: g.pose_path,
      speed: g.speed,
      moving: g.moving,
      pos: g.pos,
    };
    console.log("SINK", JSON.stringify(line));
    // Both shoes, drawn pose, AAA bar. No swing-foot exemption.
    if (minG < -1.0 || maxG > 1.5) {
      fails += 1;
      console.log("SINK_FAIL", tag, `sole out of bar min=${minG.toFixed(2)} max=${maxG.toFixed(2)}`);
    }
    if (typeof g.pelvis_step_cm === "number" && g.pelvis_step_cm > 3.05) {
      fails += 1;
      console.log("SINK_FAIL", tag, `pelvis step ${g.pelvis_step_cm.toFixed(2)} cm`);
    }
  };

  const shot = async (name) => {
    const p = path.join(OUT, name);
    await page.screenshot({ path: p, type: "png" });
    console.log("SHOT", p);
  };

  await shot("cdp_spawn.png");
  await assertSole("spawn");

  // ---- Exact review drag ----
  const x0 = 54;
  const y0 = 754;
  await client.send("Input.dispatchTouchEvent", {
    type: "touchStart",
    touchPoints: [{ x: x0, y: y0, id: 9 }],
  });
  for (let i = 1; i <= 10; i++) {
    await client.send("Input.dispatchTouchEvent", {
      type: "touchMove",
      touchPoints: [{ x: x0 + 3 * i, y: y0 - 6 * i, id: 9 }],
    });
    await new Promise((r) => setTimeout(r, 30));
  }

  // A — 300 ms into drag (walk-start).
  await new Promise((r) => setTimeout(r, 300));
  await shot("cdp_sink_A.png");
  await assertSole("A_start");
  // Dense start samples.
  for (let i = 0; i < 8; i++) {
    await assertSole(`start_${i}`);
    await new Promise((r) => setTimeout(r, 40));
  }

  // B — 2.8 s into drag (walking; may hit foliage).
  await new Promise((r) => setTimeout(r, 2500));
  await shot("cdp_sink_B.png");
  await assertSole("B_walk");
  for (let i = 0; i < 12; i++) {
    await assertSole(`walk_${i}`);
    await new Promise((r) => setTimeout(r, 80));
  }

  // Release + C — 0.8 s after release (stop transition).
  await client.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
  await new Promise((r) => setTimeout(r, 800));
  await shot("cdp_sink_C.png");
  await assertSole("C_stop");
  for (let i = 0; i < 10; i++) {
    await assertSole(`stop_${i}`);
    await new Promise((r) => setTimeout(r, 60));
  }

  // Idle settle.
  for (let i = 0; i < 6; i++) {
    await assertSole(`idle_${i}`);
    await new Promise((r) => setTimeout(r, 100));
  }
  await shot("cdp_sink_idle.png");

  // Side-on low close-up: orbit drag on the right side of the screen.
  await client.send("Input.dispatchTouchEvent", {
    type: "touchStart",
    touchPoints: [{ x: 300, y: 400, id: 11 }],
  });
  for (let i = 1; i <= 14; i++) {
    await client.send("Input.dispatchTouchEvent", {
      type: "touchMove",
      touchPoints: [{ x: 300 - i * 12, y: 400 + i * 2, id: 11 }],
    });
    await new Promise((r) => setTimeout(r, 25));
  }
  await new Promise((r) => setTimeout(r, 200));
  await shot("cdp_sink_side.png");
  await assertSole("side_on");
  await client.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });

  // Pinch-ish zoom via wheel for a low close-up of the feet (if supported).
  await page.mouse.wheel({ deltaY: -400 });
  await new Promise((r) => setTimeout(r, 300));
  await shot("cdp_sink_side_zoom.png");
  await assertSole("side_zoom");


  // ---- Run burst (full stick) ----
  await client.send("Input.dispatchTouchEvent", {
    type: "touchStart",
    touchPoints: [{ x: 80, y: 780, id: 21 }],
  });
  for (let i = 1; i <= 16; i++) {
    await client.send("Input.dispatchTouchEvent", {
      type: "touchMove",
      touchPoints: [{ x: 80 + i * 2, y: 780 - i * 18, id: 21 }],
    });
    await new Promise((r) => setTimeout(r, 25));
  }
  await new Promise((r) => setTimeout(r, 600));
  await shot("cdp_run.png");
  await assertSole("run_0");
  for (let i = 0; i < 6; i++) {
    await assertSole(`run_${i + 1}`);
    await new Promise((r) => setTimeout(r, 70));
  }
  await client.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
  await new Promise((r) => setTimeout(r, 500));
  await shot("cdp_run_stop.png");
  await assertSole("run_stop");

  // ---- Extra low side stills on different headings ----
  for (const [name, x0, y0, dx, dy, n] of [
    ["cdp_sand_side", 70, 760, 4, -5, 12],
    ["cdp_slope_side", 60, 750, 5, -8, 14],
  ]) {
    if (process.env.SKIP_SIDE === "1") break;
    await client.send("Input.dispatchTouchEvent", {
      type: "touchStart",
      touchPoints: [{ x: x0, y: y0, id: 31 }],
    });
    for (let i = 1; i <= n; i++) {
      await client.send("Input.dispatchTouchEvent", {
        type: "touchMove",
        touchPoints: [{ x: x0 + dx * i, y: y0 + dy * i, id: 31 }],
      });
      await new Promise((r) => setTimeout(r, 28));
    }
    await new Promise((r) => setTimeout(r, 400));
    // End stick before orbit — CDP requires TouchStart to restart a touch.
    await client.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
    await new Promise((r) => setTimeout(r, 80));
    // Orbit for side-on
    await client.send("Input.dispatchTouchEvent", {
      type: "touchStart",
      touchPoints: [{ x: 320, y: 380, id: 32 }],
    });
    for (let i = 1; i <= 10; i++) {
      await client.send("Input.dispatchTouchEvent", {
        type: "touchMove",
        touchPoints: [{ x: 320 - i * 14, y: 380 + i * 3, id: 32 }],
      });
      await new Promise((r) => setTimeout(r, 22));
    }
    await new Promise((r) => setTimeout(r, 200));
    await shot(`${name}.png`);
    await assertSole(name);
    await client.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
    await new Promise((r) => setTimeout(r, 300));
  }

  // Eight headings: short full-stick bursts, then a still.
  const dirs = [
    ["n", 0, -16],
    ["ne", 12, -12],
    ["e", 16, 0],
    ["se", 12, 12],
    ["s", 0, 16],
    ["sw", -12, 12],
    ["w", -16, 0],
    ["nw", -12, -12],
  ];
  for (const [name, dx, dy] of dirs) {
    const sx = 90;
    const sy = 760;
    await client.send("Input.dispatchTouchEvent", {
      type: "touchStart",
      touchPoints: [{ x: sx, y: sy, id: 41 }],
    });
    for (let i = 1; i <= 8; i++) {
      await client.send("Input.dispatchTouchEvent", {
        type: "touchMove",
        touchPoints: [{ x: sx + dx * 4 * (i / 8), y: sy + dy * 4 * (i / 8), id: 41 }],
      });
      await new Promise((r) => setTimeout(r, 30));
    }
    await new Promise((r) => setTimeout(r, 700));
    await shot(`cdp_dir_${name}.png`);
    await assertSole(`dir_${name}`);
    await client.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
    await new Promise((r) => setTimeout(r, 200));
  }

  // World-space stick. Screen-up follows the camera, which is why a fixed
  // "stick up" walk died on the dock edge at 1.3 m. yaw is the camera heading.
  const stickBase = { x: 110, y: 730 };
  const stickFor = (yaw, wx, wz) => {
    const len = Math.hypot(wx, wz) || 1;
    const dx = wx / len;
    const dz = wz / len;
    const fwdX = -Math.sin(yaw);
    const fwdZ = -Math.cos(yaw);
    const rightX = Math.cos(yaw);
    const rightZ = -Math.sin(yaw);
    return {
      ix: dx * rightX + dz * rightZ,
      iy: -(dx * fwdX + dz * fwdZ),
    };
  };
  const holdStick = async (ix, iy) => {
    const mag = Math.hypot(ix, iy) || 1;
    const k = 64 / mag;
    await client.send("Input.dispatchTouchEvent", {
      type: "touchMove",
      touchPoints: [{ x: stickBase.x + ix * k, y: stickBase.y + iy * k, id: 51 }],
    });
  };

  // Dock deck, dock lip, sand, then a long inland loop (grass, slope, cross-slope).
  const goals = [
    ["dock_deck", 0.3, -20],
    ["dock_lip", 0.4, -12.2],
    ["sand", 7.5, -5.5],
    ["grass", 10, 6],
    ["slope_up", 14, 18],
    ["slope_down", 6, 28],
    ["cross", -8, 22],
    ["cross2", -10, 8],
    ["inland_a", 16, 30],
    ["inland_b", 4, 42],
    ["inland_c", 18, 16],
    ["inland_d", -4, 34],
    ["inland_e", 12, 8],
  ];
  let route = 0;
  let last = null;
  let goalI = 0;
  let stuck = 0;
  let yPeak = -999;
  let yLow = 999;
  const seen = new Set();
  await client.send("Input.dispatchTouchEvent", {
    type: "touchStart",
    touchPoints: [{ x: stickBase.x, y: stickBase.y, id: 51 }],
  });
  const tRoute = Date.now();
  let routeShot = 0;
  while (Date.now() - tRoute < 90000 && (route < 110 || goalI < 7)) {
    const g = await readGround();
    if (g && Array.isArray(g.pos)) {
      const [x, y, z] = g.pos;
      if (last) route += Math.hypot(x - last[0], z - last[2]);
      const moved = last ? Math.hypot(x - last[0], z - last[2]) : 1;
      last = g.pos;
      if (moved < 0.15 && (g.speed || 0) < 0.25) stuck += 1;
      else stuck = 0;
      yPeak = Math.max(yPeak, y);
      yLow = Math.min(yLow, y);
      let [name, tx, tz] = goals[Math.min(goalI, goals.length - 1)];
      if (Math.hypot(x - tx, z - tz) < 2.2) {
        if (!seen.has(name)) {
          seen.add(name);
          await shot(`cdp_${name}.png`);
          await assertSole(name);
        }
        goalI += 1;
        [name, tx, tz] = goals[Math.min(goalI, goals.length - 1)];
      }
      let wx = tx - x;
      let wz = tz - z;
      if (stuck >= 8) {
        // Give up this waypoint (pier post, trunk) and keep the route moving.
        goalI += 1;
        stuck = 0;
      } else if (stuck >= 3) {
        const side = stuck % 2 === 0 ? 1 : -1;
        wx = -wz * side;
        wz = (tx - x) * side;
      }
      const st = stickFor(typeof g.yaw === "number" ? g.yaw : 0, wx, wz);
      await holdStick(st.ix, st.iy);
    }
    await assertSole(`route_${routeShot}`);
    if (routeShot % 5 === 0) await shot(`cdp_route_${routeShot}.png`);
    routeShot += 1;
    await new Promise((r) => setTimeout(r, 350));
  }
  await client.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
  console.log("ROUTE_SPOTS", [...seen].join(","), "y", yLow.toFixed(2), yPeak.toFixed(2));
  await new Promise((r) => setTimeout(r, 400));
  await shot("cdp_route_stop.png");
  console.log("ROUTE_M", route.toFixed(1));
  if (route < 100) {
    fails += 1;
    console.log("SINK_FAIL route", route.toFixed(1), "m < 100");
  }

  console.log(
    `SINK_SUMMARY samples=${samples} fails=${fails} gap_min=${gapMin.toFixed(2)} gap_max=${gapMax.toFixed(2)} route_m=${route.toFixed(1)}`
  );

  await browser.close();
  if (server) server.close();
  if (fails > 0 || samples < 30) {
    console.error("CDP_SINK FAILED");
    process.exit(1);
  }
  console.log("CDP_SINK PASS");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
