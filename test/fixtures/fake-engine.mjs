#!/usr/bin/env node
// A stand-in for native/engine in tests: ready at once, then each request answered after its delay_ms, in order.
import { createInterface } from "node:readline";
process.stdout.write(JSON.stringify({ ready: true }) + "\n");
const lines = createInterface({ input: process.stdin })[Symbol.asyncIterator]();
for await (const line of lines) {
  const request = JSON.parse(line);
  await new Promise((resolve) => setTimeout(resolve, request.delay_ms ?? 0));
  process.stdout.write(JSON.stringify({ ok: true, echo: request.n }) + "\n");
}
