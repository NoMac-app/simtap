import json, subprocess, sys, time, os
p = subprocess.Popen([os.path.expanduser("~/sue/sue-engine"), "--udid", sys.argv[1]], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1); json.loads(p.stdout.readline())
def call(req): p.stdin.write(json.dumps(req) + "\n"); p.stdin.flush(); return json.loads(p.stdout.readline())
def tops(tree): return [(n.get("type"), n.get("AXLabel")) for n in (tree if isinstance(tree, list) else [tree])][:3]
def labels(tree):
    out = []; stack = list(tree) if isinstance(tree, list) else [tree]
    while stack:
        n = stack.pop(); out.append(n.get("AXLabel")); stack.extend(n.get("children", []))
    return out
call({"op": "describe"})
for i in range(4):
    h = call({"op": "home"}); s = call({"op": "settle", "first_change_ms": 600})
    d = call({"op": "describe"}); L = labels(d.get("tree", []))
    print(f"home {i}: settle {s.get('waited_ms')} ms, {s.get('updates')} updates; top {tops(d.get('tree', []))}; Settings on screen: {'Settings' in L}; {len(L)} elements", flush=True)
    if "Settings" in L:
        st = call({"op": "describe"})
        stack = list(st["tree"]); xy = None
        while stack:
            n = stack.pop()
            if n.get("AXLabel") == "Settings" and n.get("frame"): f = n["frame"]; xy = (f["x"] + f["width"]/2, f["y"] + f["height"]/2)
            stack.extend(n.get("children", []))
        a = call({"op": "tap_settle_describe", "x": xy[0], "y": xy[1]}); print(f"   opened: top {tops(a.get('tree', []))}", flush=True)
p.stdin.close(); p.wait()
