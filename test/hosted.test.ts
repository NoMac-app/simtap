import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

import { hosted, hostedText, setAnswerWithin } from "../src/hosted.ts";

const sha = (text: string) => createHash("sha256").update(text).digest("hex");
const project = "prj_" + "f".repeat(32);
let syncs = 0;
const syncId = () => "sync_" + (++syncs).toString(16).padStart(40, "0");

/** The client's side: the files as a manifest, and a gzip tar of the ones the host asked for. */
function client(files: Record<string, string>, mtime = 1_761_100_000_000) {
  const dir = mkdtempSync(join(tmpdir(), "su-client-"));
  for (const [path, text] of Object.entries(files)) {
    mkdirSync(join(dir, path, ".."), { recursive: true });
    writeFileSync(join(dir, path), text);
  }
  const entries = Object.entries(files).map(([path, text]) => ({ path, size: Buffer.byteLength(text), mtime_ms: mtime, sha256: sha(text), kind: path.endsWith(".sh") ? "executable" : "file" }));
  const archive = (paths: string[]) => {
    const out = join(dir, "..", `${dir.split("/").pop()}.tar.gz`);
    const r = spawnSync("/usr/bin/tar", ["-czf", out, "-C", dir, ...paths]);
    assert.equal(r.status, 0, String(r.stderr));
    const bytes = readFileSync(out);
    return { base64: bytes.toString("base64"), sha256: createHash("sha256").update(bytes).digest("hex") };
  };
  return { entries, archive };
}

async function sync(files: Record<string, string>, mtime?: number) {
  const id = syncId();
  const c = client(files, mtime);
  const { missing } = (await hosted("simulator-use/sync", { op: "manifest", id, project, page: 0, pages: 1, entries: c.entries })) as { missing: string[] };
  const placed = (await hosted("simulator-use/sync", { op: "place", id, ...(missing.length ? { archive: c.archive(missing) } : {}) })) as Record<string, unknown>;
  return { missing, placed };
}

test("the sync writes only what the workspace lacks, sets every mtime, and removes what the client deleted", async () => {
  const workspace = mkdtempSync(join(tmpdir(), "su-ws-"));
  await hosted("simulator-use/configure", { workspace, cache_dir: join(workspace, "cache") });
  const root = join(workspace, "src", project);
  const first = await sync({ "App/App.swift": "let a = 1\n", "App/Info.plist": "<plist/>", "run.sh": "echo hi\n" });
  assert.deepEqual(first.missing.sort(), ["App/App.swift", "App/Info.plist", "run.sh"]);
  assert.equal(first.placed.state, "done");
  assert.equal(first.placed.root, root);
  assert.equal(readFileSync(join(root, "App/App.swift"), "utf8"), "let a = 1\n");
  assert.equal(statSync(join(root, "App/App.swift")).mtimeMs, 1_761_100_000_000);
  assert.equal(statSync(join(root, "run.sh")).mode & 0o777, 0o755);
  assert.equal(statSync(join(root, "App/Info.plist")).mode & 0o777, 0o644);

  // Something the host built beside the source stays (dependencies, build output).
  mkdirSync(join(root, "Pods"), { recursive: true });
  writeFileSync(join(root, "Pods/lib.a"), "built here");

  const second = await sync({ "App/App.swift": "let a = 2\n", "run.sh": "echo hi\n" }, 1_761_100_100_000);
  assert.deepEqual(second.missing, ["App/App.swift"], "one file changed, one deleted, one the same");
  assert.equal(second.placed.state, "done");
  assert.equal(second.placed.removed, 1);
  assert.equal(readFileSync(join(root, "App/App.swift"), "utf8"), "let a = 2\n");
  assert.equal(existsSync(join(root, "App/Info.plist")), false, "deleted on the client");
  assert.equal(statSync(join(root, "run.sh")).mtimeMs, 1_761_100_100_000, "an unchanged file still gets the client's mtime");
  assert.equal(readFileSync(join(root, "Pods/lib.a"), "utf8"), "built here");

  // A file the build removed from the folder is asked for again.
  spawnSync("rm", [join(root, "run.sh")]);
  const third = await sync({ "App/App.swift": "let a = 2\n", "run.sh": "echo hi\n" });
  assert.deepEqual(third.missing, ["run.sh"]);
  assert.ok(lstatSync(join(root, "run.sh")).isFile());
});

