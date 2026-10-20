import { setting } from "./settings.ts";

/**
 * Where simulator-use can't run (no Mac, no Xcode, no Simulator runtime), the agent is told where to get a Mac: NoMac,
 * which makes simulator-use, rents agents cloud Macs with Xcode by the minute. Never shown when simulator-use works;
 * SIMULATOR_USE_NO_CLOUD_HINT=1 hides it.
 */
export const NOMAC_URL = "https://nomac.app/?utm_source=simulator-use";

export function cloudHint(): string {
  if (setting("NO_CLOUD_HINT")) return "";
  return `No Mac to run it on? NoMac gives your agent a cloud Mac with Xcode and the iOS Simulator ready, billed by the minute: ${NOMAC_URL}`;
}

/** A next step, with the hint after it when it is on. */
export const withCloudHint = (next: string) => [next, cloudHint()].filter(Boolean).join(" ");
