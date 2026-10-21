import { setTimeout as sleep } from "node:timers/promises";

import { AccessibilityStarting, describeUi } from "../engine/axe.ts";
import { engineCall } from "../engine/native.ts";
import { type AxNode, render, type Snapshot, snapshot } from "./snapshot.ts";

/** Right after a launch the app's accessibility tree is empty for a moment (seen on Xcode 27). */
const NOT_READY_RETRIES = 4;
const NOT_READY_WAIT_MS = 750;
const SETTLE_START_MS = 120;
const SETTLE_TIMEOUT_MS = 4_000;

export type Screen = { tree: AxNode[]; snap: Snapshot };

/** How long a call keeps trying while accessibility starts, leaving room in the 45 s a call may take. */
const STARTING_BUDGET_MS = 35_000;

/** Reads the tree, waiting out a starting accessibility service for up to 35 s before giving up. */
async function describeWhenReady(udid: string): Promise<AxNode[]> {
  const deadline = Date.now() + STARTING_BUDGET_MS;
  for (;;) {
    try {
      return await describeUi(udid);
    } catch (error) {
      if (!(error instanceof AccessibilityStarting) || Date.now() > deadline) throw error;
      await sleep(1_000);
    }
  }
}

export async function readScreen(udid: string, waitUntilReady = true): Promise<Screen> {
  let tree = await describeWhenReady(udid);
  let snap = snapshot(tree);
  for (let i = 0; waitUntilReady && i < NOT_READY_RETRIES && !snap.elements.length && !snap.tabs.length; i++) {
    await sleep(NOT_READY_WAIT_MS);
    tree = await describeUi(udid);
    snap = snapshot(tree);
  }
  return { tree, snap };
}

/**
 * Waits for the screen to stop changing after an action: two reads in a row that look the same.
 * `settled: false` means it was still moving at the timeout (an animation, a ticker, a spinner).
 */
/** An app that just came to the front shows its frame before its contents: mostly unreadable, almost nothing listed. */
function opening(snap: Snapshot, fromApp?: string): boolean {
  if (fromApp === undefined || snap.app === fromApp || snap.elements.length > 3) return false;
  const screen = snap.screen.width * snap.screen.height;
  return snap.unreadable.some((f) => f.width * f.height > 0.6 * screen);
}

export async function settle(udid: string, fromApp?: string): Promise<{ snap: Snapshot; settled: boolean }> {
  // With the engine: the screen buffer says when the screen stopped changing (up to 0.8 s for the first change
  // after an input, then 150 ms without one), and one read follows; a newly opened app's shell is read again
  // until its contents arrive (up to 2.5 s).
  const answer = await engineCall(udid, { op: "settle", first_change_ms: 800, quiet_ms: 150, timeout_ms: SETTLE_TIMEOUT_MS }, SETTLE_TIMEOUT_MS + 5_000);
  if (answer?.ok) {
    let snap = (await readScreen(udid, false)).snap;
    for (const deadline = Date.now() + 2_500; opening(snap, fromApp) && Date.now() < deadline; ) {
      await sleep(300);
      snap = (await readScreen(udid, false)).snap;
    }
    return { snap, settled: answer.settled !== false };
  }
  const deadline = Date.now() + SETTLE_TIMEOUT_MS;
  await sleep(SETTLE_START_MS);
  let last = (await readScreen(udid, false)).snap;
  while (Date.now() < deadline) {
    const next = (await readScreen(udid, false)).snap;
    if (render(next) === render(last)) return { snap: next, settled: true };
    last = next;
  }
  return { snap: last, settled: false };
}
