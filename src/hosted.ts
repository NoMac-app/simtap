/**
 * What NoMac Simulator's host asks of a phone's session server besides tool calls (SIMULATOR_USE_HOSTED). The
 * server runs as the phone's pool user, the only user that may touch the account's workspace, so the sync's file
 * work happens here: hostd checks every request's shape first (mac-protocol's sim operation) and passes it on.
 */

import { createHash } from "node:crypto";
import { createReadStream, createWriteStream } from "node:fs";
import { chmod, lstat, lutimes, mkdir, readFile, rename, rm, unlink, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { Readable } from "node:stream";
import { pipeline } from "node:stream/promises";

import { run } from "./engine/exec.ts";

type Kind = "file" | "executable" | "symlink";
type Entry = { path: string; size: number; mtime_ms: number; sha256: string; kind?: Kind };
type Indexed = { size: number; mtime_ms: number; sha256: string; kind: Kind };
type Placed = { state: "running" | "done" | "failed"; root?: string; written?: number; removed?: number; error?: string };
type Sync = { project: string; pages: Map<number, Entry[]>; total: number; missing: Set<string>; place?: Placed };

const PROJECT = /^prj_[a-f0-9]{32}$/;
const SYNC = /^sync_[a-f0-9]{40}$/;
const SHA = /^[a-f0-9]{64}$/;
// A sync's pages wait here until its place; only the latest few are kept.
const KEEP_SYNCS = 8;
// place answers within this, or that it runs (hostd asks again).
let ANSWER_WITHIN_MS = 8_000;
export const setAnswerWithin = (ms: number) => (ANSWER_WITHIN_MS = ms);

let workspace: string | undefined;
const syncs = new Map<string, Sync>();

const invalid = (message: string) => Object.assign(new Error(message), { code: -32602 });
const absolute = (value: unknown): value is string =>
  typeof value === "string" && value.startsWith("/") && !value.includes("\0") && !value.split("/").includes("..") && value.length <= 1024;
const safePath = (path: unknown): path is string =>
  typeof path === "string" && path.length > 0 && !path.includes("\0") && !path.includes("\\") && path.split("/").every((part) => part !== "" && part !== "." && part !== "..");

/** The host tells a warm server, at hand-over, the account's build cache and workspace. */
export function configure(params: Record<string, unknown>): Record<string, never> {
  for (const key of ["cache_dir", "workspace"]) if (params[key] !== undefined && !absolute(params[key])) throw invalid(`${key} must be an absolute path`);
  if (params.cache_dir !== undefined) process.env.SIMULATOR_USE_CACHE_DIR = params.cache_dir as string;
  if (params.workspace !== undefined) workspace = params.workspace as string;
  return {};
}

const srcRoot = () => {
  if (!workspace) throw Object.assign(new Error("no_workspace"), { code: -32000 });
  return join(workspace, "src");
};
const indexFile = (project: string) => join(srcRoot(), ".nomac-sync", `${project}.json`);

async function readIndex(project: string): Promise<Record<string, Indexed>> {
  try {
    return JSON.parse(await readFile(indexFile(project), "utf8")) as Record<string, Indexed>;
  } catch {
    return {};
  }
}

/**
 * One page of the client's file list: answers the paths whose content this workspace lacks (new, changed, or
 * gone from the folder since the last sync).
 */
async function manifest(params: Record<string, unknown>): Promise<{ missing: string[] }> {
  const { id, project, page, pages, entries } = params as { id: unknown; project: unknown; page: unknown; pages: unknown; entries: unknown };
  if (typeof id !== "string" || !SYNC.test(id) || typeof project !== "string" || !PROJECT.test(project)) throw invalid("sync id or project");
  if (!Number.isInteger(page) || !Number.isInteger(pages) || (page as number) < 0 || (page as number) >= (pages as number) || !Array.isArray(entries)) throw invalid("page");
  for (const e of entries as Entry[]) if (!e || !safePath(e.path) || !SHA.test(e.sha256) || !Number.isInteger(e.size) || !Number.isInteger(e.mtime_ms)) throw invalid("entry");
  let sync = syncs.get(id);
  if (!sync) {
    sync = { project, pages: new Map(), total: pages as number, missing: new Set() };
    syncs.set(id, sync);
    while (syncs.size > KEEP_SYNCS) syncs.delete(syncs.keys().next().value!);
  }
  if (sync.project !== project || sync.total !== pages) throw invalid("the sync's project or page count changed");
  sync.pages.set(page as number, entries as Entry[]);
  const index = await readIndex(project);
  const root = join(srcRoot(), project);
  const missing: string[] = [];
  for (const e of entries as Entry[]) {
    const known = index[e.path];
    let present = false;
    if (known && known.sha256 === e.sha256 && known.kind === (e.kind ?? "file")) {
      present = await lstat(join(root, e.path)).then((st) => (known.kind === "symlink" ? st.isSymbolicLink() : st.isFile() && st.size === e.size), () => false);
    }
    if (!present) {
      missing.push(e.path);
      sync.missing.add(e.path);
    }
  }
  return { missing };
}

/**
 * Writes a sync into the workspace once all its pages arrived: the archive of the missing files (a gzip tar, given
 * inline or as a link), every file's mtime from the manifest (new mtimes alone make Xcode compile again), and the
 * removal of files the last sync had and this one does not. Nothing else in the folder is touched (dependencies
 * installed on the host, build output). Answers within a few seconds, or that it runs.
 */
async function place(params: Record<string, unknown>): Promise<Placed> {
  const id = params.id;
  const sync = typeof id === "string" ? syncs.get(id) : undefined;
  if (!sync) throw invalid("unknown sync: send its manifest first");
  if (sync.pages.size !== sync.total) throw invalid(`the manifest has ${sync.pages.size} of ${sync.total} pages`);
  if (!sync.place) {
    sync.place = { state: "running" };
    const placed = sync.place;
    write(sync, params.archive as Record<string, unknown> | undefined).then(
      (result) => Object.assign(placed, { state: "done" }, result),
      (error: Error) => Object.assign(placed, { state: "failed", error: error.message.slice(0, 300) }),
    );
  }
  const deadline = Date.now() + ANSWER_WITHIN_MS;
  while (sync.place.state === "running" && Date.now() < deadline) await new Promise((r) => setTimeout(r, 50));
  return { ...sync.place };
}

async function write(sync: Sync, archive: Record<string, unknown> | undefined): Promise<{ root: string; written: number; removed: number }> {
  const root = join(srcRoot(), sync.project);
  const work = join(srcRoot(), ".nomac-sync");
  await mkdir(root, { recursive: true });
  await mkdir(work, { recursive: true });
  const entries = [...sync.pages.values()].flat();
  if (archive) {
    const file = join(work, `archive-${process.pid}-${Date.now()}.tar.gz`);
    try {
      if (typeof archive.base64 === "string") {
        await writeFile(file, Buffer.from(archive.base64, "base64"));
      } else if (typeof archive.url === "string" && archive.url.startsWith("https://")) {
        const response = await fetch(archive.url);
        if (!response.ok || !response.body) throw new Error(`archive_download_failed: ${response.status}`);
        await pipeline(Readable.fromWeb(response.body as never), createWriteStream(file));
      } else {
        throw new Error("archive_invalid");
      }
      if (typeof archive.sha256 === "string") {
        const hash = createHash("sha256");
        await pipeline(createReadStream(file), hash);
        if (hash.digest("hex") !== archive.sha256) throw new Error("archive_checksum_mismatch");
      }
      // bsdtar keeps every entry inside root: it strips a leading / and refuses .. without -P.
      await run("/usr/bin/tar", ["-xzf", file, "-C", root], { timeoutMs: 10 * 60_000 });
    } finally {
      await unlink(file).catch(() => {});
    }
  }
  for (const e of entries) {
    const path = join(root, e.path);
    const kind = e.kind ?? "file";
    if (kind !== "symlink") await chmod(path, kind === "executable" ? 0o755 : 0o644).catch(() => {});
    const when = new Date(e.mtime_ms);
    await lutimes(path, when, when).catch(() => {});
  }
  const before = await readIndex(sync.project);
  const now = new Set(entries.map((e) => e.path));
  let removed = 0;
  for (const path of Object.keys(before)) {
    if (now.has(path) || !safePath(path)) continue;
    await rm(join(root, path), { force: true });
    removed++;
  }
  const index: Record<string, Indexed> = {};
  for (const e of entries) index[e.path] = { size: e.size, mtime_ms: e.mtime_ms, sha256: e.sha256, kind: e.kind ?? "file" };
  const tmp = `${indexFile(sync.project)}.tmp`;
  await mkdir(dirname(tmp), { recursive: true });
  await writeFile(tmp, JSON.stringify(index));
  await rename(tmp, indexFile(sync.project));
  return { root, written: sync.missing.size, removed };
}

/** A hosted method; anything else is not one. */
export async function hosted(method: string, params: Record<string, unknown>): Promise<unknown> {
  switch (method) {
    case "simulator-use/configure":
      return configure(params);
    case "simulator-use/sync":
      if (params.op === "manifest") return manifest(params);
      if (params.op === "place") return place(params);
      throw invalid("op is manifest or place");
  }
  throw Object.assign(new Error(`Method not found: ${method}`), { code: -32601 });
}
