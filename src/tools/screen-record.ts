import { spawn } from "node:child_process";
import { existsSync, statSync } from "node:fs";
import { readFile, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { setTimeout as sleep } from "node:timers/promises";

import { isOurs } from "../engine/exec.ts";
import { listDevices, pickDevice } from "../engine/simctl.ts";
import { deviceDir, heldDevice } from "../engine/state.ts";
import { ToolError } from "../errors.ts";
import type { Tool } from "./types.ts";

type Recording = { pid: number; file: string; started: number; watchdog?: number };

const MAX_SECONDS = 600;

const alive = (pid: number) => {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
};

export const screenRecord: Tool = {
  name: "screen_record",
  title: "Record the screen",
  description: "Start or stop a video of the Simulator's screen. stop answers with the MP4 file, to show a person what happened.",
  inputSchema: {
    type: "object",
    properties: {
      action: { type: "string", enum: ["start", "stop"], description: "start or stop" },
      device: { type: "string", description: "Name or UDID; default: the one in use" },
    },
    required: ["action"],
    additionalProperties: false,
  },
  annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false },
  command: "record",
  positional: ["action"],
  async run(args) {
    const device = pickDevice(await listDevices(), args.device as string | undefined, heldDevice());
    const dir = await deviceDir(device.udid);
    const state = join(dir, "recording.json");
    const current = await readFile(state, "utf8").then((t) => JSON.parse(t) as Recording, () => undefined);
    const running = current && (await isOurs(current.pid, /recordVideo/)) ? current : undefined;

    if (args.action === "start") {
      if (running) throw new ToolError(`Already recording since ${new Date(running.started).toLocaleTimeString()} to ${running.file}.`, 'Call screen_record {action: "stop"} first.');
      const file = join(dir, `recording-${new Date().toISOString().replace(/[:.]/g, "-")}.mp4`);
      // simctl records until it is interrupted; it runs on its own so the call can return.
      const child = spawn("xcrun", ["simctl", "io", device.udid, "recordVideo", "--codec=h264", "--force", file], { detached: true, stdio: "ignore" });
      child.unref();
      await sleep(800);
      if (!child.pid || !alive(child.pid)) throw new ToolError("The recording did not start.", "Check the Simulator is booted with devices.");
      // A forgotten recording grows about 13 MB a minute: it ends itself after 10 minutes, the file intact.
      // The watchdog checks the pid is still simctl recording, so a reused pid is never signalled.
      const watchdog = spawn("sh", ["-c", `sleep ${MAX_SECONDS}; ps -p ${child.pid} -o command= | grep -q recordVideo && kill -INT ${child.pid}`], { detached: true, stdio: "ignore" });
      watchdog.unref();
      await writeFile(state, JSON.stringify({ pid: child.pid, file, started: Date.now(), watchdog: watchdog.pid } satisfies Recording));
      return { text: `Recording ${device.name} (it stops by itself after ${MAX_SECONDS / 60} minutes). Do the work, then screen_record {action: "stop"} for the file.` };
    }

    if (!running) {
      await rm(state, { force: true });
      // It ran out its 10 minutes: the file is there all the same.
      if (current && existsSync(current.file)) return { text: `The recording had already stopped after ${MAX_SECONDS / 60} minutes: ${current.file}` };
      throw new ToolError("Nothing is recording on this Simulator.", 'Start with screen_record {action: "start"}.');
    }
    // An interrupt makes simctl finish the file properly; a kill would leave it unplayable.
    process.kill(running.pid, "SIGINT");
    if (running.watchdog && (await isOurs(running.watchdog, /sleep \d+; ps -p/))) process.kill(-running.watchdog);
    for (let i = 0; i < 40 && alive(running.pid); i++) await sleep(250);
    await rm(state, { force: true });
    if (!existsSync(running.file)) throw new ToolError("The recording stopped but left no file.");
    const seconds = Math.round((Date.now() - running.started) / 1000);
    const mb = (statSync(running.file).size / 1_000_000).toFixed(1);
    return { text: `Recorded ${seconds} s (${mb} MB): ${running.file}` };
  },
};
