import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

import { hosted, setAnswerWithin } from "../src/hosted.ts";

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
