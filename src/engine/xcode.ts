import { spawn } from "node:child_process";
import { createHash } from "node:crypto";
import { createWriteStream, existsSync, readdirSync, realpathSync } from "node:fs";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { basename, dirname, extname, join, relative, resolve } from "node:path";

import { ToolError } from "../errors.ts";
import { run } from "./exec.ts";
import { stateDir } from "./state.ts";

export type Project = { kind: "workspace" | "project"; path: string; name: string; dir: string; generated?: boolean; note?: string };

/**
 * The Xcode project in a folder: a workspace first (CocoaPods and multi-project setups need it), then a
 * project; an XcodeGen spec is generated first, and again before every build. Other kinds say what is coming.
 */
export async function findProject(where: string): Promise<Project> {
  const path = resolve(where);
  if (!existsSync(path)) throw new ToolError(`${path} does not exist.`, "Pass path: the folder with the Xcode project.");
  const ext = extname(path);
  if (ext === ".xcworkspace") return { kind: "workspace", path, name: basename(path, ext), dir: dirname(path) };
  if (ext === ".xcodeproj") {
    const dir = dirname(path);
    const note = existsSync(join(dir, "project.yml")) ? await xcodegen(dir, true) : undefined;
    return { kind: "project", path, name: basename(path, ext), dir, note };
  }
  const entries = readdirSync(path);
  // A workspace is left as it is: regenerating its project would undo what CocoaPods added to it.
  const workspace = entries.find((e) => e.endsWith(".xcworkspace"));
  if (workspace) return { kind: "workspace", path: join(path, workspace), name: basename(workspace, ".xcworkspace"), dir: path };
  const project = entries.find((e) => e.endsWith(".xcodeproj"));
  if (entries.includes("project.yml")) {
    const note = await xcodegen(path, Boolean(project));
    const made = readdirSync(path).find((e) => e.endsWith(".xcodeproj"));
    if (made) return { kind: "project", path: join(path, made), name: basename(made, ".xcodeproj"), dir: path, generated: !project, note };
  }
  if (project) return { kind: "project", path: join(path, project), name: basename(project, ".xcodeproj"), dir: path };
  if (entries.includes("app.json") || entries.includes("pubspec.yaml") || entries.some((e) => e.startsWith("capacitor.config"))) {
    throw new ToolError("Expo, React Native, Flutter and Capacitor projects are not built by app_run yet; Xcode projects are.", "Build it with its own tool for the iOS Simulator, then app_control {action: \"install\", app: \"path/to/App.app\"}.");
  }
  if (entries.includes("ios") && existsSync(join(path, "ios"))) return findProject(join(path, "ios"));
  throw new ToolError(`No Xcode project in ${path}.`, "Pass path: the folder with the .xcodeproj or .xcworkspace.");
}

/**
 * XcodeGen makes the project from project.yml, and a spec edit or a new, moved or deleted source file needs a new
 * project, or the build misses it. So the project is regenerated before every build; --use-cache skips the work when
 * neither the spec nor the files changed. Answers a note when an existing project had to be built as it was.
 */
async function xcodegen(dir: string, hasProject: boolean): Promise<string | undefined> {
  try {
    await run("xcodegen", ["generate", "--quiet", "--use-cache", "--spec", join(dir, "project.yml")], { timeoutMs: 60_000 });
    return undefined;
  } catch (error) {
    const why = ((error as Error).message.split("\n")[0] ?? "").slice(0, 200);
    if (!hasProject) throw new ToolError(`This folder has an XcodeGen spec (project.yml) but no project, and xcodegen failed: ${why}`, "Install XcodeGen (brew install xcodegen), or generate the project yourself.");
    return `XcodeGen could not regenerate the project from project.yml (${why}), so the existing project was built; spec edits and new files are not in it.`;
  }
}

