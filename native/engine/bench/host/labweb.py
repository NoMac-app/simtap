# EdgeLab's web page (a SwiftUI WKWebView in a navigation stack and a tab bar): the tree around the web view, the
# engine's scan report, and point reads in the page. As root: labweb.py <udid> <repo dir>
import json, subprocess, sys, time
udid, repo = sys.argv[1], sys.argv[2]
H = "/Users/nmsim2"; DEV = H + "/Library/Developer"
AS = ["launchctl", "asuser", "508", "sudo", "-u", "nmsim2", "-H", "env", "PATH=/usr/local/nomac-test/node/bin:/usr/bin:/bin:/usr/sbin:/sbin",
      f"HOME={H}", f"TMPDIR={DEV}/tmp/", "SIMULATOR_USE_NO_UPDATE=1", f"SIMULATOR_USE_CACHE_DIR={DEV}/su-cache"]
def cli(args):
    p = subprocess.run(AS + ["sh", "-c", f"cd {repo} && node bin/simulator-use.js {args}"], capture_output=True, text=True)
    return (p.stdout + p.stderr).strip()
time.sleep(30)
print(cli(f"run examples/edge-lab --device {udid}").splitlines()[:1], flush=True)
print(cli(f"act --device {udid} 'tap More' 'tap \"Web page\"'").splitlines()[:3], flush=True)
time.sleep(3)
eng = subprocess.Popen(AS + [repo + "/vendor/axe/simulator-use-engine", "--udid", udid], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1)
eng.stdout.readline()
def call(req):
    eng.stdin.write(json.dumps(req) + "\n"); eng.stdin.flush(); return json.loads(eng.stdout.readline())
def dump(t, depth=0):
    for n in t or []:
        f = n.get("frame") or {}
        txt = [str(n.get(k)) for k in ("AXLabel", "AXValue") if n.get(k) not in (None, "", " ")]
        if n.get("role") not in ("AXGroup",) or txt or n.get("found_by") or depth < 2 or n.get("role") == "AXScrollArea":
            print(f"    {'  ' * depth}{n.get('role')} {txt[:1]} {int(f.get('x', 0))},{int(f.get('y', 0))} {int(f.get('width', 0))}x{int(f.get('height', 0))} pid {n.get('pid')}{' (scan)' if n.get('found_by') else ''}", flush=True)
        dump(n.get("children"), depth + 1)
a = call({"op": "describe"})
time.sleep(2); a = call({"op": "describe"})
print(f"  the engine's read: scan {a.get('web_scan')}", flush=True)
dump(a.get("tree"))
for (x, y) in ((38, 84), (52, 139), (64, 822), (339, 822), (60, 200), (201, 480)):
    p = call({"op": "point", "x": x, "y": y}); e = p.get("element") or {}
    f = e.get("frame") or {}
    if not e: print(f"  point {x},{y}: answer {json.dumps(p)[:300]}", flush=True); continue
    print(f"  point {x},{y}: {e.get('role')} {[e.get('AXLabel'), e.get('AXValue')]} {int(f.get('x', 0))},{int(f.get('y', 0))} {int(f.get('width', 0))}x{int(f.get('height', 0))} pid {e.get('pid')}", flush=True)
eng.stdin.close(); eng.wait(timeout=10)
