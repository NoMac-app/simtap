# The engine's web scan end to end: WebTest read, read again (cached), the form used through acts (tap the field,
# type, tap Continue, the page's answer in the act's own tree), native screens for the cost, Safari. Pool user nmsim2.
# Usage (as root): webeng.py <udid>
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
def texts(n): return [str(n.get(k)) for k in ("AXLabel", "AXValue") if n.get(k) not in (None, "", " ")]
def center(n):
    f = n.get("frame") or {}
    return f.get("x", 0) + f.get("width", 0) / 2, f.get("y", 0) + f.get("height", 0) / 2
def find(tree, role, text):
    for n in nodes(tree):
        if n.get("role") == role and any(text in t for t in texts(n)): return n
def report(label, a, targets, took):
    tree = a.get("tree"); found = [t for t in targets if any(t in s for n in nodes(tree) for s in texts(n))]
    print(f"  {label}: {took} ms (accessibility {a.get('serialize_ms')}), scan {a.get('web_scan')}; found {len(found)}/{len(targets)}"
          + (f" missing {[t for t in targets if t not in found]}" if len(found) < len(targets) else ""), flush=True)
    return tree
def read(label, targets, **opts):
    t = time.time(); a = call({"op": "describe", **opts}); return report(label, a, targets, int((time.time() - t) * 1000))
for _ in range(3):
    if call({"op": "describe", "web": False}).get("tree"): break
WEB = ["Native header", "Sign in", "Welcome back", "Email", "Password", "Remember me", "Continue", "Forgot password?", "Item 1"]
print("== WebTest", flush=True)
subprocess.run(AS + ["xcrun", "simctl", "launch", udid, "app.nomac.webtest"], capture_output=True); time.sleep(4)
tree = read("first read", WEB)
json.dump(tree, open("/tmp/webtest-tree.json", "w"))
read("again, the screen unchanged", WEB)
read("web: false", WEB, web=False)
field = find(tree, "AXTextField", "Email")
if field:
    t = time.time(); a = call({"op": "tap_settle_describe", "x": center(field)[0], "y": center(field)[1]})
    print(f"  tap the Email field: {int((time.time() - t) * 1000)} ms (settle {a.get('settle_ms')} ms, settled {a.get('settled')}, read {a.get('read_ms')} ms), scan {a.get('web_scan')}, keyboard up: {any('Return' in s or 'return' in s for n in nodes(a.get('tree')) for s in texts(n))}", flush=True)
    t = time.time(); call({"op": "type", "text": "agent@nomac.app"}); print(f"  type the address: {int((time.time() - t) * 1000)} ms", flush=True)
    time.sleep(0.5)
    tree = read("read after typing", ["agent@nomac.app"])
    json.dump(tree, open("/tmp/webtest-typed-tree.json", "w"))
    button = find(tree, "AXButton", "Continue")
    if button:
        t = time.time(); a = call({"op": "tap_settle_describe", "x": center(button)[0], "y": center(button)[1]})
        ok = any("Signed in as agent@nomac.app" in s for n in nodes(a.get("tree")) for s in texts(n))
        print(f"  tap Continue: {int((time.time() - t) * 1000)} ms (settle {a.get('settle_ms')} ms), the page's answer in the act's tree: {ok}, scan {a.get('web_scan')}", flush=True)
    else: print("  no Continue button found after typing (the keyboard may cover it)", flush=True)
else: print("  no Email field found", flush=True)
print("== native screens", flush=True)
call({"op": "home"}); time.sleep(1)
read("home screen", ["Settings"]); read("home screen again", ["Settings"])
subprocess.run(AS + ["xcrun", "simctl", "launch", udid, "com.apple.Preferences"], capture_output=True); time.sleep(3)
read("Settings", ["General"]); read("Settings again", ["General"]); read("Settings, web: false", ["General"], web=False)
print("== Safari, example.com", flush=True)
subprocess.run(AS + ["xcrun", "simctl", "openurl", udid, "https://example.com"]); time.sleep(8)
for i in range(3): read(f"read {i + 1}", ["Example Domain", "This domain is for use", "Learn more"])
eng.stdin.close(); eng.wait(timeout=10)
