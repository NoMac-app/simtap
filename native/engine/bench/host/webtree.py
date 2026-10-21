# How a web view appears in the frontmost app's tree (WebTest, then Safari with a screenshot), to detect it exactly.
# Usage (as root): webtree.py <udid>
import base64, json, os, subprocess, sys, time
udid = sys.argv[1]
AS = ["launchctl", "asuser", "508", "sudo", "-u", "nmsim2", "-H"]
eng = subprocess.Popen(AS + [os.environ.get("ENGINE", "/usr/local/nomac-test/engine/simulator-use-engine"), "--udid", udid], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1)
eng.stdout.readline()
def call(req):
    eng.stdin.write(json.dumps(req) + "\n"); eng.stdin.flush(); return json.loads(eng.stdout.readline())
def dump(t, depth=0):
    for n in t or []:
        txt = [str(n.get(k)) for k in ("AXLabel", "AXValue") if n.get(k) not in (None, "", " ")]
        f = n.get("frame") or {}
        print(f"  {'  ' * depth}{n.get('role')} {n.get('type')} {txt[:1]} {int(f.get('x', 0))},{int(f.get('y', 0))} {int(f.get('width', 0))}x{int(f.get('height', 0))} pid {n.get('pid')} children {len(n.get('children') or [])}", flush=True)
        dump(n.get("children"), depth + 1)
for _ in range(3):
    if call({"op": "describe"}).get("tree"): break
subprocess.run(AS + ["xcrun", "simctl", "launch", udid, "app.nomac.webtest"], capture_output=True); time.sleep(4)
print("== WebTest's tree", flush=True); dump(call({"op": "describe"}).get("tree"))
subprocess.run(AS + ["xcrun", "simctl", "openurl", udid, "https://github.com/login"]); time.sleep(10)
a = call({"op": "describe"})
print("== Safari's tree (github.com/login)", flush=True); dump(a.get("tree"))
s = call({"op": "screenshot", "inline": True})
open("/tmp/safari-github.jpg", "wb").write(base64.b64decode(s.get("jpeg_base64", ""))); print("  screenshot saved", flush=True)
eng.stdin.close(); eng.wait(timeout=10)
