import { type ChildProcess, spawn } from "node:child_process";
import { existsSync } from "node:fs";
import { createInterface } from "node:readline";
import { fileURLToPath } from "node:url";

import { setting } from "../settings.ts";

/**
 * The native engine (native/engine): one long-lived process per booted Simulator that keeps CoreSimulator's
 * HID connection, accessibility and screen buffer open, so a tap is about a millisecond and a full read a few
 * hundred, where AXe pays one to three seconds per call to set up. When it is missing or fails, every caller
 * falls back to AXe. It sits beside AXe's frameworks (vendor/axe), which it loads; SIMULATOR_USE_ENGINE points
 * at another build, or "off" turns it off.
 */
export function enginePath(): string | undefined {
  const override = setting("ENGINE");
  if (override === "off" || override === "0") return undefined;
  if (override) return override;
  const bundled = fileURLToPath(new URL("../../vendor/axe/simulator-use-engine", import.meta.url));
  return existsSync(bundled) ? bundled : undefined;
}

export type Answer = Record<string, unknown> & { ok?: boolean; error?: string; busy?: boolean };

const START_MS = 15_000;
/**
 * An engine that answers nothing for this long is hung, and is ended. A request merely slower than its caller's
 * wait never ends it: a new engine on a phone booted minutes ago cannot open an automation session (measured), so
 * ending a slow one left the phone unreadable (a web field's first read took 4.2 s against a 3 s wait).
 */
const HUNG_MS = 120_000;

class Engine {
  private readonly child: ChildProcess;
  private readonly lines: AsyncIterator<string>;
  private queue: Promise<unknown> = Promise.resolve();
  dead = false;
  readonly ready: Promise<boolean>;

  constructor(path: string, udid: string) {
    this.child = spawn(path, ["--udid", udid], { stdio: ["pipe", "pipe", "ignore"] });
    // The engine closes its automation session when its input ends, so a CLI process may exit at any time:
    // nothing here keeps Node alive, and the engine finishes on its own.
    this.child.unref();
    (this.child.stdin as unknown as { unref?: () => void })?.unref?.();
    (this.child.stdout as unknown as { unref?: () => void })?.unref?.();
    this.child.on("exit", () => (this.dead = true));
    this.child.on("error", () => (this.dead = true));
    this.lines = createInterface({ input: this.child.stdout! })[Symbol.asyncIterator]();
    this.ready = this.next(START_MS).then((line) => {
      const ready = parse(line);
      if (!ready?.ready) this.kill();
      return Boolean(ready?.ready);
    }, () => (this.kill(), false));
  }

  private async next(timeoutMs: number): Promise<string> {
    let timer: NodeJS.Timeout | undefined;
    try {
      const line = await Promise.race([
        this.lines.next(),
        new Promise<never>((_, reject) => (timer = setTimeout(() => reject(new Error("the engine did not answer in time")), timeoutMs))),
      ]);
      if (line.done) throw new Error("the engine stopped");
      return line.value;
    } finally {
      clearTimeout(timer);
    }
  }

  /**
   * One request at a time, in order. A caller waits timeoutMs and then gets a busy answer, while the engine
   * finishes: the next request still waits for this one's answer, which is read and dropped, so answers stay paired
   * with their requests and the engine stays.
   */
  call(request: Record<string, unknown>, timeoutMs: number): Promise<Answer> {
    const answer = this.queue.then(async () => {
      if (this.dead) throw new Error("the engine stopped");
      this.child.stdin!.write(`${JSON.stringify(request)}\n`);
      try {
        return parse(await this.next(HUNG_MS)) ?? { ok: false, error: "unreadable answer" };
      } catch (error) {
        this.kill();
        throw error;
      }
    });
    this.queue = answer.catch(() => undefined);
    let timer: NodeJS.Timeout | undefined;
    const late = new Promise<Answer>((resolve) => {
      timer = setTimeout(() => resolve({ ok: false, busy: true, error: `no answer within ${timeoutMs} ms` }), timeoutMs);
      timer.unref();
    });
    return Promise.race([answer, late]).finally(() => clearTimeout(timer));
  }

