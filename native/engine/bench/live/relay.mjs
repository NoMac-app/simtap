// Live-view prototype: the M6's hardware H.264 stream (engine `stream`, Annex B) relayed over SSH to a browser page
// that decodes it with WebCodecs; the page's clicks and keys go back to a second engine on the same phone.
// node relay.mjs <udid> [port]
import { spawn } from "node:child_process";
import { createServer } from "node:http";
import { readFileSync } from "node:fs";
import { WebSocketServer } from "ws";

const udid = process.argv[2];
const port = Number(process.argv[3] || 8790);
const E = "/usr/local/nomac-test/engine/simulator-use-engine";
const file = `/tmp/live-${Date.now()}.h264`;
const ssh = (cmd) => spawn("ssh", ["-o", "ServerAliveInterval=15", "nomac-us1", cmd], { stdio: ["pipe", "pipe", "inherit"] });

// The engine that encodes: its stream op writes the file for 600 s; tail follows it.
const streamer = ssh(`${E} --udid ${udid} --no-bootstrap`);
streamer.stdout.on("data", (d) => process.stdout.write(`[streamer] ${d}`));
streamer.stdin.write(JSON.stringify({ op: "stream", seconds: 600, fps: 30, scale: 0.5, bitrate: 1_500_000, keyframe_s: 2, path: file }) + "\n");

// The engine that acts: taps, swipes, typing; also used for round-trip pings.
const actor = ssh(`${E} --udid ${udid} --no-bootstrap`);
let actorBuf = "", pending = [];
actor.stdout.on("data", (d) => {
  actorBuf += d;
  let i;
  while ((i = actorBuf.indexOf("\n")) >= 0) {
    const line = actorBuf.slice(0, i); actorBuf = actorBuf.slice(i + 1);
    let a; try { a = JSON.parse(line); } catch { continue; }
    if (a.ready !== undefined) { console.log("[actor] ready", line.slice(0, 80)); continue; }
    const p = pending.shift(); if (p) p(a);
  }
});
const act = (req) => new Promise((resolve) => { pending.push(resolve); actor.stdin.write(JSON.stringify(req) + "\n"); });

// Annex B to access units: split at start codes, group NAL units into one chunk per picture.
let buf = Buffer.alloc(0), au = [], key = false, sps = null;
const clients = new Set();
function flush() {
  if (!au.length) return;
  const data = Buffer.concat(au.map((n) => Buffer.concat([Buffer.from([0, 0, 0, 1]), n])));
  const head = Buffer.alloc(1); head[0] = key ? 1 : 0;
  for (const c of clients) if (c.readyState === 1 && (c.gotKey || key)) { c.gotKey = true; c.send(Buffer.concat([head, data])); }
  au = []; key = false;
}
function onNal(n) {
  const type = n[0] & 0x1f;
  if (type === 7) { flush(); sps = n; for (const c of clients) if (!c.codecSent) sendCodec(c); }
  if (type === 9) { flush(); return; }
  if ((type === 1 || type === 5) && au.some((x) => (x[0] & 0x1f) === 1 || (x[0] & 0x1f) === 5) && (n[1] & 0x80)) flush(); // first_mb_in_slice == 0
  if (type === 5) key = true;
  au.push(n);
  if (type === 1 || type === 5) flush();
}
function sendCodec(c) {
  if (!sps) return;
  const codec = "avc1." + [sps[1], sps[2], sps[3]].map((b) => b.toString(16).padStart(2, "0")).join("");
  c.send(JSON.stringify({ codec })); c.codecSent = true;
}
const tail = ssh(`while [ ! -s ${file} ]; do sleep 0.1; done; exec tail -c +1 -f ${file}`);
tail.stdout.on("data", (d) => {
  buf = Buffer.concat([buf, d]);
  let start = -1, i = 0;
  const starts = [];
  for (i = 0; i + 3 < buf.length; i++) if (buf[i] === 0 && buf[i + 1] === 0 && (buf[i + 2] === 1 || (buf[i + 2] === 0 && buf[i + 3] === 1))) { starts.push(i); i += buf[i + 2] === 1 ? 2 : 3; }
  for (let k = 0; k + 1 < starts.length; k++) {
    const s = starts[k] + (buf[starts[k] + 2] === 1 ? 3 : 4);
    onNal(buf.subarray(s, starts[k + 1]));
  }
  if (starts.length) buf = buf.subarray(starts[starts.length - 1]);
});

const page = readFileSync(new URL("./page.html", import.meta.url));
const server = createServer((req, res) => { res.writeHead(200, { "content-type": "text/html" }); res.end(page); });
const wss = new WebSocketServer({ server, path: "/ws" });
wss.on("connection", (c) => {
  clients.add(c); sendCodec(c);
  c.on("message", async (m) => {
    const msg = JSON.parse(m);
    const t = Date.now();
    const a = await act(msg.req);
    c.send(JSON.stringify({ reply: msg.id, engine_ms: a.ms, relay_ms: Date.now() - t, ok: a.ok !== false }));
  });
  c.on("close", () => clients.delete(c));
});
server.listen(port, () => console.log(`live view on http://127.0.0.1:${port}/ (stream file ${file})`));
process.on("SIGINT", () => { for (const p of [streamer, actor, tail]) p.kill(); ssh(`rm -f ${file}`).on("exit", () => process.exit(0)); });
