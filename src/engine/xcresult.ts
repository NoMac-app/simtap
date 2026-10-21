import { readdirSync, statSync } from "node:fs";
import { join, relative } from "node:path";

import { run } from "./exec.ts";

export type Failure = { test: string; id: string; message: string; file?: string; line?: number };
export type TestReport = { result: string; passed: number; failed: number; skipped: number; total: number; failures: Failure[] };

type Node = { name?: string; nodeType?: string; nodeIdentifier?: string; result?: string; children?: Node[]; sourceLocation?: { filePath?: string; lineNumber?: number } };

/** Failures as Xcode records them: the test, and "File.swift:12: message" for each failed assertion. */
export function failuresIn(nodes: Node[], bundle = ""): Failure[] {
  const out: Failure[] = [];
  for (const node of nodes) {
    if (node.nodeType === "Test Case" && node.result === "Failed") {
      const messages: string[] = [];
      const collect = (n: Node) => {
        if (n.nodeType === "Failure Message" && n.name) messages.push(n.name);
        n.children?.forEach(collect);
      };
      node.children?.forEach(collect);
      // The identifier already holds the suite (SignInTests/testX()); the bundle makes it -only-testing ready.
      const id = node.nodeIdentifier ?? node.name ?? "?";
      const test = [bundle, id].filter(Boolean).join("/");
      for (const message of messages.length ? messages : ["failed (no message recorded)"]) out.push({ test, id, message });
    } else if (node.children) {
      out.push(...failuresIn(node.children, /test bundle$/i.test(node.nodeType ?? "") ? (node.name ?? bundle) : bundle));
    }
  }
  return out;
}

export async function readTestReport(bundle: string): Promise<TestReport> {
  // Right after xcodebuild exits, one read of a finished bundle failed once; the same read a moment later worked.
  const get = async (what: string, more: string[] = []) => {
    const args = ["xcresulttool", "get", "test-results", what, ...more, "--path", bundle];
    const out = await run("xcrun", args, { timeoutMs: 60_000 }).catch(async () => {
      await new Promise((r) => setTimeout(r, 1_000));
      return run("xcrun", args, { timeoutMs: 60_000 });
    });
    return JSON.parse(out.stdout);
  };
  // One read at a time: xcresulttool builds the bundle's database on the first read, and two first reads at once
  // fail with "XCResultDataViews.Database.DBError error 0" (Xcode 27, a warm rebuild read 3 s after it started).
  const summary = await get("summary");
  const tests = await get("tests");
  const failures = failuresIn(tests.testNodes ?? []);
  // Xcode 26 starts a failure message with "File.swift:12: "; Xcode 27 keeps the place in the test's details.
  for (const f of failures.filter((x) => !/^[^\s/:]+\.\w+:\d+: /.test(x.message)).slice(0, 10)) {
    const details = await get(`test-details`, ["--test-id", f.id]).catch(() => undefined);
    const place = details && sourceLocation(details.testRuns ?? []);
    if (place?.filePath) Object.assign(f, { file: place.filePath, line: place.lineNumber });
  }
  return {
    result: summary.result,
    passed: summary.passedTests ?? 0,
    failed: summary.failedTests ?? 0,
    skipped: summary.skippedTests ?? 0,
    total: summary.totalTestCount ?? 0,
    failures,
  };
}

/** The first source location in a test's details: where the failed assertion is. */
export function sourceLocation(nodes: Node[]): { filePath?: string; lineNumber?: number } | undefined {
  for (const node of nodes) {
    if (node.sourceLocation?.filePath) return node.sourceLocation;
    const inner = sourceLocation(node.children ?? []);
    if (inner) return inner;
  }
  return undefined;
}

/** "SignInTests.swift:12: ..." names the file only; this finds it in the project to give its path. */
export function locate(message: string, projectDir: string): string {
  const match = /^([^\s/:]+\.(?:swift|m|mm)):(\d+): /.exec(message);
  if (!match) return message;
  const found: string[] = [];
  const walk = (dir: string, depth: number) => {
    if (depth > 6 || found.length > 1) return;
    let entries: string[];
    try {
      entries = readdirSync(dir);
    } catch {
      return;
    }
    for (const entry of entries) {
      if (entry.startsWith(".") || /^(DerivedData|build|Pods|node_modules|Carthage)$/.test(entry) || entry.endsWith(".xcodeproj") || entry.endsWith(".xcworkspace")) continue;
      const full = join(dir, entry);
      if (entry === match[1]) found.push(full);
      else if (statSync(full).isDirectory()) walk(full, depth + 1);
    }
  };
  walk(projectDir, 0);
  return found.length === 1 ? `${relative(projectDir, found[0]!)}${message.slice(match[1]!.length)}` : message;
}
