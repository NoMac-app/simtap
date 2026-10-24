import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

import { derivedDataFor, xcodeEnv } from "../src/engine/xcode.ts";
import { describeXcodes, listXcodes, pickXcode, setApplicationsDir } from "../src/engine/xcodes.ts";

const plist = (pairs: Record<string, string>) =>
  `<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict>${Object.entries(pairs).map(([k, v]) => `<key>${k}</key><string>${v}</string>`).join("")}</dict></plist>`;

function applications(xcodes: Record<string, [string, string]>) {
  const dir = mkdtempSync(join(tmpdir(), "su-apps-"));
  for (const [name, [version, build]] of Object.entries(xcodes)) {
    mkdirSync(join(dir, name, "Contents", "Developer"), { recursive: true });
    writeFileSync(join(dir, name, "Contents", "Info.plist"), plist({ CFBundleShortVersionString: version }));
    writeFileSync(join(dir, name, "Contents", "version.plist"), plist({ ProductBuildVersion: build }));
  }
  mkdirSync(join(dir, "Safari.app"));
  return dir;
}

test("this Mac's Xcodes: newest first, betas named, the default the one DEVELOPER_DIR names, and picked by version", { skip: process.platform !== "darwin" }, async () => {
  const dir = applications({ "Xcode.app": ["27.0", "27A266a"], "Xcode-27.1.app": ["27.1", "27A9275"], "Xcode-26.6.app": ["26.6", "17F100"], "Xcode-27.2-beta.app": ["27.2", "27B5038j"] });
  const saved = process.env.DEVELOPER_DIR;
  process.env.DEVELOPER_DIR = join(dir, "Xcode.app", "Contents", "Developer");
  setApplicationsDir(dir);
  try {
    const list = await listXcodes();
    assert.equal(describeXcodes(list), "27.2 beta, 27.1, 27.0 (default), 26.6");
    assert.equal((await pickXcode("27.1"))?.path, join(dir, "Xcode-27.1.app"));
    assert.equal((await pickXcode("Xcode 26"))?.version, "26.6");
    assert.equal((await pickXcode("27"))?.version, "27.1", "a major is its newest release, not the beta");
    assert.equal((await pickXcode("beta"))?.build, "27B5038j");
    assert.equal((await pickXcode("default"))?.version, "27.0");
    assert.equal(await pickXcode(undefined), undefined);
    await assert.rejects(pickXcode("25.0"), (error: Error & { next?: string }) =>
      error.message === "No Xcode 25.0 on this Mac." && /27\.2 beta, 27\.1, 27\.0 \(default\), 26\.6/.test(String(error.next)));
    // A build with another Xcode runs in its environment and has its own DerivedData; the default's stays as it was.
    const other = (await pickXcode("26.6"))!, def = (await pickXcode("default"))!;
    assert.equal(xcodeEnv(other).DEVELOPER_DIR, other.developer);
    assert.equal(xcodeEnv(def), process.env);
    const project = { name: "Demo", path: "/w/Demo.xcodeproj", dir: "/w", kind: "project" } as Parameters<typeof derivedDataFor>[0];
    assert.match(derivedDataFor(project, other), /Demo-[a-f0-9]{12}-xcode26\.6$/);
    assert.equal(derivedDataFor(project, def), derivedDataFor(project));
  } finally {
    if (saved === undefined) delete process.env.DEVELOPER_DIR;
    else process.env.DEVELOPER_DIR = saved;
    setApplicationsDir("/Applications");
  }
});
