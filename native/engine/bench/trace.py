import json, subprocess, sys, time, os
p = subprocess.Popen([os.path.expanduser("~/sue/sue-engine"), "--udid", sys.argv[1]], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1); json.loads(p.stdout.readline())
def call(req): p.stdin.write(json.dumps(req) + "\n"); p.stdin.flush(); return json.loads(p.stdout.readline())
def find(tree, label):
    stack = list(tree) if isinstance(tree, list) else [tree]
    while stack:
        n = stack.pop()
        if n.get("AXLabel") == label and n.get("frame"): f = n["frame"]; return f["x"] + f["width"] / 2, f["y"] + f["height"] / 2
        stack.extend(n.get("children", []))
def runs(ch):
    if not ch: return "none"
    out = []; a = b = ch[0]
    for c in ch[1:]:
        if c - b > 60: out.append(f"{a}-{b}"); a = c
        b = c
    out.append(f"{a}-{b}"); return ", ".join(out)
subprocess.run(["xcrun", "simctl", "terminate", sys.argv[1], "com.apple.Preferences"]); subprocess.run(["xcrun", "simctl", "launch", sys.argv[1], "com.apple.Preferences"], capture_output=True); time.sleep(3)
call({"op": "describe"})
for i in range(3):
    d = call({"op": "describe"}); g = find(d.get("tree", []), "General")
    if not g: print("no General row"); break
    a = call({"op": "tap_trace", "x": g[0], "y": g[1], "window_ms": 3000})
    print(f"tap General: {len(a['changes'])} changes, runs (ms after tap): {runs(a['changes'])}", flush=True)
    time.sleep(0.5); b = call({"op": "swipe", "x1": 5, "y1": 400, "x2": 300, "y2": 400, "duration": 0.3}); time.sleep(1.5)
p.stdin.close(); p.wait()
