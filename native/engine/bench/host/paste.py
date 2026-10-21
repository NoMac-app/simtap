# Pastes text set inside the phone (pbset) into Spotlight's field with Cmd+V through one engine, then reads the field.
import json, subprocess, sys, time
udid, text = sys.argv[1], sys.argv[2]
AS = ["launchctl", "asuser", "507", "sudo", "-u", "nmsim1", "-H"]
eng = subprocess.Popen(AS + ["/usr/local/nomac-test/engine/simulator-use-engine", "--udid", udid], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1)
eng.stdout.readline()
def call(req):
    eng.stdin.write(json.dumps(req) + "\n"); eng.stdin.flush(); return json.loads(eng.stdout.readline())
for _ in range(3):
    if call({"op": "describe"}).get("tree"): break
call({"op": "home"}); time.sleep(1)
call({"op": "swipe", "x1": 201, "y1": 400, "x2": 201, "y2": 700, "duration": 0.25}); time.sleep(1.5)
r = subprocess.run(AS + ["xcrun", "simctl", "spawn", udid, "/usr/local/nomac-test/pbset/pbset", text], capture_output=True, text=True)
print("  pbset:", r.returncode, r.stderr.strip())
t = time.time()
print("  Cmd+V:", call({"op": "steps", "steps": [{"combo": {"mods": [227], "key": 25}}]}).get("ok"))
call({"op": "settle", "first_change_ms": 300})
tree = json.dumps(call({"op": "describe"}).get("tree"), ensure_ascii=False)
print(f"  pasted text in the field: {'yes' if text in tree else 'NO'} ({time.time() - t:.1f} s); allow-paste prompt: {'yes' if 'Allow Paste' in tree else 'no'}")
call({"op": "home"}); eng.stdin.close(); eng.wait(timeout=10)
