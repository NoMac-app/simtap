# Web content through the engine's describe with FBSimulatorControl's remote-content phase: an app's WKWebView
# (WebTest), Safari on a real sign-in page, and a native screen (Settings) for the overhead. One engine, the pool
# user nmsim2. Usage (as root): webexp.py <udid>
import json, os, subprocess, sys, time
udid = sys.argv[1]
AS = ["launchctl", "asuser", "508", "sudo", "-u", "nmsim2", "-H"]
eng = subprocess.Popen(AS + [os.environ.get("ENGINE", "/usr/local/nomac-test/engine/simulator-use-engine"), "--udid", udid], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1)
eng.stdout.readline()
KEYS = ["label", "frame", "value", "uniqueID", "type", "title", "enabled", "role", "pid", "isRemote", "placeholder", "focused"]
def call(req):
    eng.stdin.write(json.dumps(req) + "\n"); eng.stdin.flush(); return json.loads(eng.stdout.readline())
def nodes(t):
    for n in t or []:
        yield n; yield from nodes(n.get("children"))
def texts(n): return [str(n.get(k)) for k in ("AXLabel", "AXValue", "title", "placeholder") if n.get(k) not in (None, "", " ")]
def read(label, targets, remote=None, profile=False):
    req = {"op": "describe", "keys": KEYS, "profile": profile}
    if remote is not None: req["remote"] = remote
    t = time.time(); a = call(req); took = int((time.time() - t) * 1000)
    if a.get("error"): print(f"  {label}: error {a['error']}", flush=True); return
    all_nodes = list(nodes(a.get("tree"))); remote_nodes = [n for n in all_nodes if n.get("is_remote") == "point_grid" or n.get("isRemote") == "point_grid"]
    found = [x for x in targets if any(x in t for n in all_nodes for t in texts(n))]
    prof = a.get("profile") or {}
    print(f"  {label}: {took} ms {a.get('serialize_ms')}, {len(all_nodes)} elements ({len(remote_nodes)} from the grid), coverage {a.get('frame_coverage')}, grid added {a.get('remote_coverage')}"
          + (f", xpc {prof.get('xpcCallCount')} calls {round(prof.get('totalXPCDuration', 0) * 1000)} ms" if prof else "")
          + f"; found {len(found)}/{len(targets)}: {[x for x in targets if x not in found] and 'missing ' + str([x for x in targets if x not in found]) or 'all'}", flush=True)
    return remote_nodes
for _ in range(3):
    if call({"op": "describe"}).get("tree"): break
WEB = ["Native header", "Native button", "Sign in", "Welcome back", "Email", "you@example.com", "Password", "Remember me", "Continue", "Forgot password?", "Item 1"]
print("== WebTest: native header and button, then a WKWebView sign-in page", flush=True)
subprocess.run(AS + ["xcrun", "simctl", "launch", udid, "app.nomac.webtest"], capture_output=True); time.sleep(4)
read("first read, no remote", WEB)
read("again, no remote", WEB)
for step in (50, 25, 16):
    r = read(f"remote, {step} pt grid", WEB, remote={"step": step}, profile=(step == 25))
r = read("remote, 16 pt grid again", WEB, remote={"step": 16})
for n in (r or [])[:14]:
    print(f"     grid: {n.get('type')} {texts(n)} {n.get('frame')}", flush=True)
GH = ["Sign in to GitHub", "Username or email address", "Password", "Sign in", "Forgot password?", "Create an account"]
print("== Safari on github.com/login", flush=True)
subprocess.run(AS + ["xcrun", "simctl", "openurl", udid, "https://github.com/login"]); time.sleep(8)
read("first read, remote 25 pt", GH, remote={"step": 25})
read("again, remote 25 pt", GH, remote={"step": 25})
read("again, no remote", GH)
read("remote, 16 pt grid", GH, remote={"step": 16})
print("== Settings (native)", flush=True)
subprocess.run(AS + ["xcrun", "simctl", "launch", udid, "com.apple.Preferences"], capture_output=True); time.sleep(4)
NAT = ["General", "Accessibility", "Privacy & Security"]
read("first read, no remote", NAT)
read("no remote", NAT)
read("remote 50 pt", NAT, remote={"step": 50})
read("remote 25 pt", NAT, remote={"step": 25})
read("remote 16 pt", NAT, remote={"step": 16})
eng.stdin.close(); eng.wait(timeout=10)
