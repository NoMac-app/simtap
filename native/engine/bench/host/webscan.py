# Prototype of the engine's web scan, through point reads: find the web view's empty scroll area in the main tree,
# sweep five columns down it (jumping past each element found), and when a point hits a large container of the page,
# try it with its children. WebTest and Safari on example.com. Usage (as root): webscan.py <udid>
import json, os, subprocess, sys, time
udid = sys.argv[1]
AS = ["launchctl", "asuser", "508", "sudo", "-u", "nmsim2", "-H"]
eng = subprocess.Popen(AS + [os.environ.get("ENGINE", "/usr/local/nomac-test/engine/simulator-use-engine"), "--udid", udid], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1)
eng.stdout.readline()
def call(req):
    eng.stdin.write(json.dumps(req) + "\n"); eng.stdin.flush(); return json.loads(eng.stdout.readline())
def nodes(t):
    if isinstance(t, dict): t = [t]
    for n in t or []:
        yield n; yield from nodes(n.get("children"))
def texts(n): return [str(n.get(k)) for k in ("AXLabel", "AXValue", "title") if n.get(k) not in (None, "", " ")]
def frame(n):
    f = n.get("frame") or {}
    return f.get("x", 0), f.get("y", 0), f.get("width", 0), f.get("height", 0)
def hollow_areas(tree):
    out = []
    for n in nodes(tree):
        if n.get("role") in ("AXScrollArea", "AXWebArea"):
            x, y, w, h = frame(n)
            inner = [m for m in nodes(n.get("children")) if m.get("role") != "AXSlider" and texts(m)]
            if w * h >= 402 * 874 * 0.15 and not inner and not any(abs(o[1] - y) < 1 and abs(o[3] - h) < 1 for o in out): out.append((x, y, w, h))
    return out
def scan(region, app_pid, tries_nested=True):
    rx, ry, rw, rh = region
    found, keys, hits, t0, nested_tried = [], set(), 0, time.time(), 0
    for fx in (0.1, 0.3, 0.5, 0.7, 0.9):
        x = rx + rw * fx; y = ry + 4
        while y < ry + rh - 2 and hits < 400:
            a = call({"op": "point", "x": x, "y": y}); hits += 1
            e = a.get("element") or {}
            ex, ey, ew, eh = frame(e)
            big = ew * eh >= rw * rh * 0.5
            if not e or big or ew * eh == 0:
                if big and tries_nested and nested_tried < 3:
                    nested_tried += 1
                    t1 = time.time(); b = call({"op": "point", "x": x, "y": y, "nested": True}); sub = list(nodes(b.get("element")))
                    print(f"     a big hit at {int(x)},{int(y)} ({e.get('role')} {tuple(int(v) for v in frame(e))}, pid {e.get('pid')} vs app {app_pid}) with its children: {len(sub)} nodes, {sum(1 for s in sub if texts(s))} with text, {int((time.time() - t1) * 1000)} ms; roles {sorted(set(s.get('role') for s in sub))[:8]}", flush=True)
                y += 12; continue
            key = (e.get("role"), tuple(texts(e)), round(ex), round(ey), round(ew), round(eh))
            if key not in keys: keys.add(key); found.append(e)
            y = max(y + 4, ey + eh + 1)
    return found, hits, int((time.time() - t0) * 1000)
def run(name, targets):
    a = call({"op": "describe"}); tree = a.get("tree") or []
    app_pid = tree[0].get("pid") if tree else None
    areas = hollow_areas(tree)
    print(f"  {name}: main read {a.get('ms')} ms, empty scroll areas {[(int(x), int(y), int(w), int(h)) for x, y, w, h in areas]}", flush=True)
    for region in areas[:1]:
        found, hits, took = scan(region, app_pid)
        got = [t for t in targets if any(t in s for e in found for s in texts(e))]
        print(f"  {name}: scan {took} ms, {hits} point reads, {len(found)} elements, found {len(got)}/{len(targets)} {('missing ' + str([t for t in targets if t not in got])) if len(got) < len(targets) else ''}", flush=True)
        print(f"     pids of the elements found: {sorted(set(e.get('pid') for e in found))}, app {app_pid}", flush=True)
    for e in sorted(found, key=lambda e: (frame(e)[1], frame(e)[0]))[:30]:
            print(f"     {e.get('role')} {texts(e)} {tuple(int(v) for v in frame(e))}", flush=True)
for _ in range(3):
    if call({"op": "describe"}).get("tree"): break
subprocess.run(AS + ["xcrun", "simctl", "launch", udid, "app.nomac.webtest"], capture_output=True); time.sleep(4)
run("WebTest", ["Sign in", "Welcome back", "Email", "Password", "Remember me", "Continue", "Forgot password?", "Item 1", "Item 9"])
subprocess.run(AS + ["xcrun", "simctl", "openurl", udid, "https://example.com"]); time.sleep(8)
call({"op": "describe"})
run("Safari, example.com", ["Example Domain", "This domain is for use", "Learn more"])
eng.stdin.close(); eng.wait(timeout=10)
