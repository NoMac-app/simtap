# The engine recovering a wedged phone on its own: wedge it with the old engine (two back to back), then one read
# with the recovering engine. As the Mac's own user. Usage: recover.py <udid>
import json, subprocess, sys, time
udid = sys.argv[1]
OLD, REC = "/usr/local/nomac-test/engine/simulator-use-engine", "/usr/local/nomac-test/engine/sue-rec"
def once(path, label):
    t = time.time()
    p = subprocess.run(["perl", "-e", "alarm 90; exec @ARGV", path, "--udid", udid], input='{"op":"describe","web":false}\n', capture_output=True, text=True)
    a = next((json.loads(l) for l in p.stdout.splitlines()[1:] if l.startswith("{")), {})
    print(f"  {label}: {'read' if a.get('tree') else 'FAILED ' + str(a.get('error') or 'no answer')} in {int((time.time() - t) * 1000)} ms, recoveries {a.get('session_recoveries')}, waited {a.get('session_wait_ms')} ms", flush=True)
time.sleep(60)
once(OLD, "old engine 1"); once(OLD, "old engine 2, right after (wedges the phone)")
for i in range(4): once(REC, f"recovering engine {i + 1}, back to back")
for i in range(3): time.sleep(5); once(REC, f"recovering engine, 5 s after the last ({i + 1})")
time.sleep(30); once(REC, "recovering engine, 30 s after the last")
