# Drives one engine process: sends each request, times it end to end, prints a table.
import json, subprocess, sys, time
udid = sys.argv[1]
p = subprocess.Popen([sys.argv[2], "--udid", udid], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1)
t = time.time(); ready = json.loads(p.stdout.readline()); print("start", round((time.time()-t)*1000), "ms", ready)
def call(req):
    t = time.time(); p.stdin.write(json.dumps(req) + "\n"); p.stdin.flush(); a = json.loads(p.stdout.readline()); return round((time.time()-t)*1000), a
plan = [("describe", {"op": "describe"}), ("point", {"op": "point", "x": 200, "y": 400}), ("tap", {"op": "tap", "x": 200, "y": 650}),
        ("swipe", {"op": "swipe", "x1": 200, "y1": 600, "x2": 200, "y2": 300, "duration": 0.2}), ("type", {"op": "type", "text": "hello"}),
        ("screenshot jpeg 402x874", {"op": "screenshot", "width": 402, "height": 874, "quality": 0.7}), ("screenshot png", {"op": "screenshot", "format": "png"}), ("home", {"op": "home"})]
for name, req in plan:
    times = []; last = None
    for i in range(5):
        ms, last = call(dict(req, id=i)); times.append(ms)
    extra = {k: v for k, v in last.items() if k in ("ok", "error", "bytes", "capture_ms")}
    if name == "describe" and last.get("ok"): extra["elements"] = len(json.dumps(last["tree"]))
    print(f"{name:26} {times} ms  {extra}")
p.stdin.close(); p.wait()
