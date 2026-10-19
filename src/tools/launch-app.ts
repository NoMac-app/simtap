import { setTimeout as sleep } from "node:timers/promises";

import { appInfo, launch, startLogStream } from "../engine/apps.ts";
import { AccessibilityStarting } from "../engine/axe.ts";
import type { Device } from "../engine/simctl.ts";
import { setCurrentApp } from "../engine/state.ts";
import { ToolError } from "../errors.ts";
import { readScreen } from "../look/read.ts";
import { render } from "../look/snapshot.ts";

/** How long launch waits for the app to come to the front, then after a second launch: within the 45 s of a call. */
const FRONT_WAIT_MS = 12_000;
const RELAUNCH_WAIT_MS = 15_000;
const LAUNCH_BUDGET_MS = 42_000;

/**
 * Launches an installed app fresh, with its print output and own log lines kept for app_logs, and answers with
 * its first screen. The launch returns before the app is in front: on iOS 27 in a VM, the home screen still
 * showed seconds later, and right after a crash the app once stayed behind for over 20 s. So: wait, then launch
 * once more if there is time.
 */
export async function launchAndLook(device: Device, bundleId: string): Promise<string> {
  const label = `${device.name} (${device.runtime})`;
  const info = await appInfo(device.udid, bundleId);
  if (!info) throw new ToolError(`${bundleId} is not installed on ${label}.`, 'Install it with app_control {action: "install", app: "path/to/App.app"}.');
  const started = Date.now();
  if (info.executable) await startLogStream(device.udid, bundleId, info.executable);
  await launch(device.udid, bundleId);
  await setCurrentApp(device.udid, { bundleId, executable: info.executable, launchedAt: started });
  const name = info.name ?? info.executable ?? bundleId;
  // In front: the app itself, or the app under one of iOS's prompts ("Name · system alert"). Not "Name · system
  // screen": that is iOS still animating the launch, the app's card behind it (Xcode 27 VM, October 19).
  const front = (app: string) => app === name || app === `${name} · system alert`;
  const launched = () => `Launched ${name} in ${((Date.now() - started) / 1000).toFixed(1)} s`;
  const inFront = async (until: number) => {
    let { snap } = await readScreen(device.udid);
    while (!front(snap.app) && Date.now() < until) {
      await sleep(500);
      snap = (await readScreen(device.udid)).snap;
    }
    return snap;
  };
  try {
    let snap = await inFront(started + FRONT_WAIT_MS);
    let again = "";
    // Only while the call has time for it: a cold Simulator's first read alone can take 35 s.
    if (!front(snap.app) && Date.now() - started < LAUNCH_BUDGET_MS - RELAUNCH_WAIT_MS) {
      await launch(device.udid, bundleId);
      snap = await inFront(Date.now() + RELAUNCH_WAIT_MS);
      again = " (launched twice: it was not in front after the first)";
    }
    // In front is not finished: right after launch a SwiftUI stepper's buttons joined the tree a read later.
    for (let i = 0; i < 3 && front(snap.app); i++) {
      await sleep(400);
      const next = (await readScreen(device.udid, false)).snap;
      if (render(next) === render(snap)) break;
      snap = next;
    }
    const late = front(snap.app) ? "" : `\n${name} is not in front yet; call ui_look shortly, or launch again.`;
    return `${launched()}${again}.${late}\n${render(snap, { device: label })}`;
  } catch (error) {
    // The launch worked; only reading the screen isn't possible yet (a first boot's accessibility service took
    // over 35 s on a fresh Xcode 27 Mac). That is not a failed launch.
    if (!(error instanceof AccessibilityStarting)) throw error;
    return `${launched()}. Its screen can't be read yet: the Simulator's accessibility service is still starting, as it does for a minute or two after a first boot.\nNext: ui_look in 30 seconds.`;
  }
}
