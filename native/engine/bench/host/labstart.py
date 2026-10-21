# The lab's opening, command by command as scripts/lab.sh runs them (no pauses), an engine read after each.
# As root: labstart.py <udid> <repo dir>
import json, subprocess, sys, time
udid, repo = sys.argv[1], sys.argv[2]
H = "/Users/nmsim2"; DEV = H + "/Library/Developer"
AS = ["launchctl", "asuser", "508", "sudo", "-u", "nmsim2", "-H", "env", "PATH=/usr/local/nomac-test/node/bin:/usr/bin:/bin:/usr/sbin:/sbin",
      f"HOME={H}", f"TMPDIR={DEV}/tmp/", "SIMULATOR_USE_NO_UPDATE=1", f"SIMULATOR_USE_CACHE_DIR={DEV}/su-cache"]
E = repo + "/vendor/axe/simulator-use-engine"
def engine_once(label):
    t = time.time()
    p = subprocess.run(AS + ["perl", "-e", "alarm 60; exec @ARGV", E, "--udid", udid], input='{"op":"describe","web":false}\n', capture_output=True, text=True)
    a = next((json.loads(l) for l in p.stdout.splitlines()[1:] if l.startswith("{")), {})
    print(f"    engine after {label}: {'read' if a.get('tree') else 'FAILED ' + str(a.get('error') or 'no answer')} in {int((time.time() - t) * 1000)} ms (waited {a.get('session_wait_ms')}, recoveries {a.get('session_recoveries')})", flush=True)
    return bool(a.get("tree"))
def cli(label, args, probe=True):
    t = time.time(); p = subprocess.run(AS + ["sh", "-c", f"cd {repo} && node bin/simulator-use.js {args}"], capture_output=True, text=True)
    out = (p.stdout + p.stderr).strip().splitlines()
    print(f"  {label}: exit {p.returncode} in {int((time.time() - t) * 1000)} ms: {out[:2]}", flush=True)
    return engine_once(label) if probe else True
time.sleep(40)
cli("use", "use golden")
cli("devices", "devices", probe=False)
t = time.time(); p = subprocess.run(AS + ["xcrun", "simctl", "privacy", udid, "reset", "all", "dev.simtap.edgelab"], capture_output=True, text=True)
print(f"  simctl privacy reset all: exit {p.returncode} in {int((time.time() - t) * 1000)} ms", flush=True)
engine_once("privacy reset")
if cli("run", f"run examples/edge-lab --device {udid}"):
    cli("look", f"look --device {udid}")
    cli("act tap #count-Increment", f"act --device {udid} 'tap #count-Increment'")
