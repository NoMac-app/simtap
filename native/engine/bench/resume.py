# What a resumed app's tree looks like right after an act and over the next seconds.
import json, subprocess, sys, time, os
p = subprocess.Popen([os.path.expanduser("~/sue/sue-engine"), "--udid", sys.argv[1]], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1); json.loads(p.stdout.readline())
def call(req): p.stdin.write(json.dumps(req) + "\n"); p.stdin.flush(); return json.loads(p.stdout.readline())
def find(tree, label):
    stack = list(tree) if isinstance(tree, list) else [tree]
    while stack:
        n = stack.pop()
        if n.get("AXLabel") == label and n.get("frame"): f = n["frame"]; return f["x"] + f["width"] / 2, f["y"] + f["height"] / 2
        stack.extend(n.get("children", []))
def show(tree): return [(n.get("type"), n.get("AXLabel"), n.get("pid"), len(n.get("children", []))) for n in (tree or [])][:2]
def label_at(pt):
    if not pt.get("ok"): return pt.get("error", "")[:60]
    e = pt.get("element"); e = e[0] if isinstance(e, list) and e else e
    return (e or {}).get("AXLabel")
call({"op": "describe"})
for i in range(2):
    call({"op": "home"}); d = call({"op": "describe"}); xy = find(d.get("tree", []), "Settings")
    a = call({"op": "tap_settle_describe", "x": xy[0], "y": xy[1]})
    print(f"act {i}: reads {a.get('reads')} tree {show(a.get('tree'))}", flush=True)
    for t in (0.5, 2, 5):
        time.sleep(t); d = call({"op": "describe"}); pt = call({"op": "point", "x": 200, "y": 300})
        print(f"   +{t}s describe {show(d.get('tree'))} | point {label_at(pt)}", flush=True)
p.stdin.close(); p.wait()
