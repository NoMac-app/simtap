import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

/**
 * What a call can leave for the next one.
 * - The device an MCP server's agent holds lives in its memory: each agent runs its own server, so two agents
 *   never share it. A CLI call is its own process, so the CLI keeps the device in a file (persistHeld), and
 *   `simtap use` carries over to the next command.
 * - The app last launched on a device is a small file next to its log files, so the CLI and MCP see the same.
 */
let held: string | undefined;
let persist = false;

/** Where simtap keeps its files: SIMTAP_STATE_DIR, else simtap in the user's temporary folder. */
export const stateDir = () => process.env.SIMTAP_STATE_DIR || join(tmpdir(), "simtap");
const heldFile = () => join(stateDir(), "held-device.json");

/** The CLI keeps the held device between its calls. */
export function persistHeld(): void {
  persist = true;
}

export const holdDevice = (udid: string) => {
  held = udid;
  if (!persist) return;
  try {
    mkdirSync(stateDir(), { recursive: true });
    writeFileSync(heldFile(), JSON.stringify({ udid }));
  } catch {
    // The next call falls back to the booted device.
  }
};

export const heldDevice = () => {
  if (held || !persist) return held;
  try {
    const { udid } = JSON.parse(readFileSync(heldFile(), "utf8")) as { udid?: unknown };
    if (typeof udid === "string" && /^[0-9A-Fa-f-]{36}$/.test(udid)) held = udid;
  } catch {
    // None held yet.
  }
  return held;
};

/** Where simtap keeps a device's app output: the print() lines of apps it launched. */
export async function deviceDir(udid: string): Promise<string> {
  const dir = join(stateDir(), udid);
  await mkdir(dir, { recursive: true });
  return dir;
}

export type CurrentApp = { bundleId: string; executable?: string; launchedAt?: number };

export async function currentApp(udid: string): Promise<CurrentApp | undefined> {
  try {
    return JSON.parse(await readFile(join(await deviceDir(udid), "app.json"), "utf8")) as CurrentApp;
  } catch {
    return undefined;
  }
}

export async function setCurrentApp(udid: string, app: CurrentApp): Promise<void> {
  await writeFile(join(await deviceDir(udid), "app.json"), JSON.stringify(app));
}
