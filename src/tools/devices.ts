import { listDevices, xcodeVersion } from "../engine/simctl.ts";
import type { Tool } from "./types.ts";

const MAX_LINES = 40;

export const devices: Tool = {
  name: "devices",
  title: "List Simulators",
  description: "List the iOS Simulators on this Mac: name, runtime, UDID and which are booted. The other tools use the booted one.",
  inputSchema: { type: "object", properties: {}, additionalProperties: false },
  annotations: { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false },
  command: "devices",
  async run() {
    const [list, xcode] = await Promise.all([listDevices(true), xcodeVersion()]);
    const lines = [`This Mac${xcode ? ` · ${xcode}` : ""}`];
    for (const d of list.slice(0, MAX_LINES)) lines.push(`${d.booted ? "booted " : ""}${d.name} · ${d.runtime} · ${d.udid}`);
    if (list.length > MAX_LINES) lines.push(`… ${list.length - MAX_LINES} more (xcrun simctl list devices)`);
    const booted = list.filter((d) => d.booted);
    if (!list.length) lines.push("No Simulators. Add an iOS runtime in Xcode > Settings > Components.");
    else if (!booted.length) lines.push(`None booted. Boot one: xcrun simctl boot ${list[0]!.udid}`);
    else if (booted.length > 1) lines.push("Several are booted: pass device (name or UDID) to the other tools.");
    return { text: lines.join("\n") };
  },
};