test("a place before every page arrived, an archive that is not the one announced, and paths outside are refused", async () => {
  const workspace = mkdtempSync(join(tmpdir(), "su-ws-"));
  await hosted("simulator-use/configure", { workspace });
  const id = syncId();
  const c = client({ "a.txt": "a" });
  await hosted("simulator-use/sync", { op: "manifest", id, project, page: 0, pages: 2, entries: c.entries });
  await assert.rejects(hosted("simulator-use/sync", { op: "place", id }), /1 of 2 pages/);
  const other = syncId();
  await hosted("simulator-use/sync", { op: "manifest", id: other, project, page: 0, pages: 1, entries: c.entries });
  const archive = c.archive(["a.txt"]);
  const placed = (await hosted("simulator-use/sync", { op: "place", id: other, archive: { ...archive, sha256: "0".repeat(64) } })) as Record<string, unknown>;
  assert.equal(placed.state, "failed");
  assert.match(String(placed.error), /archive_checksum_mismatch/);
  for (const path of ["../x", "/etc/passwd", "a//b", "a\\b"]) {
    await assert.rejects(hosted("simulator-use/sync", { op: "manifest", id: syncId(), project, page: 0, pages: 1, entries: [{ ...c.entries[0], path }] }), /entry/);
  }
  await assert.rejects(hosted("simulator-use/sync", { op: "manifest", id: syncId(), project: "../x", page: 0, pages: 1, entries: [] }), /project/);
  await assert.rejects(hosted("simulator-use/sync", { op: "place", id: syncId() }), /unknown sync/);
});

test("a long place answers that it runs, and the same place again reads it", async () => {
  const workspace = mkdtempSync(join(tmpdir(), "su-ws-"));
  await hosted("simulator-use/configure", { workspace });
  setAnswerWithin(0);
  try {
    const id = syncId();
    const c = client({ "b.txt": "b" });
    await hosted("simulator-use/sync", { op: "manifest", id, project, page: 0, pages: 1, entries: c.entries });
    const archive = c.archive(["b.txt"]);
    const first = (await hosted("simulator-use/sync", { op: "place", id, archive })) as Record<string, unknown>;
    assert.equal(first.state, "running");
    setAnswerWithin(5_000);
    const again = (await hosted("simulator-use/sync", { op: "place", id, archive })) as Record<string, unknown>;
    assert.equal(again.state, "done");
  } finally {
    setAnswerWithin(8_000);
  }
});

test("a place whose archive lacks a requested file fails, and the next manifest asks for it again", async () => {
  // A client that splits a large first sync over several archives must not leave files the index claims.
  const workspace = mkdtempSync(join(tmpdir(), "su-ws-"));
  await hosted("simulator-use/configure", { workspace });
  const root = join(workspace, "src", project);
  const files = { "A.swift": "let a = 1\n", "B.swift": "let b = 1\n" };
  const c = client(files);
  const id = syncId();
  const { missing } = (await hosted("simulator-use/sync", { op: "manifest", id, project, page: 0, pages: 1, entries: c.entries })) as { missing: string[] };
  assert.deepEqual(missing.sort(), ["A.swift", "B.swift"]);
  const half = (await hosted("simulator-use/sync", { op: "place", id, archive: c.archive(["A.swift"]) })) as Record<string, unknown>;
  assert.equal(half.state, "failed");
  assert.match(String(half.error), /archive_incomplete: 1 of the 2 files asked for .*B\.swift \(not in the archive\)/);
  const again = (await hosted("simulator-use/sync", { op: "manifest", id: syncId(), project, page: 0, pages: 1, entries: c.entries })) as { missing: string[] };
  assert.deepEqual(again.missing.sort(), ["A.swift", "B.swift"], "the index took nothing from the failed place");
  const whole = await sync(files);
  assert.equal(whole.placed.state, "done");
  assert.equal(readFileSync(join(root, "B.swift"), "utf8"), "let b = 1\n");
});

test("an archive with other content than announced, or a file nobody asked for, is refused", async () => {
  const workspace = mkdtempSync(join(tmpdir(), "su-ws-"));
  await hosted("simulator-use/configure", { workspace });
  const root = join(workspace, "src", project);
  // Content that is not what the manifest announced.
  const announced = client({ "C.swift": "let c = 1\n" });
  const sent = client({ "C.swift": "let c = 2\n" });
  const id = syncId();
  await hosted("simulator-use/sync", { op: "manifest", id, project, page: 0, pages: 1, entries: announced.entries });
  const differs = (await hosted("simulator-use/sync", { op: "place", id, archive: sent.archive(["C.swift"]) })) as Record<string, unknown>;
  assert.equal(differs.state, "failed");
  assert.match(String(differs.error), /archive_incomplete: .*C\.swift \(different content\)/);
  // A file the manifest did not ask for is never written.
  const asked = client({ "D.swift": "let d = 1\n" });
  const extra = client({ "D.swift": "let d = 1\n", "Extra.swift": "let x = 1\n" });
  const other = syncId();
  await hosted("simulator-use/sync", { op: "manifest", id: other, project, page: 0, pages: 1, entries: asked.entries });
  const unasked = (await hosted("simulator-use/sync", { op: "place", id: other, archive: extra.archive(["D.swift", "Extra.swift"]) })) as Record<string, unknown>;
  assert.equal(unasked.state, "failed");
  assert.match(String(unasked.error), /archive_unexpected: Extra\.swift was not asked for/);
  assert.equal(existsSync(join(root, "Extra.swift")), false);
});