/** The scheme to build: the one asked for, the only one, or the one named like the project. */
export async function pickScheme(project: Project, wanted?: string): Promise<string> {
  const { stdout } = await run("xcodebuild", ["-list", "-json", project.kind === "workspace" ? "-workspace" : "-project", project.path], { timeoutMs: 60_000 });
  const list = JSON.parse(stdout) as { project?: { schemes?: string[] }; workspace?: { schemes?: string[] } };
  const schemes = list.workspace?.schemes ?? list.project?.schemes ?? [];
  if (wanted) {
    if (!schemes.includes(wanted)) throw new ToolError(`No scheme "${wanted}" in ${basename(project.path)}. Schemes: ${schemes.join(", ") || "none"}.`);
    return wanted;
  }
  const own = schemes.filter((s) => !/^Pods-|Tests$|UITests$/.test(s));
  if (own.length === 1) return own[0]!;
  const named = own.find((s) => s === project.name);
  if (named) return named;
  if (!schemes.length) throw new ToolError(`${basename(project.path)} has no shared schemes.`, "Open it in Xcode once, or share a scheme (Product > Scheme > Manage Schemes).");
  throw new ToolError(`${basename(project.path)} has several schemes: ${own.join(", ")}.`, "Pass scheme.");
}

export type Issue = { file?: string; line?: number; column?: number; severity: "error" | "warning"; message: string };

const LOCATED = /^(\/[^:]+):(\d+):(?:(\d+):)? (error|warning|fatal error): (.+)$/;
const BARE = /^(?:xcodebuild: |clang: |ld: |\s*)?(error|fatal error): (.+)$/;

/** One line of xcodebuild output as an error or warning, or nothing. */
export function parseIssue(line: string): Issue | undefined {
  const located = LOCATED.exec(line);
  if (located) {
    const [, file, row, col, severity, message] = located;
    return { file, line: Number(row), column: col ? Number(col) : undefined, severity: severity === "warning" ? "warning" : "error", message: message!.trim() };
  }
  const bare = BARE.exec(line);
  if (bare) return { severity: "error", message: bare[2]!.trim() };
  if (/^ld: /.test(line) || /^Undefined symbols? for architecture/.test(line)) return { severity: "error", message: line.trim() };
  return undefined;
}

/** `Sources/App.swift:49:37`, relative to the project when the file is inside it, else absolute. */
export function place(file: string, line: number | undefined, column: number | undefined, base: string): string {
  const real = (p: string) => {
    try {
      return realpathSync(p);
    } catch {
      return p;
    }
  };
  // /tmp and /private/tmp are the same folder; compare real paths so the file reads relative.
  const rel = relative(real(base), real(file));
  return `${rel && !rel.startsWith("..") ? rel : file}:${line ?? "?"}${column ? `:${column}` : ""}`;
}

/** `Sources/App.swift:49:37: error: ...`. */
export function formatIssue(issue: Issue, base: string): string {
  return `${issue.file ? `${place(issue.file, issue.line, issue.column, base)}: ` : ""}${issue.severity}: ${issue.message}`;
}

/**
 * Where builds keep their products: SIMTAP_CACHE_DIR when set (a disk kept between machines, such as
 * NoMac's ~/drive, makes the next machine's build incremental), else simtap's own folder.
 */
export const cacheDir = () => process.env.SIMTAP_CACHE_DIR || stateDir();

/** Each worktree builds into its own DerivedData, so builds stay incremental and never share products. */
export function derivedDataFor(project: Project): string {
  const key = createHash("sha1").update(project.path).digest("hex").slice(0, 12);
  return join(cacheDir(), "DerivedData", `${project.name}-${key}`);
}

export type BuildResult = { ok: boolean; errors: Issue[]; warnings: number; log: string; ms: number; tail: string[] };

