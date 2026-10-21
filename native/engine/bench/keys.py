# Whole-screen read cost by attribute set and format, on the home screen and inside Settings.
import json, subprocess, sys, time, os
p = subprocess.Popen([os.path.expanduser("~/sue/sue-engine"), "--udid", sys.argv[1]], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1); json.loads(p.stdout.readline())
def call(req):
    t = time.time(); p.stdin.write(json.dumps(req) + "\n"); p.stdin.flush(); a = json.loads(p.stdout.readline()); return (time.time()-t)*1000, a
full = None
sets = {"all 15 keys": None, "6 keys (label frame value uniqueID type enabled)": ["label", "frame", "value", "uniqueID", "type", "enabled"],
        "4 keys (label frame type value)": ["label", "frame", "type", "value"], "6 keys, flat": "flat"}
for screen in ["home", "settings"]:
    call({"op": "home"}); time.sleep(1)
    if screen == "settings": subprocess.run(["xcrun", "simctl", "launch", sys.argv[1], "com.apple.Preferences"], capture_output=True); time.sleep(3)
    for name, keys in sets.items():
        req = {"op": "describe"}
        if keys == "flat": req.update(keys=["label", "frame", "value", "uniqueID", "type", "enabled"], nested=False)
        elif keys: req["keys"] = keys
        times, cpus = [], []
        for i in range(5):
            ms, a = call(req); times.append(round(ms)); cpus.append(a.get("cpu_ms"))
        print(f"{screen:8} {name:50} {times} ms, engine CPU {cpus} ms, {len(json.dumps(a.get('tree')))} bytes", flush=True)
p.stdin.close(); p.wait()
