# A clone of a golden phone: time to readable, load over 5 minutes, CPU by process, and a few apps open.
import json, subprocess, sys, time, os, re
ENGINE = os.path.expanduser("~/sue/sue-engine"); GOLD = sys.argv[1]
def sh(*a): return subprocess.run(a, capture_output=True, text=True).stdout.strip()
load = lambda: sh("sysctl", "-n", "vm.loadavg").split()[1]
t0 = time.time(); u = sh("xcrun", "simctl", "clone", GOLD, f"lean-{int(t0)}")
subprocess.run(["xcrun", "simctl", "boot", u]); subprocess.run(["xcrun", "simctl", "bootstatus", u, "-b"], capture_output=True); tb = time.time()
p = subprocess.Popen([ENGINE, "--udid", u], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1); json.loads(p.stdout.readline())
def call(req): p.stdin.write(json.dumps(req) + "\n"); p.stdin.flush(); return json.loads(p.stdout.readline())
while time.time() - t0 < 240:
    a = call({"op": "describe"})
    if a.get("ok") and a.get("tree"): break
    time.sleep(0.25)
tr = time.time()
print(f"clone+boot {tb-t0:.1f} s, readable {tr-t0:.1f} s after the clone began; widgets on screen: {json.dumps(a.get('tree')).count('Widget')}", flush=True)
marks = [30, 60, 120, 180, 300]; out = []
for m in marks:
    time.sleep(max(0, t0 + m - time.time())); out.append(f"{m}s:{load()}")
print("load", " ".join(out), flush=True)
cpu = {}
for line in sh("ps", "-Ao", "cputime=,comm=").splitlines():
    if "SimulatorRuntime" not in line: continue
    t, cmd = line.split(None, 1); parts = [float(x) for x in t.split(":")]
    secs = parts[0] * 60 + parts[1] if len(parts) == 2 else parts[0] * 3600 + parts[1] * 60 + parts[2]
    name = cmd.rsplit("/", 1)[-1]; cpu[name] = cpu.get(name, 0) + secs
print("CPU s:", ", ".join(f"{k} {v:.0f}" for k, v in sorted(cpu.items(), key=lambda kv: -kv[1])[:10]), flush=True)
print("newsd running:", "com.apple.newsd" in sh("xcrun", "simctl", "spawn", u, "launchctl", "list"), flush=True)
for bundle in ["com.apple.Preferences", "com.apple.mobilesafari", "com.apple.Maps"]:
    t = time.time(); r = subprocess.run(["xcrun", "simctl", "launch", u, bundle], capture_output=True, text=True)
    ok = False
    while time.time() - t < 20:
        a = call({"op": "describe"}); first = (a.get("tree") or [{}])[0]
        if a.get("ok") and first.get("AXLabel") not in (None, "", "Home screen icons"): ok = True; break
        time.sleep(0.25)
    print(f"  launch {bundle}: {'readable as ' + repr(first.get('AXLabel')) if ok else 'NOT readable'} in {time.time()-t:.1f} s {r.stderr.strip()[:80]}", flush=True)
p.stdin.close(); p.wait()
print("clone", u, flush=True)
open(os.path.expanduser("~/sue/lean-clone.udid"), "w").write(u)
