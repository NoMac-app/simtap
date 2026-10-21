# XCTest's snapshot of EdgeLab's SwiftUI web page (where point reads fail): do the page's elements come back?
# As root: labsnap.py <udid> <repo dir>
import json, subprocess, sys, time
udid, repo = sys.argv[1], sys.argv[2]
H = "/Users/nmsim2"; DEV = H + "/Library/Developer"
AS = ["launchctl", "asuser", "508", "sudo", "-u", "nmsim2", "-H", "env", "PATH=/usr/local/nomac-test/node/bin:/usr/bin:/bin:/usr/sbin:/sbin",
      f"HOME={H}", f"TMPDIR={DEV}/tmp/", "SIMULATOR_USE_NO_UPDATE=1", f"SIMULATOR_USE_CACHE_DIR={DEV}/su-cache"]
def cli(args):
    p = subprocess.run(AS + ["sh", "-c", f"cd {repo} && node bin/simulator-use.js {args}"], capture_output=True, text=True)
    return (p.stdout + p.stderr).strip()
time.sleep(30)
cli(f"run examples/edge-lab --device {udid}")
cli(f"act --device {udid} 'tap More' 'tap \"Web page\"'"); time.sleep(3)
eng = subprocess.Popen(AS + ["/usr/local/nomac-test/engine/sue-dbg", "--udid", udid], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1)
eng.stdout.readline()
def call(req):
    eng.stdin.write(json.dumps(req) + "\n"); eng.stdin.flush(); return json.loads(eng.stdout.readline())
a = call({"op": "describe", "web": False}); print("  describe:", a.get("ms"), "ms, app pid", (a.get("tree") or [{}])[0].get("pid"), flush=True)
for params in ({},):
    t = time.time(); s = call({"op": "xcsnapshot", "parameters": params}); took = int((time.time() - t) * 1000)
    blob = json.dumps(s.get("snapshot") or s.get("description") or "")
    print(f"  xcsnapshot params {list(params)}: {took} ms (fetch {s.get('fetch_ms')}), class {s.get('result_class')} -> {s.get('snapshot_class')}, error {s.get('snapshot_error') or s.get('error')}, {len(blob)} chars; page texts: " + ", ".join(f"{w}={'yes' if w in blob else 'no'}" for w in ("Web page", "Web field", "Web button", "waiting", "Controls")), flush=True)
    print("   attributes:", s.get("attributes"), flush=True)
    print(f"   nodes {s.get('nodes')}, pids {s.get('pids')}, remote parts {s.get('remote_count')}", flush=True)
    for r in s.get("remote_trees") or []: print("   remote:", str(r)[:1500].replace(chr(10), " | "), flush=True)
    json.dump(s.get("snapshot"), open("/tmp/xcsnap.json", "w"))
eng.stdin.close(); eng.wait(timeout=10)
