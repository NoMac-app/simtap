# One engine on one phone for an hour (run as the Mac's own user): a read every 10 s, every minute an act (open
# Settings, read, home), the engine's memory each minute; a summary line every 10 minutes. Usage: longrun.py <udid> <minutes>
import json, re, subprocess, sys, time
udid, minutes = sys.argv[1], float(sys.argv[2])
eng = subprocess.Popen(["/usr/local/nomac-test/engine/simulator-use-engine", "--udid", udid], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1)
eng.stdout.readline()
def call(req):
    eng.stdin.write(json.dumps(req) + "\n"); eng.stdin.flush()
    return json.loads(eng.stdout.readline())
def nodes(tree):
    for n in tree or []:
        yield n; yield from nodes(n.get("children"))
def frame_of(a, label):
    for n in nodes(a.get("tree")):
        if n.get("AXLabel") == label:
            f = n.get("frame") or {}
            if not f and isinstance(n.get("AXFrame"), str):
                x, y, w, h = map(float, re.findall(r"[-\d.]+", n["AXFrame"])[:4]); f = {"x": x, "y": y, "width": w, "height": h}
            return f
def rss_mb(): return int(subprocess.run(["ps", "-o", "rss=", "-p", str(eng.pid)], capture_output=True, text=True).stdout.strip() or 0) // 1024
def pct(xs, q): xs = sorted(xs); return xs[min(len(xs) - 1, int(len(xs) * q))] if xs else -1
t0 = time.time(); reads, acts, errors, window, next_act, missed = [], [], 0, 0, time.time() + 60, 0
call({"op": "home"})
while time.time() - t0 < minutes * 60:
    a = call({"op": "describe"})
    if a.get("tree"): reads.append(a["ms"])
    else: errors += 1
    if time.time() >= next_act:
        next_act += 60
        f = frame_of(a, "Settings")
        if f:
            t = time.time(); b = call({"op": "tap_settle_describe", "x": f["x"] + f["width"] / 2, "y": f["y"] + f["height"] / 2})
            if b.get("tree") and "General" in json.dumps(b["tree"]): acts.append(int((time.time() - t) * 1000))
            else: missed += 1
            call({"op": "home"})
        else: missed += 1
    m = int((time.time() - t0) // 600)
    if m > window:
        window = m
        print(f"{m * 10:3d} min: read p50 {pct(reads, .5)} ms p90 {pct(reads, .9)} ms (n {len(reads)}), act p50 {pct(acts, .5)} ms p90 {pct(acts, .9)} ms (n {len(acts)}), errors {errors}, acts missed {missed}, engine {rss_mb()} MB", flush=True)
        reads, acts = [], []
    time.sleep(10)
print(f"end: read p50 {pct(reads, .5)} ms, act p50 {pct(acts, .5)} ms, errors {errors}, engine {rss_mb()} MB", flush=True)
eng.stdin.close(); eng.wait(timeout=10)
