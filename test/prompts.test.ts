import assert from "node:assert/strict";
import { test } from "node:test";

import { openInPrompt, permissionPrompt } from "../src/engine/prompts.ts";
import type { Element, Snapshot } from "../src/look/snapshot.ts";

const frame = { x: 0, y: 0, width: 10, height: 10 };
const el = (kind: string, label: string): Element => ({ kind, label, x: 1, y: 1, frame });
const snap = (app: string, elements: Element[], modal?: "alert" | "screen"): Snapshot => ({
  app, elements, tabs: [], keyboard: false, hidden: { above: 0, below: 0, left: 0, right: 0 }, unreadable: [], screen: { x: 0, y: 0, width: 402, height: 874 }, ...(modal ? { modal } : {}),
});

test("iOS's Open in prompt is recognised, with its Open button, and nothing else is", () => {
  // As the phone showed it on October 23, after app_control open_url exps://...
  const asked = snap("System alert", [el("alert", "Open in “Expo Go”?"), el("button", "Cancel"), el("button", "Open")], "alert");
  assert.equal(openInPrompt(asked), "Open in “Expo Go”?");
  assert.equal(openInPrompt(snap("System alert", [el("alert", "Open in “Expo Go”?"), el("button", "Cancel")], "alert")), undefined, "no Open button");
  assert.equal(openInPrompt(snap("Demo", [el("text", "Open in “Expo Go”?"), el("button", "Open")])), undefined, "not an alert");
  assert.equal(openInPrompt(snap("System alert", [el("alert", "Delete “Notes”?"), el("button", "Delete")], "alert")), undefined, "another alert");
});

test("a permission prompt over the app is answered with the button that allows; other alerts are not", () => {
  const notifications = snap("Ice Cubes · system alert", [el("alert", "“Ice Cubes” Would Like to Send You Notifications"), el("button", "Don’t Allow"), el("button", "Allow")], "alert");
  assert.deepEqual(permissionPrompt(notifications, "Ice Cubes"), { title: "“Ice Cubes” Would Like to Send You Notifications", allow: "Allow" });
  const location = snap("Maps Demo · system alert", [el("alert", "Allow “Maps Demo” to use your location?"), el("button", "Allow Once"), el("button", "Allow While Using App"), el("button", "Don’t Allow")], "alert");
  assert.equal(permissionPrompt(location, "Maps Demo")?.allow, "Allow While Using App");
  const camera = snap("Cam · system alert", [el("alert", "“Cam” Would Like to Access the Camera"), el("button", "Don’t Allow"), el("button", "OK")], "alert");
  assert.equal(permissionPrompt(camera, "Cam")?.allow, "OK");
  // iOS 26's photos prompt, as the phone showed it on October 23.
  const photos = snap("EdgeLab · system alert", [el("alert", "“EdgeLab” would like full access to your Photo Library."), el("button", "Limit Access…"), el("button", "Allow Full Access"), el("button", "Don’t Allow")], "alert");
  assert.equal(permissionPrompt(photos, "EdgeLab")?.allow, "Allow Full Access");
  // Over another app, or an alert that asks for no permission: left to the agent.
  assert.equal(permissionPrompt(notifications, "Demo"), undefined);
  assert.equal(permissionPrompt(snap("Demo · system alert", [el("alert", "Save Password?"), el("button", "Not Now"), el("button", "Save")], "alert"), "Demo"), undefined);
  assert.equal(permissionPrompt(snap("Demo", [el("text", "Would Like to Send You Notifications"), el("button", "Allow")]), "Demo"), undefined, "the app's own screen");
});
