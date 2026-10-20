import { existsSync } from "node:fs";
import { resolve as resolvePath } from "node:path";

import { appInfo, BUNDLE_ID, bundleIdOf, install, pushPayload, simctlAction, stopLogStream } from "../engine/apps.ts";
import { listDevices, pickDevice } from "../engine/simctl.ts";
import { currentApp, heldDevice, setCurrentApp } from "../engine/state.ts";
import { ToolError } from "../errors.ts";
import { readScreen } from "../look/read.ts";
import { render } from "../look/snapshot.ts";
import { launchAndLook } from "./launch-app.ts";
import type { Tool } from "./types.ts";

const ACTIONS = ["launch", "install", "terminate", "uninstall", "open_url", "grant", "revoke", "reset_permissions", "location", "push"];
/** What simctl privacy takes (its help, plus camera, which it also accepts). */
const PERMISSIONS = ["all", "calendar", "camera", "contacts", "contacts-limited", "location", "location-always", "media-library", "microphone", "motion", "photos", "photos-add", "reminders", "siri"];

/** What `value` holds for each action that needs one. */
const VALUE: Record<string, string> = {
  open_url: "a URL or deep link",
  grant: "a permission: photos, photos-add, location, location-always, contacts, camera, microphone, calendar, reminders, motion, media-library, siri or all",
  revoke: "a permission, as for grant",
  location: '"latitude,longitude", or "clear"',
  push: 'the notification text, or a JSON payload with "aps"',
};

/** A push from plain text, or the agent's own JSON payload, checked the way simctl will. */
export function pushJson(value: string): string {
  const trimmed = value.trim();
  if (!trimmed.startsWith("{")) return JSON.stringify({ aps: { alert: trimmed, sound: "default" } });
  let parsed: unknown;
  try {
    parsed = JSON.parse(trimmed);
  } catch {
    throw new ToolError("The push payload is not valid JSON.", 'Send plain text, or JSON such as {"aps": {"alert": "Hello"}}.');
  }
  if (!parsed || typeof parsed !== "object" || !("aps" in parsed)) throw new ToolError('A push payload needs an "aps" object.', 'For example {"aps": {"alert": "Hello"}}.');
  if (Buffer.byteLength(trimmed) > 4096) throw new ToolError("The push payload is over 4 KB, the limit for a push.");
  return trimmed;
}

export const appControl: Tool = {
  name: "app_control",
  title: "Control an app",
  description:
    "Launch, install, stop or remove an app on the Simulator; open a URL or deep link; grant, revoke or reset a permission; set the location; send a push. launch answers with the app's first screen; later calls default to the app launched last.",
  inputSchema: {
    type: "object",
    properties: {
      action: { type: "string", enum: ACTIONS, description: "What to do" },
      app: { type: "string", description: "Bundle id, or for install the path to a Simulator .app" },
      value: { type: "string", description: "URL, permission, latitude,longitude, or push text/JSON, per action" },
      device: { type: "string", description: "Name or UDID; default: the one in use" },
    },
    required: ["action"],
    additionalProperties: false,
  },
  annotations: { readOnlyHint: false, destructiveHint: true, idempotentHint: false, openWorldHint: false },
  command: "app",
  positional: ["action", "value"],
  async run(args) {
    const action = args.action as string;
    const device = pickDevice(await listDevices(), args.device as string | undefined, heldDevice());
    const label = `${device.name} (${device.runtime})`;
    // Actions without a value take the app as their one word: `simulator-use app launch dev.example.app`.
    const takesValue = Boolean(VALUE[action]) || action === "reset_permissions";
    const value = takesValue ? (args.value as string | undefined) : undefined;
    const app = (args.app as string | undefined) ?? (takesValue ? undefined : (args.value as string | undefined));
    if (VALUE[action] && !value) throw new ToolError(`${action} needs value: ${VALUE[action]}.`);

    if (action === "install") {
      const path = app ? resolvePath(app) : "";
      if (!path || !existsSync(path)) throw new ToolError("install needs app: the path to a .app built for the Simulator.", "Build with xcodebuild -sdk iphonesimulator; the .app is under Build/Products/Debug-iphonesimulator.");
      const bundleId = await bundleIdOf(path);
      await install(device.udid, path);
      const info = await appInfo(device.udid, bundleId);
      await setCurrentApp(device.udid, { bundleId, executable: info?.executable });
      return { text: `Installed ${info?.name ?? bundleId} (${bundleId}) on ${label}. Next: app_control {action: "launch"}.` };
    }

    // Every other action works on an installed app: the one named, or the one launched last.
    const bundleId = app ?? (await currentApp(device.udid))?.bundleId;
    if (bundleId && !BUNDLE_ID.test(bundleId)) throw new ToolError(`"${bundleId}" is not a bundle id.`, "A bundle id looks like com.example.app; install takes the path to a .app.");
    const needsApp = !["open_url", "location", "reset_permissions"].includes(action);
    if (needsApp && !bundleId) throw new ToolError(`${action} needs app: the bundle id.`, "Pass app, or launch the app first.");

    switch (action) {
      case "launch":
        return { text: await launchAndLook(device, bundleId!) };
      case "terminate":
        await simctlAction(["terminate", device.udid, bundleId!], `stop ${bundleId}`).catch((error: ToolError) => {
          if (!/found nothing to terminate|not running/i.test(error.message)) throw error;
        });
        return { text: `Stopped ${bundleId}.` };
      case "uninstall":
        await stopLogStream(device.udid, bundleId!);
        await simctlAction(["uninstall", device.udid, bundleId!], `remove ${bundleId}`);
        return { text: `Removed ${bundleId} and its data from ${label}.` };
      case "open_url":
        await simctlAction(["openurl", device.udid, value!], `open ${value}`);
        return { text: `Opened ${value}.\n${render((await readScreen(device.udid)).snap, { device: label })}` };
      case "grant":
      case "revoke":
        if (!PERMISSIONS.includes(value!)) throw new ToolError(`Unknown permission "${value}".`, `Permissions: ${PERMISSIONS.join(", ")}.`);
        await simctlAction(["privacy", device.udid, action, value!, bundleId!], `${action} ${value}`);
        return { text: `${action === "grant" ? "Granted" : "Revoked"} ${value} for ${bundleId}. The app may have been stopped: iOS does that when a permission changes.` };
      case "reset_permissions":
        await simctlAction(["privacy", device.udid, "reset", value ?? "all", ...(bundleId ? [bundleId] : [])], "reset permissions");
        return { text: `Reset ${value ?? "all"} permissions${bundleId ? ` for ${bundleId}` : ""}: the app asks again on next use.` };
      case "location": {
        if (value!.trim() === "clear") {
          await simctlAction(["location", device.udid, "clear"], "clear the location");
          return { text: "Cleared the simulated location." };
        }
        const match = /^\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*$/.exec(value!);
        if (!match || Math.abs(Number(match[1])) > 90 || Math.abs(Number(match[2])) > 180) throw new ToolError(`"${value}" is not latitude,longitude.`, 'For example "47.4979,19.0402".');
        await simctlAction(["location", device.udid, "set", `${match[1]},${match[2]}`], "set the location");
        return { text: `Location set to ${match[1]},${match[2]}.` };
      }
      case "push":
        await pushPayload(device.udid, bundleId!, pushJson(value!));
        return { text: `Sent a push to ${bundleId}.` };
      default:
        throw new ToolError(`Unknown action "${action}". Actions: ${ACTIONS.join(", ")}.`);
    }
  },
};
