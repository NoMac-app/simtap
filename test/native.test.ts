import assert from "node:assert/strict";
import { test } from "node:test";

import { engineGesture, engineSteps } from "../src/engine/native.ts";

test("AXe batch steps become engine steps", () => {
  assert.deepEqual(engineSteps(["tap -x 10 -y 20", "sleep 0.15", "key-combo --modifiers 227 --key 4", "key 42", "type 'it'\\''s'", "touch -x 5 -y 6 --down --up --delay 1.5"]), [
    { tap: [10, 20] },
    { sleep: 0.15 },
    { combo: { mods: [227], key: 4 } },
    { key: 42 },
    { type: "it's" },
    { touch: [5, 6], hold: 1.5 },
  ]);
});

test("a physical tap (switches, checkboxes) is a touch down and up", () => {
  assert.deepEqual(engineSteps(["tap -x 300 -y 120 --tap-style physical"]), [{ touch: [300, 120], hold: 0.1 }]);
});

test("a step the engine does not know sends the whole batch to AXe", () => {
  assert.equal(engineSteps(["tap -x 1 -y 2", "gesture scroll-up"]), undefined);
});

test("swipes and drags become engine gestures; anything else stays with AXe", () => {
  assert.deepEqual(engineGesture(["swipe", "--start-x", "350", "--start-y", "500", "--end-x", "50", "--end-y", "500", "--duration", "0.3"]),
    { op: "swipe", x1: 350, y1: 500, x2: 50, y2: 500, duration: 0.3 });
  assert.deepEqual(engineGesture(["drag", "--start-x", "1", "--start-y", "2", "--end-x", "3", "--end-y", "4"]), { op: "drag", x1: 1, y1: 2, x2: 3, y2: 4, duration: 0.6 });
  assert.equal(engineGesture(["slider", "--id", "x"]), undefined);
  assert.equal(engineGesture(["swipe", "--start-x", "1"]), undefined);
});

test("a slow request gets a busy answer, the engine stays, and the next request gets its own answer", async () => {
  const { closeEngines, engineCall } = await import("../src/engine/native.ts");
  process.env.SIMULATOR_USE_ENGINE = new URL("fixtures/fake-engine.mjs", import.meta.url).pathname;
  try {
    const slow = await engineCall("FAKE-PHONE", { op: "x", n: 1, delay_ms: 400 }, 100);
    assert.equal(slow?.busy, true);
    const next = await engineCall("FAKE-PHONE", { op: "x", n: 2 }, 2_000);
    assert.equal(next?.ok, true);
    assert.equal(next?.echo, 2);
  } finally {
    closeEngines();
    delete process.env.SIMULATOR_USE_ENGINE;
  }
});
