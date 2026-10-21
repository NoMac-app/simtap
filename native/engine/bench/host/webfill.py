# simulator-use's fill, step by step through one engine, each request timed, to find the one that hangs on a web
# field: tap, select all, delete, type (as one steps request), then point reads on the focused field.
# Usage (as root): webfill.py <udid>
import json, os, select, subprocess, sys, time
udid = sys.argv[1]
AS = ["launchctl", "asuser", "508", "sudo", "-u", "nmsim2", "-H"]
eng = subprocess.Popen(AS + ["/usr/local/nomac-test/engine/simulator-use-engine.web", "--udid", udid], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1)
eng.stdout.readline()
def call(req, timeout=40):
    eng.stdin.write(json.dumps(req) + "\n"); eng.stdin.flush()
    r, _, _ = select.select([eng.stdout], [], [], timeout)
    if not r: return {"error": f"no answer in {timeout} s"}
    return json.loads(eng.stdout.readline())
def timed(label, req, timeout=40):
    t = time.time(); a = call(req, timeout); ms = int((time.time() - t) * 1000)
    e = a.get("element") or {}
    print(f"  {label}: {ms} ms {a.get('error') or ''} {('-> ' + str(e.get('role')) + ' ' + repr(e.get('AXValue'))) if e else ''}", flush=True)
    return a
for _ in range(3):
    if call({"op": "describe", "web": False}).get("tree"): break
subprocess.run(AS + ["xcrun", "simctl", "launch", udid, "app.nomac.webtest"], capture_output=True); time.sleep(5)
timed("describe", {"op": "describe"})
fx, fy = 192, 277
timed("point on the field before", {"op": "point", "x": fx, "y": fy})
timed("steps: tap, sleep, cmd+A, delete, type", {"op": "steps", "steps": [{"tap": [fx, fy]}, {"sleep": 0.15}, {"combo": {"mods": [227], "key": 4}}, {"key": 42}, {"type": "agent@nomac.app"}]})
for i in range(3):
    timed(f"point on the focused field {i + 1}", {"op": "point", "x": fx, "y": fy}); time.sleep(0.3)
timed("describe with the keyboard up", {"op": "describe"})
timed("settle", {"op": "settle", "first_change_ms": 0})
timed("point on Continue", {"op": "point", "x": 183, "y": 444})
eng.stdin.close()
try: eng.wait(timeout=10)
except Exception: eng.kill()
