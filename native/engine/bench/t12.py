# T12: builds next to phones. N settled lean phones, each driven in a loop (home, open Settings: tap,
# settle, read); act latency alone, then during an incremental build at normal and at background priority.
import json, subprocess, sys, time, os, threading, statistics
N = int(sys.argv[1]); GOLD = sys.argv[2]; ENGINE = os.path.expanduser("~/sue/sue-engine"); PROJ = os.path.expanduser("~/IceCubesApp")
def sh(*a): return subprocess.run(a, capture_output=True, text=True).stdout.strip()
load = lambda: sh("sysctl", "-n", "vm.loadavg").split()[1]
class Engine:
    def __init__(self, u):
        self.p = subprocess.Popen([ENGINE, "--udid", u], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1); json.loads(self.p.stdout.readline())
    def call(self, req):
        t = time.time(); self.p.stdin.write(json.dumps(req) + "\n"); self.p.stdin.flush(); a = json.loads(self.p.stdout.readline()); return (time.time() - t) * 1000, a
def find(tree, label):
    stack = list(tree) if isinstance(tree, list) else [tree]
    while stack:
        n = stack.pop()
        if n.get("AXLabel") == label and n.get("frame"): f = n["frame"]; return f["x"] + f["width"] / 2, f["y"] + f["height"] / 2
        stack.extend(n.get("children", []))
phones = []
for i in range(N):
    u = sh("xcrun", "simctl", "clone", GOLD, f"t12-{i}"); subprocess.run(["xcrun", "simctl", "boot", u]); subprocess.run(["xcrun", "simctl", "bootstatus", u, "-b"], capture_output=True)
    e = Engine(u); t0 = time.time()
    while time.time() - t0 < 120:
        _, a = e.call({"op": "describe"})
        if a.get("ok") and len(json.dumps(a.get("tree"))) > 2000: break
        time.sleep(1)
    phones.append((u, e)); print(f"phone {i+1} readable, load {load()}", flush=True)
t0 = time.time()
while time.time() - t0 < 420 and float(load()) > 4 + N: time.sleep(10)
print(f"settled, load {load()}", flush=True)
samples = []; wrong = []; lock = threading.Lock(); stop = threading.Event()
def drive(u, e):
    while not stop.is_set():
        e.call({"op": "home"})
        _, d = e.call({"op": "describe"}); xy = find(d.get("tree", []), "Settings")
        if not xy: continue
        ms, a = e.call({"op": "tap_settle_describe", "x": xy[0], "y": xy[1]})
        good = a.get("ok") and (find(a.get("tree", []), "General") or find(a.get("tree", []), "About"))
        if not good:
            roots = a.get("tree") or []
            with lock: wrong.append(f"{(roots[0].get('AXLabel') if roots else None)!r} ({len(json.dumps(roots))} bytes, settle {a.get('settle_ms')} ms, {a.get('updates')} updates, reads {a.get('reads')}, {a.get('error', '')[:40]})")
        with lock: samples.append((time.time(), ms if good else None))
        time.sleep(1.0)  # an agent's think time
def phase(name, seconds, build=None):
    start = time.time(); build_s = None
    if build:
        subprocess.run(["touch", os.path.join(PROJ, "IceCubesApp/App/Main/IceCubesApp.swift")])
        b0 = time.time(); r = subprocess.run(build, cwd=PROJ, capture_output=True, text=True); build_s = time.time() - b0
        ok = "BUILD SUCCEEDED" in r.stdout or "SwiftCompile" in r.stdout
    else:
        time.sleep(seconds)
    with lock: got = [ms for t, ms in samples if t >= start]
    v = sorted(x for x in got if x is not None); bad = len(got) - len(v)
    if v: print(f"{name:34} acts {len(v)} correct, {bad} wrong screen: p50 {statistics.median(v):.0f} ms, p90 {v[int(len(v)*0.9)-1]:.0f} ms, max {v[-1]:.0f} ms; load {load()}" + (f"; build {build_s:.0f} s" if build_s else ""), flush=True)
threads = [threading.Thread(target=drive, args=pe, daemon=True) for pe in phones]; [t.start() for t in threads]
base = ["xcodebuild", "-project", "IceCubesApp.xcodeproj", "-scheme", "IceCubesApp", "-destination", "generic/platform=iOS Simulator", "-derivedDataPath", os.path.expanduser("~/t12-dd"), "CODE_SIGNING_ALLOWED=NO", "build"]
phase("phones alone", 45)
phase("incremental build, normal priority", 0, base)
phase("phones alone again", 30)
phase("incremental build, background (taskpolicy -b)", 0, ["taskpolicy", "-b"] + base)
phase("incremental build, utility (taskpolicy -c utility)", 0, ["taskpolicy", "-c", "utility"] + base)
stop.set(); time.sleep(3)
for u, e in phones:
    e.p.stdin.close(); e.p.wait(); subprocess.run(["xcrun", "simctl", "shutdown", u], capture_output=True); subprocess.run(["xcrun", "simctl", "delete", u], capture_output=True)
print("wrong screens:", wrong[:8], flush=True)
print("done", flush=True)