test("answers read project paths relative to the project, and the host's other files as ids that get uploads", async () => {
  const workspace = mkdtempSync(join(tmpdir(), "su-ws-"));
  const cache = join(workspace, "cache");
  await hosted("simulator-use/configure", { workspace, cache_dir: cache });
  const root = join(workspace, "src", project);
  const log = join(cache, "DerivedData", "Demo-7f063f2e7788", "build-1.log");
  mkdirSync(join(log, ".."), { recursive: true });
  writeFileSync(log, "the build log");
  const text = [
    `Build of Demo failed after 1.1 s with 1 error. Full log: ${log}`,
    `${root}/Sources/App.swift:48:30: error: cannot find 'undefinedName' in scope`,
    "/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/x.h:1:1: warning: from the SDK",
    `${root} does not exist.`,
    `A recording that is gone: ${join(cache, "gone.mp4")}.`,
  ].join("\n");
  const out = hostedText(text).split("\n");
  const id = /Full log: (file_[a-f0-9]{40})\/build-1\.log$/.exec(out[0]!)?.[1];
  assert.ok(id, out[0]);
  assert.equal(out[1], "Sources/App.swift:48:30: error: cannot find 'undefinedName' in scope");
  assert.match(out[2]!, /^\/Applications\/Xcode\.app/, "a path outside the host's own folders stays");
  assert.equal(out[3], ". does not exist.");
  assert.equal(out[4], `A recording that is gone: ${join(cache, "gone.mp4")}.`, "only files that exist become ids");
  assert.equal(hostedText(`Full log: ${log}`), `Full log: ${id}/build-1.log`, "the same file, the same id");

  // get uploads that file to the link NoMac signed.
  const sent: { url: string; method?: string; length: string | null; body: string }[] = [];
  const realFetch = globalThis.fetch;
  let storage = 200;
  globalThis.fetch = (async (url: string, init?: RequestInit) => {
    const headers = new Headers(init?.headers);
    sent.push({ url: String(url), method: init?.method, length: headers.get("content-length"), body: Buffer.from(await new Response(init?.body).arrayBuffer()).toString() });
    return new Response(null, { status: storage });
  }) as typeof fetch;
  try {
    const got = (await hosted("simulator-use/get", { id: `get_${"1".repeat(40)}`, file: id, url: "https://r2.example.test/put" })) as Record<string, unknown>;
    assert.deepEqual(got, { state: "done", size: 13 });
    assert.deepEqual(sent, [{ url: "https://r2.example.test/put", method: "PUT", length: "13", body: "the build log" }]);
    // The same id answers the upload it started, and uploads nothing again.
    assert.deepEqual(await hosted("simulator-use/get", { id: `get_${"1".repeat(40)}`, file: id, url: "https://r2.example.test/put" }), { state: "done", size: 13 });
    assert.equal(sent.length, 1);
    storage = 403;
    const refused = (await hosted("simulator-use/get", { id: `get_${"4".repeat(40)}`, file: id, url: "https://r2.example.test/put" })) as Record<string, unknown>;
    assert.equal(refused.state, "failed");
    assert.match(String(refused.error), /^upload_failed: storage answered 403/);
    await assert.rejects(hosted("simulator-use/get", { id: `get_${"2".repeat(40)}`, file: `file_${"0".repeat(40)}`, url: "https://r2.example.test/put" }), /file_not_found/);
    await assert.rejects(hosted("simulator-use/get", { id: `get_${"3".repeat(40)}`, file: id, url: "http://r2.example.test/put" }), /get id, file or url/);
  } finally {
    globalThis.fetch = realFetch;
  }
});

test("the pool's warm-up runs only before the hand-over, and a stop with none running answers so", async () => {
  // Configured (handed over): a warm-up now would build beside the customer's own work.
  await hosted("simulator-use/configure", { workspace: mkdtempSync(join(tmpdir(), "su-ws-")) });
  await assert.rejects(hosted("simulator-use/warm", {}), /the warm-up runs before the hand-over/);
  assert.deepEqual(await hosted("simulator-use/warm", { stop: true }), { ok: true, ms: 0, stopped: false });
});
