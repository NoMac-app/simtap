// Opens the live view in headless Chrome and measures, through the whole path: frames, bitrate, round trips, and
// input-to-pixels latency for typed letters (Spotlight's field) and taps.
import { chromium } from "playwright-core";
const url = process.argv[2] || "http://127.0.0.1:8790/";
const browser = await chromium.launch({ executablePath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", headless: true });
const page = await browser.newPage({ viewport: { width: 500, height: 1000 } });
page.on("console", (m) => console.log("[page]", m.text()));
await page.goto(url);
await page.waitForFunction(() => window.stats && window.stats.frames > 5, null, { timeout: 60000 });
const t = Date.now(); await page.waitForTimeout(5000);
let st = await page.evaluate(() => ({ frames: window.stats.frames, bytes: window.stats.bytes, keys: window.stats.keys, errors: window.stats.decodeErrors }));
console.log("after 5 s:", st);
const p = (xs) => { const a = [...xs].sort((x, y) => x - y); return a.length ? `p50 ${a[Math.floor(a.length / 2)].toFixed(0)} ms, p90 ${a[Math.floor(a.length * 0.9)].toFixed(0)} ms, n ${a.length}` : "none"; };
// round trips through the relay to the acting engine (an unknown op answers at once, touching nothing)
for (let i = 0; i < 10; i++) await page.evaluate(() => window.send({ op: "ping" }));
const rtts = await page.evaluate(() => window.stats.rtts.map((r) => r.total));
console.log("round trip page to engine and back:", p(rtts));
// Spotlight: swipe down on the home screen, then type letters one at a time
await page.evaluate(() => window.send({ op: "home" }));
await page.waitForTimeout(1500);
await page.evaluate(() => window.send({ op: "swipe", x1: 201, y1: 400, x2: 201, y2: 700, duration: 0.25 }));
await page.waitForTimeout(2000);
const typed = [];
for (const ch of "nomacsimulator") { typed.push(await page.evaluate((ch) => window.send({ op: "type", text: ch }, true), ch)); await page.waitForTimeout(700); }
console.log("letter typed to pixels changed:", p(typed));
await page.evaluate(() => window.send({ op: "home" }));
await page.waitForTimeout(1500);
// taps on a home-screen icon (row 1, column 1), home in between
const taps = [];
for (let i = 0; i < 6; i++) { taps.push(await page.evaluate(() => window.send({ op: "tap", x: 64, y: 120 }, true))); await page.waitForTimeout(2500); await page.evaluate(() => window.send({ op: "home" })); await page.waitForTimeout(2500); }
console.log("icon tap to pixels changed:", p(taps));
st = await page.evaluate(() => ({ frames: window.stats.frames, bytes: window.stats.bytes, keys: window.stats.keys, errors: window.stats.decodeErrors, secs: (performance.now() - window.stats.started) / 1000 }));
console.log("total:", st, `${(st.bytes * 8 / 1000 / st.secs).toFixed(0)} kbit/s, ${(st.frames / st.secs).toFixed(1)} fps`);
await page.screenshot({ path: new URL("./live-shot.png", import.meta.url).pathname });
await browser.close();
