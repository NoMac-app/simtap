import { readdir } from "node:fs/promises";
import { join } from "node:path";

import { ToolError } from "../errors.ts";
import { run } from "./exec.ts";

/** An Xcode installed on this Mac. default: the one builds use unless asked (DEVELOPER_DIR, else xcode-select). */
export type Xcode = { version: string; build: string; path: string; developer: string; beta: boolean; default: boolean };

let cached: { at: number; list: Xcode[] } | undefined;
const CACHE_MS = 60_000;
/** Where Xcodes are looked for; tests point it elsewhere. */
let applications = "/Applications";
export function setApplicationsDir(dir: string) {
  applications = dir;
  cached = undefined;
}

const plist = async (file: string, key: string) => (await run("/usr/bin/plutil", ["-extract", key, "raw", file], { timeoutMs: 5_000 })).stdout.trim();

const newer = (a: string, b: string) => {
  const x = a.split(".").map(Number), y = b.split(".").map(Number);
  for (let i = 0; i < Math.max(x.length, y.length); i++) if ((x[i] ?? 0) !== (y[i] ?? 0)) return (x[i] ?? 0) - (y[i] ?? 0);
  return 0;
};

/** The Xcodes in /Applications (Xcode*.app), newest first, releases before a beta of the same version. */
export async function listXcodes(): Promise<Xcode[]> {
  if (cached && Date.now() - cached.at < CACHE_MS) return cached.list;
  const names = (await readdir(applications).catch(() => [] as string[])).filter((name) => /^Xcode.*\.app$/.test(name));
  const selected = process.env.DEVELOPER_DIR || (await run("xcode-select", ["-p"], { timeoutMs: 5_000 }).then((o) => o.stdout.trim()).catch(() => ""));
  const list: Xcode[] = [];
  for (const name of names) {
    const path = join(applications, name);
    try {
      const version = await plist(join(path, "Contents", "Info.plist"), "CFBundleShortVersionString");
      const build = await plist(join(path, "Contents", "version.plist"), "ProductBuildVersion").catch(() => "");
      // Named so: Apple's betas expand to Xcode-beta.app (a build number cannot tell: 27.0's release is 27A266a).
      const beta = /beta|release.?candidate|[-_ ]rc\b/i.test(name);
      list.push({ version, build, path, developer: join(path, "Contents", "Developer"), beta, default: Boolean(selected) && (selected === path || selected.startsWith(`${path}/`)) });
    } catch {
      // Not an Xcode (or not readable): left out.
    }
  }
  list.sort((a, b) => newer(b.version, a.version) || Number(a.beta) - Number(b.beta));
  cached = { at: Date.now(), list };
  return list;
}

/** The Xcodes as an answer names them: "27.1, 27.0 (default), 26.6, 27.2 beta". */
export const describeXcodes = (list: Xcode[]) => list.map((x) => `${x.version}${x.beta ? " beta" : ""}${x.default ? " (default)" : ""}`).join(", ");

/**
 * The Xcode a call asked for: a version ("27.1"; "27" is the newest 27 release), "beta" for the newest beta, or
 * "default". Nothing asked, nothing picked: builds use the default.
 */
export async function pickXcode(wanted: string | undefined): Promise<Xcode | undefined> {
  if (!wanted?.trim()) return undefined;
  const list = await listXcodes();
  const w = wanted.trim().toLowerCase().replace(/^xcode\s*/, "");
  if (w === "default") return list.find((x) => x.default);
  const found = w === "beta"
    ? list.find((x) => x.beta)
    : list.find((x) => x.version === w && !x.beta) ?? list.find((x) => !x.beta && x.version.startsWith(`${w}.`)) ?? list.find((x) => x.version === w);
  if (!found) {
    throw new ToolError(
      `No Xcode ${wanted} on this Mac.`,
      list.length ? `Pass one of: ${describeXcodes(list)}; or leave xcode out for the default.` : "Leave xcode out: this Mac's Xcodes could not be listed.",
    );
  }
  return found;
}
