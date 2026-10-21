# T13: clone of a settled golden phone vs a brand-new phone: make, boot, then the first successful
# full read through one engine (the accessibility service accepting a reader), and the host's load.
import json, subprocess, sys, time, os
ENGINE = os.path.expanduser("~/sue/sue-engine")
def sh(*a): return subprocess.run(a, capture_output=True, text=True).stdout.strip()
rt = [l.split()[-1] for l in sh("xcrun", "simctl", "list", "runtimes", "available").splitlines() if l.startswith("iOS")][-1]
gold = [l.split("(")[1].split(")")[0] for l in sh("xcrun", "simctl", "list", "devices").splitlines() if "bench-a" in l][0]
subprocess.run(["xcrun", "simctl", "shutdown", gold], capture_output=True); time.sleep(2)
def first_read(udid, limit=180):
    t0 = time.time(); tries = 0
    p = subprocess.Popen([ENGINE, "--udid", udid], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1)
    ready = json.loads(p.stdout.readline())
    if not ready.get("ready"): return None, ready, 0
    while time.time() - t0 < limit:
        tries += 1
        p.stdin.write('{"op":"describe"}\n'); p.stdin.flush()
        a = json.loads(p.stdout.readline())
        if a.get("ok") and a.get("tree"): 
            n = len(json.dumps(a["tree"])); p.stdin.close(); p.wait(); return time.time() - t0, n, tries
        time.sleep(0.25)
    p.stdin.close(); p.wait(); return None, a.get("error"), tries
for kind in ["clone", "clone", "fresh"]:
    t0 = time.time()
    udid = sh("xcrun", "simctl", "clone", gold, f"t13-{kind}-{int(t0)}") if kind == "clone" else sh("xcrun", "simctl", "create", f"t13-fresh-{int(t0)}", "iPhone 17 Pro", rt)
    t1 = time.time(); subprocess.run(["xcrun", "simctl", "boot", udid]); subprocess.run(["xcrun", "simctl", "bootstatus", udid, "-b"], capture_output=True); t2 = time.time()
    secs, info, tries = first_read(udid)
    time.sleep(15); load = sh("sysctl", "-n", "vm.loadavg").split()[1]; procs = len(sh("ps", "-A").splitlines())
    print(f"{kind:5} make {t1-t0:.1f} s, boot {t2-t1:.1f} s, first full read {secs if secs is None else round(secs,1)} s after boot ({tries} tries, {info}), total {(t2-t0)+(secs or 0):.1f} s; 15 s later load {load}, {procs} processes", flush=True)
    subprocess.run(["xcrun", "simctl", "shutdown", udid], capture_output=True); subprocess.run(["xcrun", "simctl", "delete", udid], capture_output=True); time.sleep(5)
