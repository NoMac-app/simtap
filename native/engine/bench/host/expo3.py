# Expo Go through one engine for the whole run (a second engine on a young phone cannot open a session): open the
# project URL, tap iOS's "Open" prompt, wait for the app, change App.js, time until the change is on screen.
# Run as root: expo3.py <udid> <App.js path> <metro log>
import json, re, subprocess, sys, time
udid, appjs, metro_log = sys.argv[1:4]
E = "/usr/local/nomac-test/engine/simulator-use-engine"
AS = ["launchctl", "asuser", "507", "sudo", "-u", "nmsim1", "-H"]
eng = subprocess.Popen(AS + [E, "--udid", udid], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1)
eng.stdout.readline()
def call(req):
    eng.stdin.write(json.dumps(req) + "\n"); eng.stdin.flush()
    return json.loads(eng.stdout.readline())
def nodes(tree):
    for n in tree or []:
        yield n
        yield from nodes(n.get("children"))
def find(label):
    a = call({"op": "describe"})
    for n in nodes(a.get("tree")):
        if n.get("AXLabel") == label:
            f = n.get("frame") or {}
            if not f and isinstance(n.get("AXFrame"), str):
                x, y, w, h = map(float, re.findall(r"[-\d.]+", n["AXFrame"])[:4]); f = {"x": x, "y": y, "width": w, "height": h}
            return f, a
    return None, a
def text_on_screen(a): return json.dumps(a.get("tree") or [])
for _ in range(3):
    a = call({"op": "describe"})
    if a.get("tree"): break
print(f"  engine reads the phone: {a.get('ms')} ms", flush=True)
t0 = time.time()
subprocess.run(AS + ["xcrun", "simctl", "openurl", udid, "exp://127.0.0.1:20101"])
tries = 0
for _ in range(60):
    f, a = find("Open")
    if f:
        # The prompt slides in: a tap during its animation is dropped. Wait for a still screen, tap, check it is gone.
        call({"op": "settle", "first_change_ms": 0})
        f, a = find("Open")
        if f:
            tries += 1
            call({"op": "tap", "x": f["x"] + f["width"] / 2, "y": f["y"] + f["height"] / 2})
            call({"op": "settle", "first_change_ms": 300})
            if find("Open")[0] is None: break
    time.sleep(0.25)
print(f"  iOS's Open prompt tapped and gone {time.time() - t0:.1f} s after openurl ({tries} taps)", flush=True)
while time.time() - t0 < 120:
    a = call({"op": "describe"})
    if "Open up App.js" in text_on_screen(a): break
    time.sleep(0.3)
print(f"  the app's text readable {time.time() - t0:.1f} s after openurl", flush=True)
time.sleep(2)
t1 = time.time()
# The edit made by the pool user, as the product's sync writes files
subprocess.run(["sudo", "-u", "nmsim1", "sed", "-i", "", "s/Open up App.js to start working on your app!/Changed by the agent on NoMac/", appjs])
seen = None
while time.time() - t1 < 15:
    a = call({"op": "describe", "keys": ["AXLabel"]})
    if "Changed by the agent" in text_on_screen(a): seen = time.time() - t1; break
print(f"  the edit on screen: {f'{seen:.2f} s after the file changed (reads take about 0.3 s each)' if seen else 'not within 15 s'}", flush=True)
conns = subprocess.run(["lsof", "-nP", "-a", "-u", "nmsim1", "-iTCP:20101"], capture_output=True, text=True).stdout.splitlines()[1:]
print(f"  TCP connections on Metro's port: {len(conns)}: " + "; ".join(" ".join(c.split()[i] for i in (0, 8, 9)) for c in conns[:6]), flush=True)
if not seen:
    b = subprocess.run(AS + ["curl", "-s", "-m", "60", "http://127.0.0.1:20101/index.bundle?platform=ios&dev=true&minify=false"], capture_output=True, text=True).stdout
    print(f"  Metro's bundle fetched after the edit ({len(b) // 1024} KB): {'has the new text, so Metro saw the change and the hot update did not reach the app' if 'Changed by the agent' in b else 'still the old text, so Metro did not see the change' if 'Open up App.js' in b else 'neither text found'}", flush=True)
    t2 = time.time()
    r = subprocess.run(AS + ["/usr/local/nomac-test/node/bin/node", "/tmp/metro-reload.mjs", "20101"], capture_output=True, text=True)
    for _ in range(60):
        if "Changed by the agent" in text_on_screen(call({"op": "describe", "keys": ["AXLabel"]})):
            print(f"  a reload through Metro's message socket ({r.stdout.strip()}): the edit on screen {time.time() - t2:.1f} s later", flush=True); break
        time.sleep(0.2)
    else: print(f"  a reload through Metro's message socket ({(r.stdout + r.stderr).strip()[:80]}): the edit still not on screen", flush=True)
print("  Metro after the edit: " + " | ".join(l.strip()[:80] for l in open(metro_log).read().splitlines()[-4:]), flush=True)
eng.stdin.close(); eng.wait(timeout=10)
