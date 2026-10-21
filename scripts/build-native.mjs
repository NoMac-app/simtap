// Builds simulator-use's native parts into vendor/axe, beside AXe's frameworks, and checks them: the engine
// (native/engine, a persistent Simulator driver; it needs idb's private headers at compile time, IDB_HEADERS) and
// the clipboard helper (native/pbset, built for the Simulator). Run by prepack after fetch-axe.mjs: a release
// without the engine would quietly fall back to AXe everywhere, so a missing IDB_HEADERS stops it. Set
// SIMULATOR_USE_SKIP_NATIVE=1 to pack without them (a local tarball for testing AXe alone).
import { execFileSync } from "node:child_process";
import { existsSync, statSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("..", import.meta.url));
const vendor = join(root, "vendor", "axe");
if (process.env.SIMULATOR_USE_SKIP_NATIVE === "1") {
  console.log("native parts skipped (SIMULATOR_USE_SKIP_NATIVE=1): the package will use AXe alone");
  process.exit(0);
}
if (!existsSync(join(vendor, "Frameworks", "FBSimulatorControl.framework"))) throw new Error("AXe's frameworks are missing from vendor/axe: run scripts/fetch-axe.mjs first");
if (!process.env.IDB_HEADERS || !existsSync(process.env.IDB_HEADERS)) {
  throw new Error("IDB_HEADERS must point at idb's PrivateHeaders (github.com/cameroncooke/idb at the commit AXe pins) to build the engine; SIMULATOR_USE_SKIP_NATIVE=1 packs without it");
}
const sh = (script) => execFileSync("bash", [script], { cwd: root, stdio: "inherit", env: process.env });
sh(join(root, "native", "engine", "build.sh"));
execFileSync("mv", [join(root, "native", "engine", "simulator-use-engine"), join(vendor, "simulator-use-engine")]);
sh(join(root, "native", "pbset", "build.sh"));
for (const [name, platform] of [["simulator-use-engine", "macOS"], ["simulator-use-pbset", "iOS Simulator"]]) {
  const path = join(vendor, name);
  const info = execFileSync("file", [path], { encoding: "utf8" });
  if (!/Mach-O/.test(info) || !/arm64/.test(info)) throw new Error(`${name} is not an arm64 Mach-O binary: ${info.trim()}`);
  execFileSync("codesign", ["--verify", path]);
  console.log(`${name}: ${Math.round(statSync(path).size / 1024)} KB, for ${platform}, signed`);
}