  kill(): void {
    this.dead = true;
    this.child.stdin?.end();
    setTimeout(() => this.child.kill(), 2_000).unref();
  }
}

function parse(line: string): Answer | undefined {
  try {
    return JSON.parse(line) as Answer;
  } catch {
    return undefined;
  }
}

const engines = new Map<string, Engine>();
/** Phones whose engine would not start: AXe for the rest of this process. */
const unavailable = new Set<string>();

async function engineFor(udid: string): Promise<Engine | undefined> {
  const path = enginePath();
  if (!path || unavailable.has(udid)) return undefined;
  let engine = engines.get(udid);
  if (!engine || engine.dead) {
    engine = new Engine(path, udid);
    engines.set(udid, engine);
  }
  if (await engine.ready) return engine;
  engines.delete(udid);
  unavailable.add(udid);
  return undefined;
}

/**
 * A request to the phone's engine, or undefined when there is none (the caller uses AXe). An answer with busy set
 * means the engine is still working on it: the caller goes on without it, never with AXe, whose own automation
 * session would compete with the engine's.
 */
export async function engineCall(udid: string, request: Record<string, unknown>, timeoutMs = 30_000): Promise<Answer | undefined> {
  const engine = await engineFor(udid);
  if (!engine) return undefined;
  try {
    return await engine.call(request, timeoutMs);
  } catch {
    return undefined;
  }
}

/** Ends this process's engines (tests, and a phone that was shut down). */
export function closeEngines(udid?: string): void {
  for (const [id, engine] of engines) if (!udid || id === udid) (engine.kill(), engines.delete(id));
}

type Step = Record<string, unknown>;

/**
 * AXe's batch steps, as the engine's steps. Undefined for any step it does not know, so the whole batch goes to
 * AXe as before.
 */
export function engineSteps(steps: string[]): Step[] | undefined {
  const out: Step[] = [];
  for (const step of steps) {
    let m: RegExpMatchArray | null;
    if ((m = step.match(/^tap -x (-?[\d.]+) -y (-?[\d.]+)( --tap-style physical)?$/))) {
      // Switches and checkboxes need a real touch down and up (see tapStep in ui-act).
      out.push(m[3] ? { touch: [Number(m[1]), Number(m[2])], hold: 0.1 } : { tap: [Number(m[1]), Number(m[2])] });
    } else if ((m = step.match(/^sleep ([\d.]+)$/))) out.push({ sleep: Number(m[1]) });
    else if ((m = step.match(/^key-combo --modifiers ([\d,]+) --key (\d+)$/))) out.push({ combo: { mods: m[1]!.split(",").map(Number), key: Number(m[2]) } });
    else if ((m = step.match(/^key (\d+)$/))) out.push({ key: Number(m[1]) });
    else if ((m = step.match(/^type '([\s\S]*)'$/))) out.push({ type: m[1]!.replace(/'\\''/g, "'") });
    else if ((m = step.match(/^touch -x (-?[\d.]+) -y (-?[\d.]+) --down --up --delay ([\d.]+)$/))) out.push({ touch: [Number(m[1]), Number(m[2])], hold: Number(m[3]) });
    else return undefined;
  }
  return out;
}

/** AXe's swipe and drag arguments, as an engine request; undefined for anything else. */
export function engineGesture(args: string[]): Step | undefined {
  const [kind, ...rest] = args;
  if (kind !== "swipe" && kind !== "drag") return undefined;
  const value = (flag: string) => {
    const i = rest.indexOf(flag);
    return i >= 0 ? Number(rest[i + 1]) : NaN;
  };
  const [x1, y1, x2, y2] = ["--start-x", "--start-y", "--end-x", "--end-y"].map(value);
  const duration = value("--duration");
  if ([x1, y1, x2, y2].some((n) => !Number.isFinite(n))) return undefined;
  return { op: kind, x1, y1, x2, y2, duration: Number.isFinite(duration) ? duration : kind === "drag" ? 0.6 : 0.3 };
}
