# Can a wedged phone (no automation session opens) be fixed without a reboot? Wedge one with the old engine (two
# engines back to back), then restart the phone's own test daemon and try again. As the Mac's own user.
# Usage: unwedge.py <udid>
import json, subprocess, sys, time
udid = sys.argv[1]
OLD = "/usr/local/nomac-test/engine/simulator-use-engine"
NEW = "/usr/local/nomac-test/engine/simulator-use-engine.next"
def engine_once(path, label):
    t = time.time()
    p = subprocess.run(["perl", "-e", "alarm 45; exec @ARGV", path, "--udid", udid], input='{"op":"describe","web":false}\n', capture_output=True, text=True)
    a = next((json.loads(l) for l in p.stdout.splitlines()[1:] if l.startswith("{")), {})
    print(f"  {label}: {'read' if a.get('tree') else 'FAILED ' + str(a.get('error') or 'no answer')} in {int((time.time() - t) * 1000)} ms", flush=True)
    return bool(a.get("tree"))
time.sleep(60)
engine_once(OLD, "old engine 1"); engine_once(OLD, "old engine 2, right after")
if engine_once(NEW, "the new engine, wedged phone?"):
    print("  not wedged; nothing to recover", flush=True); sys.exit(0)
jobs = subprocess.run(["xcrun", "simctl", "spawn", udid, "launchctl", "list"], capture_output=True, text=True).stdout
labels = [l.split()[-1] for l in jobs.splitlines() if "testmanager" in l.lower() or "xctest" in l.lower() or "automation" in l.lower()]
print(f"  test daemons in the phone: {labels}", flush=True)
for label in labels:
    r = subprocess.run(["xcrun", "simctl", "spawn", udid, "launchctl", "stop", label], capture_output=True, text=True)
    print(f"  stopped {label}: exit {r.returncode} {r.stderr.strip()[:60]}", flush=True)
time.sleep(3)
if engine_once(NEW, "the new engine after the daemons were restarted"): sys.exit(0)
time.sleep(20)
engine_once(NEW, "again 20 s later")
