/**
 * The command line, built from the same tool list as the MCP server:
 * `simtap look --find "Sign In"` calls ui_look with { find: "Sign In" }.
 */

import { writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { serve } from "./mcp.ts";
import { callTool, TOOLS, VERSION } from "./registry.ts";
import type { Tool } from "./tools/types.ts";

const flag = (name: string) => `--${name.replace(/_/g, "-")}`;

/** Parses `--name value` and `--switch` into arguments the tool's schema accepts. */
export function parseArgs(tool: Tool, argv: string[]): Record<string, unknown> | string {
  const props = tool.inputSchema.properties;
  const args: Record<string, unknown> = {};
  const list = Object.entries(props).find(([, p]) => p.type === "array")?.[0];
  const words = [...(tool.positional ?? [])];
  for (let i = 0; i < argv.length; i++) {
    const raw = argv[i]!;
    if (!raw.startsWith("--")) {
      // Bare words fill the tool's positional arguments in order, then a list argument takes the rest.
      const next = words.find((w) => !(w in args));
      if (next) {
        args[next] = raw;
        continue;
      }
      if (list) {
        args[list] = [...((args[list] as string[] | undefined) ?? []), raw];
        continue;
      }
      return `Unexpected "${raw}". ${usage(tool)}`;
    }
    const [name, inline] = raw.startsWith("--") ? raw.slice(2).split(/=(.*)/s, 2) : [undefined, undefined];
    const key = name?.replace(/-/g, "_");
    const prop = key ? props[key] : undefined;
    if (!key || !prop || prop.type === "array") return `Unknown option ${raw}. ${usage(tool)}`;
    if (prop.type === "boolean") {
      args[key] = inline === undefined ? true : inline !== "false";
      continue;
    }
    const value = inline ?? argv[++i];
    if (value === undefined) return `${flag(key)} needs a value.`;
    args[key] = prop.type === "number" ? Number(value) : value;
  }
  return args;
}

export function usage(tool: Tool): string {
  const entries = Object.entries(tool.inputSchema.properties);
  const bare = (tool.positional ?? []).map((key) => ` [${key}]`).join("");
  const options = entries.filter(([key, p]) => p.type !== "array" && !tool.positional?.includes(key)).map(([key, p]) => `${flag(key)}${p.type === "boolean" ? "" : ` <${p.type}>`}`);
  const words = entries.filter(([, p]) => p.type === "array").map(([key]) => ` <${key}...>`).join("");
  return `Usage: simtap ${tool.command}${bare}${options.length ? ` [${options.join("] [")}]` : ""}${words}`;
}

/** The first sentence of a description, ending in one period. */
const summary = (description: string) => `${description.split(/\.\s/)[0]!.replace(/\.$/, "")}.`;

export function help(): string {
  const width = Math.max(...TOOLS.map((t) => t.command.length), 3);
  return [
    `simtap ${VERSION}: give your agent a phone.`,
    "",
    "Commands:",
    ...TOOLS.map((t) => `  ${t.command.padEnd(width)}  ${summary(t.description)}`),
    `  ${"mcp".padEnd(width)}  Run the MCP server on stdio.`,
    "",
    "Examples:",
    "  simtap run                      build, install and launch the Xcode project in this folder",
    "  simtap look                     read the screen",
    '  simtap act "fill #email a@b.co" "tap #signIn" \'wait "Welcome"\'',
    "  simtap logs --crashes           why did it crash",
    "",
    "Run simtap <command> --help for its options.",
  ].join("\n");
}

/** One command's help: what it does, its words and options with their choices. */
export function commandHelp(tool: Tool): string {
  const lines = [tool.description, "", usage(tool)];
  for (const [key, p] of Object.entries(tool.inputSchema.properties)) {
    const choices = p.type !== "array" && p.enum ? ` (${p.enum.join(", ")})` : "";
    const name = p.type === "array" ? `<${key}...>` : tool.positional?.includes(key) ? `[${key}] or ${flag(key)}` : flag(key);
    lines.push(`  ${name}  ${p.description}${choices}`);
  }
  return lines.join("\n");
}

export async function main(argv: string[]): Promise<number> {
  const [command, ...rest] = argv;
  if (!command || command === "help" || command === "--help" || command === "-h") {
    console.log(help());
    return 0;
  }
  if (command === "--version" || command === "-v") {
    console.log(VERSION);
    return 0;
  }
  if (command === "mcp") {
    await serve();
    // The client closed stdin: answer what was in flight, then go, even if a child process still holds a pipe.
    process.exit(0);
  }
  const tool = TOOLS.find((t) => t.command === command || t.name === command);
  if (!tool) {
    console.error(`Unknown command "${command}".\n\n${help()}`);
    return 2;
  }
  if (rest.includes("--help") || rest.includes("-h")) {
    console.log(commandHelp(tool));
    return 0;
  }
  const args = parseArgs(tool, rest);
  if (typeof args === "string") {
    console.error(args);
    return 2;
  }
  const out = await callTool(tool.name, args, { waitForJobs: true });
  let text = out.text;
  if (out.image) {
    const file = join(tmpdir(), `simtap-${Date.now()}.${out.image.mimeType === "image/png" ? "png" : "jpg"}`);
    await writeFile(file, out.image.data);
    text += `\nscreenshot: ${file}`;
  }
  (out.isError ? console.error : console.log)(text);
  return out.isError ? 1 : 0;
}
