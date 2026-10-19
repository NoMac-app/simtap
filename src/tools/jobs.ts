import { elapsed, getJob, waitFor } from "../engine/jobs.ts";
import { ToolError } from "../errors.ts";
import type { Tool } from "./types.ts";

const WAIT_MS = 40_000;

const find = (id: unknown) => {
  const job = getJob(id as string | undefined);
  if (!job) throw new ToolError(id ? `No job ${id} in this server.` : "No job has been started.", "Jobs live as long as this MCP server; start the work again if it restarted.");
  return job;
};

export const jobStatus: Tool = {
  name: "job_status",
  title: "Follow a job",
  description: "Wait up to 40 s for a job (a long build) to finish and answer with its result, or with what it is doing and its last output lines.",
  inputSchema: {
    type: "object",
    properties: { job_id: { type: "string", description: "Default: the latest job" } },
    additionalProperties: false,
  },
  annotations: { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false },
  command: "job",
  positional: ["job_id"],
  async run(args) {
    const job = find(args.job_id);
    const done = await waitFor(job, WAIT_MS);
    if (done) return done;
    const tail = job.tail.slice(-5).join("\n");
    return {
      text: `${job.title}: ${job.step}, ${elapsed(job)} so far (${job.id}).${tail ? `\nLast lines:\n${tail}` : ""}${job.log ? `\nFull log: ${job.log}` : ""}\nNext: job_status again, or job_cancel.`,
    };
  },
};

export const jobCancel: Tool = {
  name: "job_cancel",
  title: "Stop a job",
  description: "Stop a job, such as a build that is no longer needed.",
  inputSchema: {
    type: "object",
    properties: { job_id: { type: "string", description: "Default: the latest job" } },
    additionalProperties: false,
  },
  annotations: { readOnlyHint: false, destructiveHint: true, idempotentHint: true, openWorldHint: false },
  command: "cancel",
  positional: ["job_id"],
  async run(args) {
    const job = find(args.job_id);
    if (job.result) return { text: `${job.title} had already ${job.cancelled ? "been stopped" : "finished"}.` };
    if (!job.cancel) return { text: `${job.title} is ${job.step} and can't be stopped at this step; it ends on its own.` };
    job.cancel();
    await waitFor(job, 10_000);
    return { text: `Stopped ${job.title} after ${elapsed(job)}.` };
  },
};
