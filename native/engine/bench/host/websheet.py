# Sign-in sheets and in-app browsers: ASWebAuthenticationSession (iOS's "wants to use ... to sign in" alert, then a
# Safari sheet) and SFSafariViewController, both on github.com/login, read through one engine as nmsim2; the tree
# around the remote view dumped to see how it appears. Usage (as root): websheet.py <udid>
import json, subprocess, sys, time
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
def dump(t, depth=0, limit=[60]):
    for n in t or []:
        if limit[0] <= 0: return
        limit[0] -= 1
        f = n.get("frame") or {}
        print(f"    {'  ' * depth}{n.get('role')} {texts(n)[:1]} {int(f.get('x', 0))},{int(f.get('y', 0))} {int(f.get('width', 0))}x{int(f.get('height', 0))} pid {n.get('pid')}{' (scan)' if n.get('found_by') else ''}", flush=True)
        dump(n.get("children"), depth + 1, limit)
def read(name, show=False, save=None):
    t = time.time(); a = call({"op": "describe"}); took = int((time.time() - t) * 1000)
    tree = a.get("tree"); w = a.get("web_scan") or {}
    labels = [t for n in nodes(tree) for t in texts(n)]
    print(f"  {name}: {took} ms, app {(tree or [{}])[0].get('AXLabel')!r}, scan {w.get('ms')} ms pages {w.get('pages')}, {len(labels)} texts, GitHub page read: {'Sign in to GitHub' in ' '.join(labels)}", flush=True)
    if show: dump(tree, limit=[45])
    if save: json.dump(tree, open(f"/tmp/ws-{save}.json", "w"))
    return tree
def launch(*args):
    subprocess.run(AS + ["xcrun", "simctl", "terminate", udid, "app.nomac.webtest"], capture_output=True)
    subprocess.run(AS + ["xcrun", "simctl", "launch", udid, "app.nomac.webtest", *args], capture_output=True)
for _ in range(3):
    if call({"op": "describe", "web": False}).get("tree"): break
print("== ASWebAuthenticationSession", flush=True)
launch("-mode", "auth"); time.sleep(3)
tree = read("the system's question", show=True, save="auth-alert")
cont = next((n for n in nodes(tree) if n.get("role") == "AXButton" and "Continue" in texts(n)), None)
if cont:
    call({"op": "tap_settle_describe", "x": center(cont)[0], "y": center(cont)[1]}); time.sleep(5)
    read("the sign-in sheet", show=True, save="auth-sheet"); read("the sign-in sheet again")
else: print("  no Continue button", flush=True)
print("== SFSafariViewController", flush=True)
launch("-mode", "safari"); time.sleep(6)
read("the in-app browser", show=True, save="safari-vc"); read("the in-app browser again")
eng.stdin.close(); eng.wait(timeout=10)
