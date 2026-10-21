# Does a point read on a web page's background, serialized with its children, return the whole page? WebTest and
# Safari (github.com/login), one engine as the pool user nmsim2. Usage (as root): webpoint.py <udid>
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
def probe(name, targets, points):
    for (x, y) in points:
        t = time.time(); a = call({"op": "point", "x": x, "y": y, "nested": True}); took = int((time.time() - t) * 1000)
        el = a.get("element"); all_nodes = list(nodes(el)); root = all_nodes[0] if all_nodes else {}
        found = [w for w in targets if any(w in s for n in all_nodes for s in texts(n))]
        print(f"  {name} point {x},{y}: {took} ms, hit {root.get('role')} {texts(root)[:1]} {root.get('frame')}, {len(all_nodes)} nodes under it, found {len(found)}/{len(targets)}", flush=True)
        if len(found) >= len(targets) // 2:
            for n in all_nodes[:40]:
                if texts(n) or n.get("role") in ("AXTextField", "AXButton", "AXLink", "AXCheckBox"): print(f"     {n.get('role')} {texts(n)} {n.get('frame')}", flush=True)
            return
for _ in range(3):
    if call({"op": "describe"}).get("tree"): break
WEB = ["Sign in", "Welcome back", "Email", "Password", "Remember me", "Continue", "Forgot password?", "Item 1"]
subprocess.run(AS + ["xcrun", "simctl", "launch", udid, "app.nomac.webtest"], capture_output=True); time.sleep(4)
call({"op": "describe"})
print("== WebTest (WKWebView below a native header)", flush=True)
probe("WebTest", WEB, [(4, 400), (395, 500), (200, 860), (300, 160), (200, 300)])
GH = ["Sign in to GitHub", "Username or email address", "Password", "Sign in", "Forgot password?", "Create an account"]
subprocess.run(AS + ["xcrun", "simctl", "openurl", udid, "https://github.com/login"]); time.sleep(8)
print("== Safari, github.com/login", flush=True)
probe("Safari", GH, [(4, 400), (395, 500), (200, 700), (30, 300), (200, 250)])
eng.stdin.close(); eng.wait(timeout=10)
