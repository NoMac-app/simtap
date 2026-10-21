# An iPad as the pool user, through one engine: first reads, a screenshot, and opening Settings (tap, settle, read).
import json, re, subprocess, sys, time
udid = sys.argv[1]
AS = ["launchctl", "asuser", "507", "sudo", "-u", "nmsim1", "-H"]
eng = subprocess.Popen(AS + ["/usr/local/nomac-test/engine/simulator-use-engine", "--udid", udid], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1)
print("  engine:", eng.stdout.readline().strip()[:100])
def call(req):
    eng.stdin.write(json.dumps(req) + "\n"); eng.stdin.flush(); return json.loads(eng.stdout.readline())
def nodes(t):
    for n in t or []:
        yield n; yield from nodes(n.get("children"))
ms = []
for _ in range(6):
    a = call({"op": "describe"}); ms.append(a.get("ms") if a.get("tree") else f"error {a.get('error')}")
print("  whole-screen reads (ms):", ms)
labels = [n.get("AXLabel") for n in nodes(a.get("tree")) if n.get("AXLabel")]
print("  on screen:", labels[:8])
s = call({"op": "screenshot"}); print(f"  screenshot: {s.get('ms')} ms, {s.get('bytes')} bytes (JPEG)")
f = None
for n in nodes(a.get("tree")):
    if n.get("AXLabel") == "Settings":
        f = n.get("frame") or {}
        if not f and isinstance(n.get("AXFrame"), str):
            x, y, w, h = map(float, re.findall(r"[-\d.]+", n["AXFrame"])[:4]); f = {"x": x, "y": y, "width": w, "height": h}
        break
if f:
    t = time.time(); b = call({"op": "tap_settle_describe", "x": f["x"] + f["width"] / 2, "y": f["y"] + f["height"] / 2})
    print(f"  open Settings: {int((time.time() - t) * 1000)} ms, General on screen: {'General' in json.dumps(b.get('tree'))}")
else: print("  no Settings icon found")
eng.stdin.close(); eng.wait(timeout=10)
