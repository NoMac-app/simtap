# What changes the screen's seed: describes with the web scan, a pause, describes without it. Usage: seeds.py <udid>
import json, os, subprocess, sys, time
udid = sys.argv[1]
AS = ["launchctl", "asuser", "508", "sudo", "-u", "nmsim2", "-H"]
eng = subprocess.Popen(AS + [os.environ["ENGINE"], "--udid", udid], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1)
eng.stdout.readline()
def call(req):
    eng.stdin.write(json.dumps(req) + "\n"); eng.stdin.flush(); return json.loads(eng.stdout.readline())
for _ in range(3):
    if call({"op": "describe", "web": False}).get("tree"): break
subprocess.run(AS + ["xcrun", "simctl", "launch", udid, "app.nomac.webtest"], capture_output=True); time.sleep(5)
for i in range(4):
    a = call({"op": "describe"}); w = a.get("web_scan") or {}
    print(f"  read {i + 1}: seed before {w.get('seed_before')}, after {w.get('seed_after')}, cached {w.get('cached')}, {w.get('ms')} ms", flush=True)
    time.sleep(1)
for i in range(3):
    call({"op": "describe", "web": False}); time.sleep(0.5)
    a = call({"op": "describe"}); w = a.get("web_scan") or {}
    print(f"  after a read without the scan: seed before {w.get('seed_before')}, after {w.get('seed_after')}, cached {w.get('cached')}", flush=True)
p = call({"op": "point", "x": 200, "y": 300}); a = call({"op": "describe"}); w = a.get("web_scan") or {}
print(f"  after one point read: seed before {w.get('seed_before')}, after {w.get('seed_after')}, cached {w.get('cached')}", flush=True)
eng.stdin.close(); eng.wait(timeout=10)
