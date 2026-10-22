/**
 * The MCP server over stdio: newline-delimited JSON-RPC 2.0, no SDK.
 * It speaks both the 2024-11-05 to 2025-11-25 protocol (an initialize handshake) and the stateless
 * 2026-07-28 protocol (server/discover, with the version in every request's _meta).
 */

import { createInterface } from "node:readline";

import { cancelAllJobs } from "./engine/jobs.ts";
import { callTool, INSTRUCTIONS, toContent, TOOLS, VERSION } from "./registry.ts";
import { setting } from "./settings.ts";

const STATELESS = "2026-07-28";
const HANDSHAKE_VERSIONS = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"];
export const SUPPORTED_VERSIONS = [STATELESS, ...HANDSHAKE_VERSIONS];
const SERVER_INFO = { name: "simulator-use", version: VERSION };
const CAPABILITIES = { tools: { listChanged: false } };

type Request = { jsonrpc?: string; id?: string | number | null; method?: string; params?: Record<string, unknown> };
type Response = { jsonrpc: "2.0"; id: string | number | null; result?: unknown; error?: { code: number; message: string; data?: unknown } };

const toolList = () =>
  TOOLS.map((t) => ({ name: t.name, title: t.title, description: t.description, inputSchema: t.inputSchema, annotations: { title: t.title, ...t.annotations } }));

async function result(method: string, params: Record<string, unknown>, stateless: boolean): Promise<unknown> {
  switch (method) {
    case "initialize": {
      const asked = params.protocolVersion;
      const protocolVersion = typeof asked === "string" && HANDSHAKE_VERSIONS.includes(asked) ? asked : HANDSHAKE_VERSIONS[0];
      return { protocolVersion, capabilities: CAPABILITIES, serverInfo: SERVER_INFO, instructions: INSTRUCTIONS };
    }
    case "server/discover":
      return { supportedVersions: SUPPORTED_VERSIONS, capabilities: CAPABILITIES, instructions: INSTRUCTIONS, ttlMs: 3_600_000, cacheScope: "public" };
    case "ping":
      return {};
    case "tools/list":
      return stateless ? { tools: toolList(), ttlMs: 3_600_000, cacheScope: "public" } : { tools: toolList() };
    case "tools/call": {
      const name = typeof params.name === "string" ? params.name : "";
      const args = params.arguments && typeof params.arguments === "object" ? (params.arguments as Record<string, unknown>) : {};
      return toContent(await callTool(name, args));
    }
    case "simulator-use/configure":
      if (setting("HOSTED")) return configure(params);
      throw Object.assign(new Error(`Method not found: ${method}`), { code: -32601 });
    default:
      throw Object.assign(new Error(`Method not found: ${method}`), { code: -32601 });
  }
}

/**
 * A hosted session server (NoMac Simulator, SIMULATOR_USE_HOSTED) is started warm for a phone before anyone's
 * session; at hand-over the host tells it the account's build cache. Only an absolute path is taken.
 */
function configure(params: Record<string, unknown>): Record<string, never> {
  const cacheDir = params.cache_dir;
  if (cacheDir !== undefined) {
    if (typeof cacheDir !== "string" || !cacheDir.startsWith("/") || cacheDir.includes("\0") || cacheDir.split("/").includes("..") || cacheDir.length > 1024) {
      throw Object.assign(new Error("cache_dir must be an absolute path"), { code: -32602 });
    }
    process.env.SIMULATOR_USE_CACHE_DIR = cacheDir;
  }
  return {};
}

/** Handles one message. Returns null for notifications, which get no answer. */
export async function handle(message: Request): Promise<Response | null> {
  // Anything but an object ("null", a number) is not a request; it must not take the server down.
  if (!message || typeof message !== "object" || Array.isArray(message)) return { jsonrpc: "2.0", id: null, error: { code: -32600, message: "Invalid request" } };
  if (message.id === undefined || message.id === null || typeof message.method !== "string") {
    if (typeof message.method === "string") return null;
    return { jsonrpc: "2.0", id: message.id ?? null, error: { code: -32600, message: "Invalid request" } };
  }
  const params = message.params ?? {};
  const meta = (params._meta ?? {}) as Record<string, unknown>;
  const requested = meta["io.modelcontextprotocol/protocolVersion"];
  if (typeof requested === "string" && !SUPPORTED_VERSIONS.includes(requested)) {
    return { jsonrpc: "2.0", id: message.id, error: { code: -32022, message: `Unsupported protocol version ${requested}`, data: { supported: SUPPORTED_VERSIONS, requested } } };
  }
  const stateless = requested === STATELESS || message.method === "server/discover";
  try {
    const value = (await result(message.method, params, stateless)) as Record<string, unknown>;
    const body = stateless ? { ...value, resultType: "complete", _meta: { "io.modelcontextprotocol/serverInfo": SERVER_INFO } } : value;
    return { jsonrpc: "2.0", id: message.id, result: body };
  } catch (error) {
    const code = (error as { code?: number }).code ?? -32603;
    return { jsonrpc: "2.0", id: message.id, error: { code, message: (error as Error).message } };
  }
}

export function serve(input: NodeJS.ReadableStream = process.stdin, output: NodeJS.WritableStream = process.stdout): Promise<void> {
  const write = (response: Response) => output.write(`${JSON.stringify(response)}\n`);
  const lines = createInterface({ input, crlfDelay: Infinity });
  const pending = new Set<Promise<void>>();
  lines.on("line", (raw) => {
    if (!raw.trim()) return;
    let message: Request;
    try {
      message = JSON.parse(raw) as Request;
    } catch {
      write({ jsonrpc: "2.0", id: null, error: { code: -32700, message: "Parse error" } });
      return;
    }
    // Calls run side by side; each answer carries its id. A batch (MCP 2025-03-26) is answered as a batch.
    const answer = async (): Promise<void> => {
      if (Array.isArray(message)) {
        const replies = (await Promise.all((message as Request[]).map((m) => handle(m)))).filter((r): r is Response => r !== null);
        if (!message.length) write({ jsonrpc: "2.0", id: null, error: { code: -32600, message: "Invalid request" } });
        else if (replies.length) output.write(`${JSON.stringify(replies)}\n`);
        return;
      }
      const response = await handle(message);
      if (response) write(response);
    };
    const job = answer().catch((error: Error) => {
      write({ jsonrpc: "2.0", id: null, error: { code: -32603, message: error.message } });
    });
    pending.add(job);
    void job.finally(() => pending.delete(job));
  });
  // When the client goes away, running builds and tests go with it.
  return new Promise((resolve) =>
    lines.on("close", () => {
      cancelAllJobs();
      void Promise.allSettled([...pending]).then(() => resolve());
    }),
  );
}
