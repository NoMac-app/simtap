import { writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { account, cloudState, setCloudState, signIn } from "../cloud/account.ts";
import { type CloudApi, CloudError } from "../cloud/api.ts";
import { forward } from "../cloud/forward.ts";
import { randomKey } from "../cloud/sync.ts";
import { ToolError } from "../errors.ts";
import { setting } from "../settings.ts";
import type { CallContext, Tool, ToolResult } from "./types.ts";

/** How long start waits for the phone before answering that it is still starting (an MCP call has about a minute). */
const READY_WAIT_MS = 40_000;
const ACTIONS = ["start", "status", "stop", "run"];

type Phone = { id: string; state: string; ready_at?: string | null; failure_code?: string | null; cost?: { accrued_microunits?: string; billable_seconds?: number }; cleanup_confirmed?: boolean };
/** A phone answer's links: view and control while it runs, its replay always. */
type Links = { view?: string; control?: string; replay?: string };

const dollars = (micro: string | undefined) => `$${(Number(micro ?? 0) / 1e6).toFixed(2)}`;
const phoneOf = async (api: CloudApi, id: string) => (await api.json("GET", `/api/v1/simulator/sessions/${id}`)).session as Phone;

/** Waits for a phone to be ready, up to the time given. Answers it as it last read. */
async function untilReady(api: CloudApi, id: string, waitMs: number): Promise<Phone> {
  let phone = await phoneOf(api, id);
  for (const deadline = Date.now() + waitMs; !["ready", "failed", "stopped", "stopping"].includes(phone.state) && Date.now() < deadline; ) {
    await new Promise((r) => setTimeout(r, 500));
    phone = await phoneOf(api, id);
  }
  return phone;
}

async function start(context: CallContext): Promise<ToolResult> {
  const signed = await signIn();
  if ("link" in signed) {
    return { text: `Sign in to NoMac for a cloud phone: open ${signed.link} and approve code ${signed.code}.\nNext: cloud start again once it is approved (headless: set NOMAC_API_KEY instead).` };
  }
  const { api } = signed;
  const state = await cloudState();
  if (state.session) {
    const phone = await phoneOf(api, state.session).catch(() => undefined);
    if (phone && (phone.state === "ready" || phone.state === "queued" || phone.state === "provisioning")) {
      await setCloudState({ ...state, on: true });
      return { text: `Cloud is on: phone ${phone.id} is ${phone.state}, ${dollars(phone.cost?.accrued_microunits)} so far. Every tool runs there; cloud stop ends it.` };
    }
  }
  const started = Date.now();
  const created = await api.json("POST", "/api/v1/simulator/sessions", {}, `cli-start-${randomKey()}`);
  const id = String((created.session as Phone).id);
  await setCloudState({ on: true, session: id });
  const phone = await untilReady(api, id, context.waitForJobs ? 5 * 60_000 : READY_WAIT_MS);
  if (phone.state !== "ready") {
    if (["failed", "stopped", "stopping"].includes(phone.state)) {
      await setCloudState({ on: false });
      throw new ToolError(`The cloud phone did not start: ${phone.failure_code ?? phone.state}.`, "Call cloud start again; report_issue on NoMac's MCP if it keeps failing.");
    }
    return { text: `The cloud phone ${id} is still starting after ${((Date.now() - started) / 1000).toFixed(0)} s.\nNext: cloud status, or any tool: it waits for the phone.` };
  }
  const links = (created.links ?? {}) as Links;
  const watch = links.view && links.control ? `\nA person can watch it at ${links.view} or use it at ${links.control}.` : "";
  return { text: `Cloud phone ready in ${((Date.now() - started) / 1000).toFixed(1)} s: an iPhone Simulator on a NoMac Mac, $0.80 an hour by the minute.\nEvery tool now runs there; app_run and tests_run send the project first. cloud stop ends it.${watch}` };
}

async function status(): Promise<ToolResult> {
  const state = await cloudState();
  if (!state.on) return { text: "Cloud is off: the tools run on this machine. cloud start runs them on a NoMac phone." };
  const api = await account();
  if (!api || !state.session) return { text: "Cloud is on but has no phone yet. cloud start starts one." };
  const phone = await phoneOf(api, state.session);
  const minutes = Math.ceil((phone.cost?.billable_seconds ?? 0) / 60);
  return { text: `Cloud is on: phone ${phone.id} is ${phone.state}; ${minutes} min so far, ${dollars(phone.cost?.accrued_microunits)} at $0.80 an hour.` };
}

async function stop(): Promise<ToolResult> {
  const state = await cloudState();
  const api = await account();
  await setCloudState({ on: false });
  if (!state.session || !api) return { text: "Cloud is off: the tools run on this machine." };
  const stopped = await api.json("DELETE", `/api/v1/simulator/sessions/${state.session}`).catch((error: unknown) => {
    if (!(error instanceof CloudError && error.status === 404)) throw error;
    return undefined;
  });
  let phone = await phoneOf(api, state.session).catch(() => undefined);
  for (let i = 0; phone && !phone.cleanup_confirmed && i < 15; i++) {
    await new Promise((r) => setTimeout(r, 2_000));
    phone = await phoneOf(api, state.session).catch(() => undefined);
  }
  const minutes = Math.ceil((phone?.cost?.billable_seconds ?? 0) / 60);
  const replay = ((stopped?.links ?? {}) as Links).replay;
  return { text: `Stopped the cloud phone after ${minutes} min, ${dollars(phone?.cost?.accrued_microunits)}. The tools run on this machine again.${replay ? `\nIts replay, the screen and every call, opens at ${replay} in a minute (kept 7 days).` : ""}` };
}

/**
 * CI in one call: a phone, the project built and run, its tests with tests: true, a screenshot of its screen, and
 * the phone stopped (unless cloud was already on). Fails when the build or a test fails.
 */
async function runOnce(args: Record<string, unknown>, context: CallContext): Promise<ToolResult> {
  const before = await cloudState();
  const lines: string[] = [];
  let failed = false;
  let image: ToolResult["image"];
  const ensure = await start({ waitForJobs: true });
  if (/^Sign in to NoMac/.test(ensure.text)) return { text: ensure.text, isError: true };
  try {
    const path = typeof args.path === "string" ? args.path : ".";
    // A video of the whole run for the person reviewing it (the phone records up to its own limit).
    const recording = await forward("screen_record", { action: "start" }, context);
    const ran = await forward("app_run", { path }, { waitForJobs: true });
    lines.push(ran.text);
    failed ||= Boolean(ran.isError);
    if (!ran.isError && args.tests === true) {
      const tested = await forward("tests_run", { path }, { waitForJobs: true });
      lines.push(tested.text);
      failed ||= Boolean(tested.isError);
    }
    const out = typeof args.out === "string" ? args.out : tmpdir();
    if (!ran.isError) {
      const look = await forward("ui_look", { screenshot: true }, context);
      image = look.image;
      if (image && context.waitForJobs) {
        const file = join(out, `simulator-use-cloud-${Date.now()}.${image.mimeType === "image/png" ? "png" : "jpg"}`);
        await writeFile(file, image.data);
        lines.push(`Screenshot: ${file}`);
      }
    }
    if (!recording.isError) {
      const stopped = await forward("screen_record", { action: "stop" }, context);
      const link = /https?:\/\/\S+\/api\/v1\/simulator\/files\/[A-Za-z0-9_.-]+/.exec(stopped.text)?.[0];
      if (link && context.waitForJobs) {
        const response = await fetch(link);
        if (response.ok) {
          const file = join(out, `simulator-use-cloud-${Date.now()}.mp4`);
          await writeFile(file, Buffer.from(await response.arrayBuffer()));
          lines.push(`Recording: ${file}`);
        } else {
          lines.push(`Recording: ${link}`);
        }
      } else if (link) {
        lines.push(`Recording: ${link}`);
      }
    }
  } finally {
    if (!before.on) lines.push((await stop()).text);
  }
  // The command line saved the screenshot above; an MCP client gets the picture itself.
  return { text: lines.join("\n\n"), ...(image && !context.waitForJobs ? { image } : {}), ...(failed ? { isError: true } : {}) };
}

export const cloud: Tool = {
  name: "cloud",
  title: "Cloud phone",
  command: "cloud",
  positional: ["action", "path"],
  description:
    "A NoMac cloud iPhone Simulator on a Mac with Xcode, $0.80 an hour by the minute: for a machine that can't run one (Linux, Windows, a cloud agent) or for CI. start signs in (a link for the person the first time; NOMAC_API_KEY for headless) and starts a phone: until stop, every tool runs there and app_run and tests_run send the project first. status: the phone and its cost so far. stop: ends it. run: start, build and run path, its tests with tests, a screenshot and a recording, stop, in one call.",
  inputSchema: {
    type: "object",
    properties: {
      action: { type: "string", enum: ACTIONS, description: "start, status, stop, or run" },
      path: { type: "string", description: "run: the project folder; default: the current folder" },
      tests: { type: "boolean", description: "run: run the project's tests too" },
      out: { type: "string", description: "run (command line): the folder for the screenshot; default: the temporary folder" },
    },
    required: ["action"],
    additionalProperties: false,
  },
  annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: true },
  async run(args, context) {
    if (setting("HOSTED")) throw new ToolError("This is a NoMac phone already.", "Call the other tools directly.");
    try {
      switch (args.action) {
        case "start":
          return await start(context);
        case "status":
          return await status();
        case "stop":
          return await stop();
        case "run":
          return await runOnce(args, context);
      }
      throw new ToolError(`Unknown action "${String(args.action)}".`, `Actions: ${ACTIONS.join(", ")}.`);
    } catch (error) {
      if (error instanceof CloudError) throw new ToolError(`NoMac: ${error.message}`, error.code === "insufficient_credit" ? "Add credit at https://nomac.app/dashboard, then cloud start again." : "Call cloud status, or try again in a minute.");
      throw error;
    }
  },
};
