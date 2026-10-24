import assert from "node:assert/strict";
import { test } from "node:test";

import { CaseTally, finishedCase } from "../src/engine/testcases.ts";

test("finished test cases are read from xcodebuild's output: XCTest, its parallel clones, and Swift Testing", () => {
  assert.deepEqual(finishedCase("Test Case '-[DemoTests.SignInTests testSignIn]' passed (0.123 seconds)."), { name: "SignInTests/testSignIn", result: "passed", seconds: 0.123 });
  assert.deepEqual(finishedCase("Test Case '-[DemoUITests testWrongPassword]' failed (4.017 seconds)."), { name: "DemoUITests/testWrongPassword", result: "failed", seconds: 4.017 });
  assert.deepEqual(finishedCase("Test case 'SignInTests.testSignIn()' passed on 'Clone 1 of iPhone 17 Pro' (0.200 seconds)"), { name: "SignInTests/testSignIn", result: "passed", seconds: 0.2 });
  assert.deepEqual(finishedCase("✔ Test signIn() passed after 0.012 seconds."), { name: "signIn()", result: "passed", seconds: 0.012 });
  assert.deepEqual(finishedCase("✘ Test \"Wrong password\" failed after 1.500 seconds with 1 issue."), { name: "\"Wrong password\"", result: "failed", seconds: 1.5 });
  for (const other of ["Test Case '-[DemoTests.SignInTests testSignIn]' started.", "◇ Test signIn() started.", "✘ Test signIn() recorded an issue at A.swift:3:5", "Test Suite 'All tests' passed at 2026-10-24",
    "✔ Test run with 1 test in 0 suites passed after 0.055 seconds.", "✘ Test run with 3 tests in 1 suite failed after 0.2 seconds with 1 issue."]) {
    assert.equal(finishedCase(other), undefined, other);
  }
});

test("a run's tally says how it goes, and names the slowest cases", () => {
  const tally = new CaseTally();
  assert.equal(tally.progress(), "0 passed so far");
  tally.add({ name: "A/testFast", result: "passed", seconds: 0.1 });
  tally.add({ name: "A/testSlow", result: "passed", seconds: 3.2 });
  tally.add({ name: "B/testBroken", result: "failed", seconds: 1.4 });
  assert.equal(tally.progress(), "2 passed, 1 failed so far; last: B/testBroken failed (1.4 s)");
  assert.equal(tally.slowest(), "A/testSlow 3.2 s, B/testBroken 1.4 s");
  assert.equal(tally.count, 3);
});
