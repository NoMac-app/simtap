import { createHash } from "node:crypto";
import { mkdir, readFile, rm, stat, writeFile } from "node:fs/promises";
import { join } from "node:path";

import { stateDir } from "./state.ts";

const alive = (pid: number) => {
  try {
    process.kill(pid, 0);
    return true;
  } catch (error) {
    return (error as NodeJS.ErrnoException).code === "EPERM";
  }
};

/** A lock's directory: names that are not plain words (a project's path) are hashed. */
const lockDir = (name: string) => join(stateDir(), `${/^[\w.-]{1,80}$/.test(name) ? name : createHash("sha1").update(name).digest("hex").slice(0, 16)}.lock.d`);

/**
 * Takes a lock shared by every simulator-use process on this Mac (each agent, and each CLI call, is its own process).
 * The lock is a directory, made atomically, holding the owner's pid; a lock whose owner died, or that was left
 * without a pid for 60 s, is taken over. Returns its release, or the pid that holds it.
 */
export async function tryLock(name: string): Promise<{ release: () => Promise<void> } | { holder: number }> {
  await mkdir(stateDir(), { recursive: true });
  const lock = lockDir(name);
  const owner = join(lock, "pid");
  for (;;) {
    try {
      await mkdir(lock);
      await writeFile(owner, String(process.pid));
      return {
        // Only its owner removes it: one taken over from a dead owner belongs to someone else now.
        release: async () => {
          if (Number(await readFile(owner, "utf8").catch(() => "0")) === process.pid) await rm(lock, { recursive: true, force: true });
        },
      };
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== "EEXIST") throw error;
      const holder = Number(await readFile(owner, "utf8").catch(() => "0"));
      const age = Date.now() - ((await stat(lock).catch(() => undefined))?.mtimeMs ?? Date.now());
      // An empty pid is a lock being made right now, unless it has been empty for a minute.
      if ((holder && !alive(holder)) || (!holder && age > 60_000)) {
        await rm(lock, { recursive: true, force: true });
        continue;
      }
      return { holder };
    }
  }
}

/** Runs work holding the lock, waiting for it up to waitMs; past that, busy() says why it can't. */
export async function withLock<T>(name: string, waitMs: number, busy: (holder: number) => Error, work: () => Promise<T>): Promise<T> {
  const deadline = Date.now() + waitMs;
  for (;;) {
    const taken = await tryLock(name);
    if ("release" in taken) {
      try {
        return await work();
      } finally {
        await taken.release();
      }
    }
    if (Date.now() > deadline) throw busy(taken.holder);
    await new Promise((r) => setTimeout(r, 250));
  }
}
