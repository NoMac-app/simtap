# The web scan on the screens agents meet, through one engine as the pool user nmsim2: WebTest's form (a checkbox,
# a link), an empty native scroll area and a map (the scan must stop at once), a long page (scroll, reread, the
# bottom button), and real pages in the app's own WKWebView. Each tree is saved for simulator-use's renderer.
# Usage (as root): webpolish.py <udid>
import json, os, subprocess, sys, time
udid = sys.argv[1]
AS = ["launchctl", "asuser", "508", "sudo", "-u", "nmsim2", "-H"]
eng = subprocess.Popen(AS + ["/usr/local/nomac-test/engine/simulator-use-engine.next", "--udid", udid], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1)
eng.stdout.readline()
def call(req):
    eng.stdin.write(json.dumps(req) + "\n"); eng.stdin.flush(); return json.loads(eng.stdout.readline())
def nodes(t):
    if isinstance(t, dict): t = [t]
    for n in t or []:
        yield n; yield from nodes(n.get("children"))
def texts(n): return [str(n.get(k)) for k in ("AXLabel", "AXValue") if n.get(k) not in (None, "", " ")]
def center(n):
    f = n.get("frame") or {}
    return f.get("x", 0) + f.get("width", 0) / 2, f.get("y", 0) + f.get("height", 0) / 2
def find(tree, text, role=None):
    for n in nodes(tree):
        if (role is None or n.get("role") == role) and any(text in t for t in texts(n)): return n
def read(name, save=None):
    t = time.time(); a = call({"op": "describe"}); took = int((time.time() - t) * 1000)
    w = a.get("web_scan") or {}
    found = [n for n in nodes(a.get("tree")) if n.get("found_by")]
    roles = {}
    for n in found: roles[n.get("role")] = roles.get(n.get("role"), 0) + 1
    print(f"  {name}: {took} ms, scan {w.get('ms')} ms, {w.get('reads')} reads, pages {w.get('pages')}, cached {w.get('cached')}, complete {w.get('complete')}; {len(found)} found {roles}", flush=True)
    if save: json.dump(a.get("tree"), open(f"/tmp/wp-{save}.json", "w"))
    return a.get("tree")
def launch(*args):
    subprocess.run(AS + ["xcrun", "simctl", "terminate", udid, "app.nomac.webtest"], capture_output=True)
    subprocess.run(AS + ["xcrun", "simctl", "launch", udid, "app.nomac.webtest", *args], capture_output=True)
for _ in range(3):
    if call({"op": "describe", "web": False}).get("tree"): break
print("== the form: a checkbox and a link", flush=True)
launch(); time.sleep(4)
tree = read("read", save="form")
box = find(tree, "Remember me")
if box:
    a = call({"op": "tap_settle_describe", "x": center(box)[0], "y": center(box)[1]})
    cb = [n for n in nodes(a.get("tree")) if n.get("role") == "AXCheckBox"]
    print(f"  tap 'Remember me': checkboxes in the act's tree: {[(texts(n), n.get('AXValue')) for n in cb]}", flush=True)
link = find(tree, "Forgot password?", "AXLink")
if link:
    a = call({"op": "tap_settle_describe", "x": center(link)[0], "y": center(link)[1]})
    print(f"  tap the link: scan {a.get('web_scan')}", flush=True)
print("== an empty native scroll area, and a map", flush=True)
launch("-mode", "empty"); time.sleep(3)
read("empty area, read 1"); read("empty area, read 2")
launch("-mode", "map"); time.sleep(5)
read("map, read 1", save="map"); read("map, read 2")
print("== a long page: scroll down and reread, the bottom button", flush=True)
launch("-mode", "long"); time.sleep(4)
read("top of the long page", save="long-top")
for i in range(8):
    call({"op": "swipe", "x1": 201, "y1": 750, "x2": 201, "y2": 250, "duration": 0.3}); call({"op": "settle", "first_change_ms": 300})
tree = read("after scrolling to the bottom", save="long-bottom")
b = find(tree, "Bottom button", "AXButton")
if b:
    a = call({"op": "tap_settle_describe", "x": center(b)[0], "y": center(b)[1]})
    print(f"  tap 'Bottom button': pressed {any('Bottom pressed' in t for n in nodes(a.get('tree')) for t in texts(n))}", flush=True)
else: print("  'Bottom button' not found after scrolling", flush=True)
print("== real pages in the app's WKWebView", flush=True)
for name, url, wait in (("github-login", "https://github.com/login", 6), ("httpbin-form", "https://httpbin.org/forms/post", 5),
                        ("wikipedia", "https://en.m.wikipedia.org/wiki/IOS", 6), ("hackernews", "https://news.ycombinator.com", 5)):
    launch("-mode", "url", "-url", url); time.sleep(wait)
    read(f"{name}, read 1", save=name); read(f"{name}, read 2")
eng.stdin.close(); eng.wait(timeout=10)
