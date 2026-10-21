# T9 (run as root): tenant B's phone while tenant A burns 12 cores, at normal priority, demoted by root, after A
# tries to undo it, and started clamped. One engine for B's phone for the whole test. Usage: t9.py <B's udid>
import json, os, subprocess, sys, time
UB = sys.argv[1]
E = "/usr/local/nomac-test/engine/simulator-use-engine"
def as_user(uid, name, cmd, **kw):
    return ["launchctl", "asuser", str(uid), "sudo", "-u", name, "-H"] + cmd
eng = subprocess.Popen(as_user(508, "nmsim2", [E, "--udid", UB]), stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1)
print("engine:", eng.stdout.readline().strip()[:80])
def call(req):
    eng.stdin.write(json.dumps(req) + "\n"); eng.stdin.flush()
    return json.loads(eng.stdout.readline())
def a_cpu():
    out = subprocess.run(["ps", "-u", "nmsim1", "-o", "%cpu="], capture_output=True, text=True).stdout.split()
    return round(sum(float(x) for x in out))
def phase(label, n=15):
    reads, shots = [], []
    for _ in range(n):
        a = call({"op": "describe"}); reads.append(a.get("ms", 99999) if a.get("tree") else 99999)
        b = call({"op": "screenshot", "format": "jpeg"}); shots.append(b.get("ms", 99999))
    reads.sort(); shots.sort()
    load = os.getloadavg()[0]
    print(f"  {label}: read p50 {reads[n//2]} ms, p90 {reads[int(n*0.9)]} ms; screenshot p50 {shots[n//2]} ms; A's CPU {a_cpu()}%; load {load:.1f}", flush=True)
burners = []
def burn(prefix=()):
    for _ in range(12):
        burners.append(subprocess.Popen(as_user(507, "nmsim1", list(prefix) + ["yes"]), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
    time.sleep(3)
def yes_pids():
    return subprocess.run(["pgrep", "-u", "nmsim1", "-x", "yes"], capture_output=True, text=True).stdout.split()
def stop():
    subprocess.run(["pkill", "-9", "-u", "nmsim1", "-x", "yes"]); time.sleep(2)
for _ in range(3): call({"op": "describe"})
phase("quiet")
burn(); phase("A burns 12 threads at normal priority")
for p in yes_pids(): subprocess.run(["taskpolicy", "-b", "-p", p])
time.sleep(2); phase("root set A's burners to background (taskpolicy -b -p)")
undo = [subprocess.run(["sudo", "-u", "nmsim1", "taskpolicy", "-B", "-p", p], capture_output=True, text=True) for p in yes_pids()]
print(f"  A's undo (taskpolicy -B -p as A): {sum(r.returncode == 0 for r in undo)} of {len(undo)} accepted; {(undo[0].stderr or '').strip()[:80]}")
time.sleep(2); phase("after A's undo")
stop()
burn(("taskpolicy", "-c", "background")); phase("A's burners started clamped (taskpolicy -c background)")
undo = [subprocess.run(["sudo", "-u", "nmsim1", "taskpolicy", "-B", "-p", p], capture_output=True, text=True) for p in yes_pids()]
print(f"  A's undo of the clamp: {sum(r.returncode == 0 for r in undo)} of {len(undo)} accepted")
time.sleep(2); phase("after A's undo of the clamp")
stop(); phase("quiet again")
eng.stdin.close(); eng.wait(timeout=10)
