/** A test case that just finished, read from xcodebuild's output as it runs. */
export type FinishedCase = { name: string; result: "passed" | "failed" | "skipped"; seconds?: number };

// XCTest: "Test Case '-[DemoTests.SignInTests testSignIn]' passed (0.123 seconds)."
const XCTEST = /^Test Case '-\[(?:[\w]+\.)?([\w]+) ([\w]+)\]' (passed|failed|skipped) \((\d+(?:\.\d+)?) seconds\)/;
// XCTest with parallel clones (Xcode 15 on): "Test case 'SignInTests.testSignIn()' passed on 'Clone 1 of iPhone 17 Pro' (0.123 seconds)"
const XCTEST_CLONES = /^Test case '([\w]+)\.([\w]+)\(\)' (passed|failed|skipped) on '[^']*' \((\d+(?:\.\d+)?) seconds\)/;
// Swift Testing: "✔ Test signIn() passed after 0.012 seconds." and "✘ Test signIn() failed after 0.010 seconds with 1 issue.",
// but not its summary, "✔ Test run with 3 tests in 1 suite passed after 0.055 seconds."
const SWIFT_TESTING = /^[✔✘] Test (?!run with \d+ tests? in )(.+?) (passed|failed) after (\d+(?:\.\d+)?) seconds/;
const SWIFT_SKIPPED = /^[➜↷] Test (.+?) skipped/;

export function finishedCase(line: string): FinishedCase | undefined {
  const text = line.trim();
  let m = XCTEST.exec(text) ?? XCTEST_CLONES.exec(text);
  if (m) return { name: `${m[1]}/${m[2]}`, result: m[3] as FinishedCase["result"], seconds: Number(m[4]) };
  if ((m = SWIFT_TESTING.exec(text))) return { name: m[1]!, result: m[2] as FinishedCase["result"], seconds: Number(m[3]) };
  if ((m = SWIFT_SKIPPED.exec(text))) return { name: m[1]!, result: "skipped" };
  return undefined;
}

/** The cases of a run so far: counts, the last one, and the slowest, for job_status while tests run and their answer. */
export class CaseTally {
  passed = 0;
  failed = 0;
  skipped = 0;
  last?: FinishedCase;
  private all: FinishedCase[] = [];

  add(c: FinishedCase) {
    this[c.result]++;
    this.last = c;
    this.all.push(c);
  }

  get count() {
    return this.all.length;
  }

  /** "12 passed, 1 failed so far; last: SignInTests/testSignIn failed (0.4 s)". */
  progress(): string {
    const counts = `${this.passed} passed${this.failed ? `, ${this.failed} failed` : ""}${this.skipped ? `, ${this.skipped} skipped` : ""} so far`;
    return this.last ? `${counts}; last: ${this.last.name} ${this.last.result}${this.last.seconds !== undefined ? ` (${this.last.seconds.toFixed(1)} s)` : ""}` : counts;
  }

  /** The slowest cases, when any took a second or more: where a run's time goes. */
  slowest(n = 3): string {
    const slow = this.all.filter((c) => (c.seconds ?? 0) >= 1).sort((a, b) => (b.seconds ?? 0) - (a.seconds ?? 0)).slice(0, n);
    return slow.map((c) => `${c.name} ${c.seconds!.toFixed(1)} s`).join(", ");
  }
}
