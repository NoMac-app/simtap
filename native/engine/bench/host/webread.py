# Can the engine read a web page? Safari opened on a page, then read every 2 s for 30 s through one engine.
import json, subprocess, sys, time
udid = sys.argv[1]
AS = ["launchctl", "asuser", "508", "sudo", "-u", "nmsim2", "-H"]
eng = subprocess.Popen(AS + ["/usr/local/nomac-test/engine/simulator-use-engine", "--udid", udid], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1)
eng.stdout.readline()
def call(req):
    eng.stdin.write(json.dumps(req) + "\n"); eng.stdin.flush(); return json.loads(eng.stdout.readline())
def nodes(t):
    for n in t or []:
        yield n; yield from nodes(n.get("children"))
for _ in range(3):
    if call({"op": "describe"}).get("tree"): break
subprocess.run(AS + ["xcrun", "simctl", "openurl", udid, "https://example.com"])
t0 = time.time()
while time.time() - t0 < 30:
    a = call({"op": "describe"})
    tree = a.get("tree") or []
    labels = [n.get("AXLabel") for n in nodes(tree) if n.get("AXLabel")]
    app = tree[0].get("AXLabel") if tree else None
    print(f"  {time.time() - t0:4.1f} s: {a.get('ms')} ms, app {app!r}, {len(json.dumps(tree))} bytes, {len(labels)} labels, Example Domain: {'yes' if any('Example Domain' in (l or '') for l in labels) else 'no'} {labels[:4] if len(labels) < 30 else ''}", flush=True)
    if len(labels) >= 30: print("     labels:", [l for l in labels if l and l.strip()][:40], flush=True)
    if any('Example Domain' in (l or '') for l in labels): break
    time.sleep(2)
for y in (150, 250, 350, 450):
    p = call({"op": "point", "x": 200, "y": y}); e = p.get("element") or {}
    print(f"  a point read at 200,{y}: {p.get('ms')} ms, {e.get('role')} {e.get('AXLabel')!r} {e.get('AXValue')!r}", flush=True)
eng.stdin.close(); eng.wait(timeout=10)