export async function build(
  project: Project,
  scheme: string,
  udid: string,
  options: { configuration?: string; clean?: boolean; action?: "build" | "test"; extra?: string[]; onLine?: (line: string) => void; onCancel?: (cancel: () => void) => void },
): Promise<BuildResult> {
  const derived = derivedDataFor(project);
  await mkdir(derived, { recursive: true });
  const log = join(derived, `${options.action ?? "build"}-${Date.now()}.log`);
  const args = [
    project.kind === "workspace" ? "-workspace" : "-project",
    project.path,
    "-scheme",
    scheme,
    "-configuration",
    options.configuration ?? "Debug",
    "-destination",
    `id=${udid}`,
    "-derivedDataPath",
    derived,
    ...(options.extra ?? []),
    ...(options.clean ? ["clean"] : []),
    options.action ?? "build",
  ];
  const started = Date.now();
  const out = createWriteStream(log);
  // Its own process group, so a cancel stops the compilers it started too.
  const child = spawn("xcodebuild", args, { cwd: project.dir, detached: true, stdio: ["ignore", "pipe", "pipe"] });
  options.onCancel?.(() => {
    try {
      process.kill(-child.pid!, "SIGTERM");
    } catch {
      // Already finished.
    }
  });
  const seen = new Set<string>();
  const errors: Issue[] = [];
  let warnings = 0;
  let pending = "";
  const tail: string[] = [];
  const take = (chunk: Buffer) => {
    out.write(chunk);
    pending += chunk.toString("utf8");
    const lines = pending.split("\n");
    pending = lines.pop() ?? "";
    for (const line of lines) {
      options.onLine?.(line);
      if (line.trim()) {
        tail.push(line.length > 200 ? `${line.slice(0, 199)}…` : line);
        if (tail.length > 8) tail.shift();
      }
      const issue = parseIssue(line);
      if (!issue) continue;
      // The same diagnostic repeats (once per architecture or compile batch).
      const key = `${issue.file}:${issue.line}:${issue.severity}:${issue.message}`;
      if (seen.has(key)) continue;
      seen.add(key);
      if (issue.severity === "warning") warnings++;
      else errors.push(issue);
    }
  };
  child.stdout.on("data", take);
  child.stderr.on("data", take);
  const code = await new Promise<number | null>((resolveCode) => child.on("close", resolveCode));
  out.end();
  return { ok: code === 0, errors, warnings, log, ms: Date.now() - started, tail };
}

/** The .app a Simulator build made: the scheme's own, never a test runner. */
export function builtApp(project: Project, scheme: string, configuration = "Debug"): string | undefined {
  const products = join(derivedDataFor(project), "Build", "Products", `${configuration}-iphonesimulator`);
  if (!existsSync(products)) return undefined;
  const apps = readdirSync(products).filter((e) => e.endsWith(".app") && !e.endsWith("-Runner.app"));
  const named = apps.find((a) => a === `${scheme}.app`);
  return named || apps.length === 1 ? join(products, named ?? apps[0]!) : undefined;
}

/** What app_run remembers per folder, so the next call needs no arguments. */
export type Remembered = { project: string; scheme: string; bundleId?: string };

const memoryFile = async (dir: string) => {
  const folder = join(stateDir(), "projects");
  await mkdir(folder, { recursive: true });
  return join(folder, `${createHash("sha1").update(resolve(dir)).digest("hex").slice(0, 16)}.json`);
};

export async function remembered(dir: string): Promise<Remembered | undefined> {
  try {
    return JSON.parse(await readFile(await memoryFile(dir), "utf8")) as Remembered;
  } catch {
    return undefined;
  }
}

export async function remember(dir: string, value: Remembered): Promise<void> {
  await writeFile(await memoryFile(dir), JSON.stringify(value));
}

/** The project the last app_run or tests_run used, for calls that name none from a folder without one. */
export async function lastProject(): Promise<string | undefined> {
  try {
    return (JSON.parse(await readFile(join(stateDir(), "last-project.json"), "utf8")) as { project: string }).project;
  } catch {
    return undefined;
  }
}

export async function setLastProject(project: string): Promise<void> {
  await mkdir(stateDir(), { recursive: true });
  await writeFile(join(stateDir(), "last-project.json"), JSON.stringify({ project }));
}

/**
 * Which project a call means: the path given; else the current folder's (or what app_run remembered for it);
 * else the one the last call used, so an agent that named a path once can drop it.
 */
export async function projectFor(path: string | undefined, scheme: string | undefined): Promise<{ project: Project; scheme: string; dir: string; note: string }> {
  const dir = path ?? process.cwd();
  const memory = await remembered(dir);
  let project: Project;
  let note = "";
  try {
    project = await findProject(memory && !path ? memory.project : dir);
  } catch (error) {
    const last = path ? undefined : await lastProject();
    if (!last || !existsSync(last)) throw error;
    project = await findProject(last);
    note = `No project in ${dir}; using ${project.name} from the last call (${project.dir}).\n`;
  }
  if (project.note) note += `${project.note}\n`;
  const rememberedScheme = memory?.project === project.path ? memory.scheme : (await remembered(project.dir))?.scheme;
  const chosen = await pickScheme(project, scheme ?? rememberedScheme);
  await setLastProject(project.path);
  return { project, scheme: chosen, dir: path ? dir : project.dir, note };
}
