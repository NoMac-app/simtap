# How long after boot a new engine process (one per CLI command) can open an automation session: an engine reads
# and exits every 30 s from 30 s after boot, with AXe's own read between them. Usage (as root): young.py <udid> <boot epoch>
import json, subprocess, sys, time
udid, booted = sys.argv[1], float(sys.argv[2])
AS = ["launchctl", "asuser", "508", "sudo", "-u", "nmsim2", "-H"]
E = "/usr/local/nomac-test/engine/simulator-use-engine"
AXE = "/usr/local/nomac-test/su-next/lib/node_modules/simulator-use/vendor/axe/axe"
def engine_once():
    t = time.time()
    p = subprocess.run(AS + ["perl", "-e", "alarm 45; exec @ARGV", E, "--udid", udid], input='{"op":"describe","web":false}\n', capture_output=True, text=True)
    lines = [json.loads(l) for l in p.stdout.splitlines() if l.startswith("{")]
    a = lines[1] if len(lines) > 1 else {}
    return ("read" if a.get("tree") else f"FAILED ({a.get('error') or 'no answer'})"), int((time.time() - t) * 1000)
def axe_once():
    t = time.time()
    p = subprocess.run(AS + ["perl", "-e", "alarm 45; exec @ARGV", AXE, "describe-ui", "--udid", udid], capture_output=True, text=True)
    return ("read" if p.returncode == 0 and p.stdout.strip().startswith("[") else f"FAILED ({(p.stderr or p.stdout).strip()[:60]})"), int((time.time() - t) * 1000)
next_at = booted + 30
while time.time() - booted < 660:
    time.sleep(max(0, next_at - time.time()))
    age = int(time.time() - booted)
    e1 = engine_once(); time.sleep(1)
    ax = axe_once(); time.sleep(1)
    e2 = engine_once()
    print(f"  phone {age:3d} s old: engine {e1[0]} {e1[1]} ms; AXe after it {ax[0]} {ax[1]} ms; engine again {e2[0]} {e2[1]} ms", flush=True)
    next_at += 60
