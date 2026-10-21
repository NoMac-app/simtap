# T7: N phones on one host. Clone the settled golden phone N times, boot one at a time (no boot storm),
# wait until each is readable, let them settle, then drive all N at once through one engine each:
# home, tap Settings, read until Settings shows, read again, home. Latencies, memory and swap.
import json, subprocess, sys, time, os, threading, statistics
N = int(sys.argv[1]); ROUNDS = int(sys.argv[2]) if len(sys.argv) > 2 else 8
ENGINE = os.path.expanduser("~/sue/sue-engine")
def sh(*a): return subprocess.run(a, capture_output=True, text=True).stdout.strip()
def mem():
    free = sh("memory_pressure", "-Q").split(":")[-1].strip()
    swap = sh("sysctl", "-n", "vm.swapusage").split("used = ")[1].split()[0]
    return f"free {free}, swap {swap}, load {sh('sysctl','-n','vm.loadavg').split()[1]}"
gold = sys.argv[3] if len(sys.argv) > 3 else [l.split("(")[1].split(")")[0] for l in sh("xcrun", "simctl", "list", "devices").splitlines() if "bench-a" in l][0]
subprocess.run(["xcrun", "simctl", "shutdown", gold], capture_output=True)
print(f"before: {mem()}", flush=True)
class Engine:
    def __init__(self, udid):
        self.p = subprocess.Popen([ENGINE, "--udid", udid], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1)
        self.ready = json.loads(self.p.stdout.readline())
    def call(self, req):
        t = time.time(); self.p.stdin.write(json.dumps(req) + "\n"); self.p.stdin.flush(); a = json.loads(self.p.stdout.readline()); return (time.time() - t) * 1000, a
    def close(self): self.p.stdin.close(); self.p.wait()
phones = []
for i in range(N):
    t0 = time.time()
    u = sh("xcrun", "simctl", "clone", gold, f"t7-{i}")
    subprocess.run(["xcrun", "simctl", "boot", u]); subprocess.run(["xcrun", "simctl", "bootstatus", u, "-b"], capture_output=True)
    e = Engine(u)
    while time.time() - t0 < 240:
        _, a = e.call({"op": "describe"})
        if a.get("ok") and a.get("tree"): break
        time.sleep(0.5)
    phones.append((u, e))
    print(f"phone {i+1}: readable {time.time()-t0:.0f} s after clone; {mem()}", flush=True)
ts = time.time()
while time.time() - ts < 480 and float(sh("sysctl", "-n", "vm.loadavg").split()[1]) > 4 + N: time.sleep(10)
print(f"all {N} settled after {time.time()-ts:.0f} s more: {mem()}", flush=True)
def label_frame(tree, label):
    stack = list(tree) if isinstance(tree, list) else [tree]
    while stack:
        n = stack.pop()
        if n.get("AXLabel") == label: f = n["frame"]; return f["x"] + f["width"] / 2, f["y"] + f["height"] / 2
        stack.extend(n.get("children", []))
results = {"act: open Settings (tap, settle, read)": [], "read whole screen": [], "screenshot": [], "point read": []}
lock = threading.Lock(); failures = []
def drive(u, e):
    e.call({"op": "describe"})  # this engine's one-time bootstrap
    for r in range(ROUNDS):
        e.call({"op": "home"}); e.call({"op": "settle", "first_change_ms": 600})
        _, d = e.call({"op": "describe"}); xy = label_frame(d.get("tree", []), "Settings")
        if not xy: failures.append(f"{u}: no Settings icon ({d.get('error')})"); continue
        ms, a = e.call({"op": "tap_settle_describe", "x": xy[0], "y": xy[1]})
        if not a.get("ok"): failures.append(f"{u}: act failed ({a.get('error')})"); continue
        with lock: results["act: open Settings (tap, settle, read)"].append(ms)
        ms, _ = e.call({"op": "describe"})
        with lock: results["read whole screen"].append(ms)
        ms, _ = e.call({"op": "point", "x": 200, "y": 300})
        with lock: results["point read"].append(ms)
        ms, _ = e.call({"op": "screenshot", "width": 402, "height": 874})
        with lock: results["screenshot"].append(ms)
threads = [threading.Thread(target=drive, args=pe) for pe in phones]
t0 = time.time(); [t.start() for t in threads]; [t.join() for t in threads]
print(f"driven at once, {ROUNDS} rounds each, {time.time()-t0:.0f} s; {mem()}", flush=True)
for k, v in results.items():
    if v: v = sorted(v); print(f"  {k:32} p50 {statistics.median(v):.0f} ms, p90 {v[int(len(v)*0.9)-1]:.0f} ms, max {v[-1]:.0f} ms ({len(v)})", flush=True)
if failures: print("  failures:", failures[:5], flush=True)
for u, e in phones:
    e.close(); subprocess.run(["xcrun", "simctl", "shutdown", u], capture_output=True); subprocess.run(["xcrun", "simctl", "delete", u], capture_output=True)
print(f"after cleanup: {mem()}", flush=True)
