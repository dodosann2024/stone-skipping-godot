#!/usr/bin/env node
/**
 * Side-view stills of the exported v39 build, plus the reviewer's drag.
 *   ?side=1 puts the lens perpendicular to travel and does not change stick yaw.
 *   node dev/cdp_side_v39.mjs
 */
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "..");
const OUT = path.join(ROOT, "screenshots/v39");
fs.mkdirSync(OUT, { recursive: true });

const W = 390;
const H = 844;
const DPR = 3;
const PORT = Number(process.env.SIDE_PORT || 18925);

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
      if (urlPath === "/") urlPath = "/game_v39.html";
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
  const puppeteer = await import("puppeteer-core");
  const dir = path.join(ROOT, "docs/game_v39");
  if (!fs.existsSync(path.join(dir, "game_v39.html"))) throw new Error("missing docs/game_v39");
  const server = await startStatic(dir, PORT);
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
  const client = await page.createCDPSession();
  await client.send("Emulation.setTouchEmulationEnabled", { enabled: true, maxTouchPoints: 5 });

  const bootDefault = Number(process.env.SIDE_BOOT_S || 60);
  const open = async (qs, boot = bootDefault) => {
    const url = `http://127.0.0.1:${PORT}/game_v39.html?${qs}`;
    console.log("OPEN", url);
    await page.goto(url, { waitUntil: "domcontentloaded", timeout: 180000 });
    await page.waitForSelector("canvas", { timeout: 180000 });
    await page.waitForFunction(() => {
      const c = document.querySelector("canvas");
      return c && c.width > 100 && c.height > 100;
    }, { timeout: 180000 });
    console.log("BOOT", boot);
    await new Promise((r) => setTimeout(r, boot * 1000));
    await client.send("Input.dispatchTouchEvent", {
      type: "touchStart",
      touchPoints: [{ x: 195, y: 420, id: 1 }],
    });
    await client.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
    await new Promise((r) => setTimeout(r, 1500));
  };

  const ground = async () => {
    const evalP = page.evaluate(() => (typeof window.__ground === "object" ? window.__ground : null));
    const timeout = new Promise((resolve) => setTimeout(() => resolve(null), 4000));
    return Promise.race([evalP, timeout]);
  };

  const shot = async (name) => {
    const p = path.join(OUT, name);
    await page.screenshot({ path: p, type: "png" });
    const g = await ground();
    console.log("SHOT", name, JSON.stringify(g));
    return g;
  };

  const drag = async (x0, y0, dx, dy, n, id) => {
    await client.send("Input.dispatchTouchEvent", {
      type: "touchStart",
      touchPoints: [{ x: x0, y: y0, id }],
    });
    for (let i = 1; i <= n; i++) {
      await client.send("Input.dispatchTouchEvent", {
        type: "touchMove",
        touchPoints: [{ x: x0 + dx * i, y: y0 + dy * i, id }],
      });
      await new Promise((r) => setTimeout(r, 30));
    }
  };
  const release = async () => {
    await client.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
  };

  // Reviewer's drag, lens from the side so shin length is visible.
  await open("v=39&debug=1&side=1");
  await drag(54, 754, 3, -6, 10, 9);
  await new Promise((r) => setTimeout(r, 300));
  await shot("side_start.png");
  await new Promise((r) => setTimeout(r, 2500));
  await shot("side_walk.png");
  await release();
  await new Promise((r) => setTimeout(r, 800));
  await shot("side_stop.png");

  // Full stick: run, then the stop.
  await drag(54, 754, 2, -22, 12, 21);
  await new Promise((r) => setTimeout(r, 900));
  await shot("side_run.png");
  await release();
  await new Promise((r) => setTimeout(r, 800));
  await shot("side_run_stop.png");

  // Same drag in the default camera (the picture the reviewer scored).
  await open("v=39&debug=1");
  await drag(54, 754, 3, -6, 10, 9);
  await new Promise((r) => setTimeout(r, 300));
  await shot("front_a.png");
  await new Promise((r) => setTimeout(r, 2500));
  await shot("front_b.png");
  await release();
  await new Promise((r) => setTimeout(r, 800));
  await shot("front_c.png");

  // Key spots already in the export: slope grass and dock deck.
  await open("v=39&debug=1&side=1&at=slope", 25);
  await shot("side_slope.png");
  // Eight headings on the grass rise, default camera, so the crest cannot hide the legs.
  await open("v=39&debug=1&at=slope", 20);
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
    await drag(90, 760, dx, dy, 8, 41);
    await new Promise((r) => setTimeout(r, 700));
    await shot(`slope_dir_${name}.png`);
    await release();
    await new Promise((r) => setTimeout(r, 250));
  }
  await open("v=39&debug=1&side=1&at=dock", 25);
  await shot("side_dock.png");

  await browser.close();
  server.close();
  console.log("SIDE_DONE");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
