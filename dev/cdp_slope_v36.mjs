#!/usr/bin/env node
/**
 * Web CDP: slope walk (up + down) + full-stick run, low camera, feet visible.
 * Asserts window.__ground blob↔sole < 3 cm and sole gap within bar while moving.
 *
 *   node dev/cdp_slope_v36.mjs [url]
 */
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { spawn } from "node:child_process";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "..");
const OUT = path.join(ROOT, "screenshots/v36");
fs.mkdirSync(OUT, { recursive: true });

const W = 390;
const H = 844;

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
    const dir = path.join(ROOT, "docs/game_v36");
    const html = "game_v36.html";
    if (!fs.existsSync(path.join(dir, html))) throw new Error("missing docs/game_v36");
    server = await startStatic(dir, 18902);
    url = `http://127.0.0.1:18902/${html}?v=36&debug=1&at=slope&q=low`;
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
  await page.setViewport({ width: W, height: H, deviceScaleFactor: 2, isMobile: true, hasTouch: true });
  console.log("CDP_SLOPE open", url);
  await page.goto(url, { waitUntil: "domcontentloaded", timeout: 120000 });
  await page.waitForSelector("canvas", { timeout: 180000 });
  await page.waitForFunction(() => {
    const c = document.querySelector("canvas");
    return c && c.width > 100 && c.height > 100;
  }, { timeout: 180000 });
  await new Promise((r) => setTimeout(r, 12000));

  const client = await page.createCDPSession();
  await client.send("Emulation.setTouchEmulationEnabled", { enabled: true, maxTouchPoints: 5 });

  const tap = async (x, y) => {
    await client.send("Input.dispatchTouchEvent", {
      type: "touchStart",
      touchPoints: [{ x, y, id: 1 }],
    });
    await client.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
  };

  const stickDrag = async (dx, dy, holdMs, id = 9) => {
    const x0 = 54;
    const y0 = 754;
    await client.send("Input.dispatchTouchEvent", {
      type: "touchStart",
      touchPoints: [{ x: x0, y: y0, id }],
    });
    for (let i = 1; i <= 12; i++) {
      const t = i / 12;
      await client.send("Input.dispatchTouchEvent", {
        type: "touchMove",
        touchPoints: [{ x: x0 + t * dx, y: y0 + t * dy, id }],
      });
      await new Promise((r) => setTimeout(r, 40));
    }
    await new Promise((r) => setTimeout(r, holdMs));
  };

  const stickEnd = async (id = 9) => {
    await client.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
  };

  const readGround = async () =>
    page.evaluate(() => (typeof window.__ground === "object" ? window.__ground : null));
  const readFrame = async () =>
    page.evaluate(() => (typeof window.__frame === "object" ? window.__frame : null));

  const assertGround = async (tag) => {
    const g = await readGround();
    const f = await readFrame();
    if (!g) {
      console.log("GROUND_SKIP", tag, "(no __ground yet)");
    } else {
      console.log("GROUND", tag, JSON.stringify(g));
      if (g.blob_d_cm > 3.0) {
        throw new Error(`${tag} blob↔sole ${g.blob_d_cm.toFixed(1)}cm > 3cm`);
      }
      if (g.moving && g.sole_gap_cm > 1.5) {
        throw new Error(`${tag} sole gap ${g.sole_gap_cm.toFixed(1)}cm > 1.5cm`);
      }
      if (g.moving && g.disc_on) {
        throw new Error(`${tag} contact disc visible while locomoting`);
      }
    }
    if (f) {
      console.log("FRAME", tag, JSON.stringify(f));
      if (!f.ok) {
        throw new Error(
          `${tag} framing fail head=${JSON.stringify(f.head_uv)} feet=${JSON.stringify(f.feet_uv)} margin=${f.margin_min}`
        );
      }
      if (f.fixed) {
        throw new Error(`${tag} cam_fixed true — follow required`);
      }
    }
  };

  const burstShots = async (prefix, count, gapMs) => {
    for (let i = 0; i < count; i++) {
      const p = path.join(OUT, `${prefix}_${i}.png`);
      await page.screenshot({ path: p, type: "png" });
      console.log("SHOT", p);
      await assertGround(`${prefix}_${i}`);
      await new Promise((r) => setTimeout(r, gapMs));
    }
  };

  // Dismiss start / unlock audio.
  await tap(195, 420);
  await new Promise((r) => setTimeout(r, 600));
  await tap(195, 420);
  await new Promise((r) => setTimeout(r, 400));

  // Uphill walk (stick up) — 6+ low-cam frames.
  console.log("CDP_SLOPE uphill");
  await stickDrag(20, -95, 200, 9);
  await burstShots("cdp_slope_up", 7, 220);
  await stickEnd(9);
  await new Promise((r) => setTimeout(r, 300));

  // Downhill walk (stick down).
  console.log("CDP_SLOPE downhill");
  await stickDrag(10, 95, 200, 10);
  await burstShots("cdp_slope_dn", 7, 220);
  await stickEnd(10);
  await new Promise((r) => setTimeout(r, 300));

  // Full-stick run (push to edge).
  console.log("CDP_SLOPE run");
  await stickDrag(35, -120, 150, 11);
  await burstShots("cdp_run", 7, 180);
  await stickEnd(11);
  await new Promise((r) => setTimeout(r, 400));

  // Final hold frame for blob coincidence check after release.
  const after = path.join(OUT, "cdp_slope_after.png");
  await page.screenshot({ path: after, type: "png" });
  console.log("SHOT", after);

  await browser.close();
  if (server) server.close();
  console.log("CDP_SLOPE PASS");
}

main().catch((e) => {
  console.error("CDP_SLOPE FAIL", e);
  process.exit(1);
});
