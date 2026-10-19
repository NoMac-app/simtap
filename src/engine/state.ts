import { mkdir, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

/**
 * What a call can leave for the next one.
 * - The device this agent holds lives in memory: each agent runs its own MCP server, so two agents never share it.
 * - The app last launched on a device is a small file next to its log files, so the CLI and MCP see the same.
 */
let held: string | undefined;

export const holdDevice = (udid: string) => {
  held = udid;
};
export const heldDevice = () => held;

/** Where simtap keeps a device's app output: the print() lines of apps it launched. */
export async function deviceDir(udid: string): Promise<string> {
  const dir = join(tmpdir(), "simtap", udid);
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
