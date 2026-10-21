# One-call acts: tap, wait until the screen stops changing (framebuffer updates), read the new screen.
import json, subprocess, sys, time, os
p = subprocess.Popen([os.path.expanduser("~/sue/sue-engine"), "--udid", sys.argv[1]], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1)
json.loads(p.stdout.readline())
def call(req):
    t = time.time(); p.stdin.write(json.dumps(req) + "\n"); p.stdin.flush(); a = json.loads(p.stdout.readline()); return (time.time()-t)*1000, a
def nodes(tree):
    stack = list(tree) if isinstance(tree, list) else [tree]
    while stack:
        n = stack.pop(); yield n; stack.extend(n.get("children", []))
def find(tree, label):
    for n in nodes(tree):
        if n.get("AXLabel") == label and n.get("frame"): f = n["frame"]; return f["x"] + f["width"] / 2, f["y"] + f["height"] / 2
call({"op": "describe"})  # the one-time bootstrap
for r in range(4):
    call({"op": "home"}); call({"op": "settle"})
    _, d = call({"op": "describe"}); xy = find(d.get("tree", []), "Settings")
    if not xy: print("no Settings icon", d.get("error")); break
    t1, a = call({"op": "tap_settle_describe", "x": xy[0], "y": xy[1]})
    g = find(a.get("tree", []), "General")
    t2, b = call({"op": "tap_settle_describe", "x": g[0], "y": g[1]}) if g else (0, {})
    about = bool(find(b.get("tree", []), "About")) if g else False
    print(f"round {r}: open Settings {t1:.0f} ms (screen moving {a.get('settle_ms')} ms, {a.get('updates')} frames; read {a.get('read_ms')} ms), shows General: {bool(g)} | open General {t2:.0f} ms (moving {b.get('settle_ms')} ms; read {b.get('read_ms')} ms), shows About: {about}", flush=True)
p.stdin.close(); p.wait()
