/**
 * With cloud on, every tool runs on the NoMac phone instead of this machine: called by name through NoMac's API
 * and polled until it ends. app_run and tests_run send their project first, and app_control install its .app, so
 * the paths the phone takes are its own. Answers read as a local tool's do; files they name are links.
 */

import { existsSync, realpathSync, statSync } from "node:fs";
import { basename, dirname, extname, relative, resolve, sep } from "node:path";
import { createHash } from "node:crypto";

import { run } from "../engine/exec.ts";
import { ToolError } from "../errors.ts";
import type { CallContext, ToolResult } from "../tools/types.ts";
import { account, cloudState, setCloudState } from "./account.ts";
import { type CloudApi, CloudError } from "./api.ts";
import { randomKey, syncFolder } from "./sync.ts";

const JOB = /Next: job_status \{job_id: "([^"]+)"\}/;

/** The phone cloud mode uses, or why there is none. */
export async function cloudPhone(): Promise<{ api: CloudApi; session: string }> {
  const state = await cloudState();
  const api = await account();
  if (!api) throw new ToolError("Cloud is on but this machine is not signed in to NoMac.", "Call cloud start to sign in, or cloud stop to run tools on this machine.");
  if (!state.session) throw new ToolError("Cloud is on but has no phone.", "Call cloud start for one, or cloud stop to run tools on this machine.");
  return { api, session: state.session };
}

/** A phone that ended (its limit, an idle stop, stopped elsewhere): cloud mode forgets it and says so. */
async function ended(session: string): Promise<ToolResult> {
  const state = await cloudState();
  if (state.session === session) await setCloudState({ ...state, session: undefined });
  return { text: `The cloud phone ${session} has ended (its time limit, an idle stop, or stopped elsewhere).\nNext: cloud start for a new one, or cloud stop to run tools on this machine again.`, isError: true };
}

/**
 * Where a project is sent from: the repository it is in (so local packages beside it come along), else its own
 * folder; and the path inside that the phone's tool takes.
 */
async function projectRoot(path: string): Promise<{ folder: string; inside: string }> {
  const local = resolve(path);
  if (!existsSync(local)) throw new ToolError(`No project at ${local}.`, "Pass path: the folder with the .xcodeproj, .xcworkspace or project.yml.");
  const isProject = [".xcodeproj", ".xcworkspace"].includes(extname(local));
  const dir = isProject || !statSync(local).isDirectory() ? dirname(local) : local;
  let folder = realpathSync(dir);
  try {
    folder = realpathSync((await run("git", ["-C", dir, "rev-parse", "--show-toplevel"], { timeoutMs: 5_000 })).stdout.trim());
  } catch {
    // Not in a repository: the folder itself.
  }
  return { folder, inside: relative(folder, realpathSync(local)).split(sep).join("/") };
}

/** Runs one tool on the phone and answers as the local tool would. */
export async function forward(name: string, args: Record<string, unknown>, context: CallContext): Promise<ToolResult> {
  const { api, session } = await cloudPhone();
  let sent = args;
  let note = "";
  try {
    if (name === "app_run" || name === "tests_run") {
      const { folder, inside } = await projectRoot(typeof args.path === "string" ? args.path : ".");
      const synced = await syncFolder(api, session, folder);
      sent = { ...args, path: inside ? `${synced.root}/${inside}` : synced.root };
      note = synced.sent ? `Sent ${synced.sent} of ${synced.files} files (${Math.max(1, Math.round(synced.bytes / 1024))} KB) in ${(synced.ms / 1000).toFixed(1)} s.\n` : `Sent nothing: the phone has all ${synced.files} files.\n`;
    } else if (name === "app_control" && args.action === "install" && typeof args.app === "string") {
      const app = resolve(args.app);
      if (extname(app) !== ".app" || !existsSync(app) || !statSync(app).isDirectory()) throw new ToolError(`${args.app} is not a .app built for the Simulator.`, "Build with xcodebuild -sdk iphonesimulator; the .app is under Build/Products/Debug-iphonesimulator.");
      // Its own project on the phone, so this upload never touches the files of the project it was built from.
      const project = `prj_${createHash("sha256").update(`app:${realpathSync(app)}`).digest("hex").slice(0, 32)}`;
      const synced = await syncFolder(api, session, dirname(app), { only: basename(app), project });
      sent = { ...args, app: `${synced.root}/${basename(app)}` };
    }
    let result = await call(api, session, name, sent);
    // The command line waits for a long build, as it does on this Mac: job_status until the job ends.
    for (let rounds = 0; context.waitForJobs && rounds < 60; rounds++) {
      const job = JOB.exec(result.text)?.[1];
      if (!job) break;
      result = await call(api, session, "job_status", { job_id: job });
    }
    return note ? { ...result, text: `${note}${result.text}` } : result;
  } catch (error) {
    if (error instanceof CloudError && (error.code === "session_not_found" || error.code === "session_not_ready" || error.code === "session_expired")) return ended(session);
    if (error instanceof CloudError) return { text: `NoMac: ${error.message}`, isError: true };
    throw error;
  }
}

async function call(api: CloudApi, session: string, name: string, args: Record<string, unknown>): Promise<ToolResult> {
  let answer = await api.json("POST", `/api/v1/simulator/sessions/${session}/tools/${name}`, args, `cli-${name}-${randomKey()}`);
  while (answer.state === "running" && typeof answer.id === "string") {
    await new Promise((r) => setTimeout(r, 1_000));
    answer = await api.json("GET", `/api/v1/simulator/sessions/${session}/calls/${answer.id}`);
  }
  if (answer.state === "cancelled") return { text: `${name} was cancelled.`, isError: true };
  const result = answer.result as { content?: { type: string; text?: string; data?: string; mimeType?: string }[]; isError?: boolean } | undefined;
  if (!result) return { text: `${name} failed on the phone: ${String(answer.error ?? answer.state)}.`, isError: true };
  const text = (result.content ?? []).filter((c) => c.type === "text").map((c) => c.text ?? "").join("\n");
  const picture = (result.content ?? []).find((c) => c.type === "image" && c.data);
  const notices = (answer.notices as string[] | undefined)?.includes("phone_restarted") ? "\nThe phone restarted; its apps and data are kept." : "";
  return {
    text: `${text}${notices}`,
    ...(picture ? { image: { data: Buffer.from(picture.data!, "base64"), mimeType: picture.mimeType === "image/png" ? "image/png" : "image/jpeg" } } : {}),
    ...(result.isError ? { isError: true } : {}),
  };
}
