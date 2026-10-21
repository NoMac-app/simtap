# What wedges a phone's automation sessions: (1) engines back to back with no gap, (2) AXe while an engine is open,
# then whether the phone recovers. Each case on its own fresh boot (the shell reboots between). As root:
# wedge.py <udid> <case: gap0 | axe-beside>
import json, subprocess, sys, time
udid, case = sys.argv[1], sys.argv[2]
AS = ["launchctl", "asuser", "508", "sudo", "-u", "nmsim2", "-H"]
E = "/usr/local/nomac-test/engine/simulator-use-engine.next"
AXE = "/usr/local/nomac-test/su-next/lib/node_modules/simulator-use/vendor/axe/axe"
def engine_once(label):
    t = time.time()
    p = subprocess.run(AS + ["perl", "-e", "alarm 45; exec @ARGV", E, "--udid", udid], input='{"op":"describe","web":false}\n', capture_output=True, text=True)
    a = next((json.loads(l) for l in p.stdout.splitlines()[1:] if l.startswith("{")), {})
    print(f"  {label}: {'read' if a.get('tree') else 'FAILED ' + str(a.get('error') or 'no answer')} in {int((time.time() - t) * 1000)} ms", flush=True)
    return bool(a.get("tree"))
def axe_once(label):
    t = time.time()
    p = subprocess.run(AS + ["perl", "-e", "alarm 45; exec @ARGV", AXE, "describe-ui", "--udid", udid], capture_output=True, text=True)
    ok = p.returncode == 0 and p.stdout.strip().startswith("[")
    print(f"  {label}: {'read' if ok else 'FAILED ' + (p.stderr or p.stdout).strip()[:70]} in {int((time.time() - t) * 1000)} ms", flush=True)
    return ok
time.sleep(60)
if case == "gap0":
    for i in range(4): engine_once(f"engine {i + 1}, right after the last one")
else:
    eng = subprocess.Popen(AS + [E, "--udid", udid], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1)
    eng.stdout.readline(); eng.stdin.write('{"op":"describe","web":false}\n'); eng.stdin.flush()
    a = json.loads(eng.stdout.readline()); print(f"  a long-lived engine's first read: {'read' if a.get('tree') else a.get('error')}", flush=True)
    axe_once("AXe while that engine is open")
    eng.stdin.write('{"op":"describe","web":false}\n'); eng.stdin.flush()
    a = json.loads(eng.stdout.readline()); print(f"  the engine again: {'read' if a.get('tree') else 'FAILED ' + str(a.get('error'))} in {a.get('ms')} ms", flush=True)
    eng.stdin.close(); eng.wait(timeout=20)
for wait in (5, 30, 60):
    time.sleep(wait)
    if engine_once(f"recovery check, {wait} s later"): break
