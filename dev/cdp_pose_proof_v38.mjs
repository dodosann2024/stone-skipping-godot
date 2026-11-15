#!/usr/bin/env node
/**
 * Prove which pose path the web Compatibility renderer draws.
 *   ?poseproof=lift     — FootIK modifier adds +42 cm to the left foot
 *   ?poseproof=override — modifier skipped; set_bone_global_pose_override +42 cm
 * Screenshots are the evidence. A raised left shoe means that channel is skinned.
 */
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { spawn } from "node:child_process";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "..");
const OUT = path.join(ROOT, "screenshots/v38");
const DIR = path.join(ROOT, "docs/game_v38");
fs.mkdirSync(OUT, { recursive: true });

function startStatic(dir, port) {
  return new Promise((resolve) => {
    const server = http.createServer((req, res) => {
      let urlPath = decodeURIComponent((req.url || "/").split("?")[0]);
      if (urlPath === "/") urlPath = "/game_v38.html";
      const file = path.join(dir, urlPath);
      if (!file.startsWith(dir) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) {
        res.writeHead(404); res.end("no"); return;
      }
      const ext = path.extname(file);
      const type = ext === ".html" ? "text/html" : ext === ".js" ? "application/javascript" : ext === ".wasm" ? "application/wasm" : "application/octet-stream";
      res.writeHead(200, { "Content-Type": type });
      fs.createReadStream(file).pipe(res);
    });
    server.listen(port, "127.0.0.1", () => resolve(server));
  });
}

async function shot(page, name) {
  const p = path.join(OUT, name);
  await page.screenshot({ path: p, type: "png" });
  console.log("PROOF_SHOT", p);
}

async function main() {
  let puppeteer;
  try { puppeteer = await import("puppeteer-core"); }
  catch {
    await new Promise((res, rej) => {
      const c = spawn("npm", ["install", "--no-save", "puppeteer-core@23"], { cwd: ROOT, stdio: "inherit" });
      c.on("exit", (code) => (code === 0 ? res() : rej(new Error("npm"))));
    });
    puppeteer = await import("puppeteer-core");
  }
  const server = await startStatic(DIR, 18922);
  const browser = await puppeteer.default.launch({
    executablePath: process.env.CHROME_PATH || "/usr/bin/google-chrome-stable",
    headless: true,
    args: ["--window-size=390,844", "--no-sandbox", "--enable-webgl", "--ignore-gpu-blocklist", "--use-gl=angle", "--use-angle=swiftshader-webgl", "--enable-unsafe-swiftshader"],
  });
  for (const mode of ["lift", "override"]) {
    const page = await browser.newPage();
    await page.setViewport({ width: 390, height: 844, deviceScaleFactor: 2, isMobile: true, hasTouch: true });
    const url = `http://127.0.0.1:18922/game_v38.html?v=38&debug=1&poseproof=${mode}`;
    console.log("PROOF open", url);
    await page.goto(url, { waitUntil: "domcontentloaded", timeout: 180000 });
    await page.waitForSelector("canvas", { timeout: 180000 });
    await new Promise((r) => setTimeout(r, 14000));
    const g = await page.evaluate(() => window.__ground || null);
    console.log("PROOF", mode, JSON.stringify(g));
    await shot(page, `cdp_proof_${mode}.png`);
    await page.close();
  }
  await browser.close();
  server.close();
}

main().catch((e) => { console.error(e); process.exit(1); });
