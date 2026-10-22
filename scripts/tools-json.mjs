// Writes dist/tools.json: the tools as an MCP client lists them, with the server's instructions and
// version, for NoMac's hosted simulator-use (mcp.nomac.app/simulator-use), which reads them from the
// pinned package so its tools never drift from the local ones. Run by npm run build.
import { writeFileSync } from "node:fs";
import { INSTRUCTIONS, TOOLS, VERSION } from "../dist/registry.js";

const tools = TOOLS.map((t) => ({ name: t.name, title: t.title, description: t.description, inputSchema: t.inputSchema, annotations: { title: t.title, ...t.annotations } }));
writeFileSync(new URL("../dist/tools.json", import.meta.url), `${JSON.stringify({ version: VERSION, instructions: INSTRUCTIONS, tools }, null, 2)}\n`);
