# Which step of `simulator-use run` leaves the phone refusing automation sessions? On a fresh phone: an engine read
# (healthy?), then one step, then an engine read again. Steps: build (xcodebuild with the phone as destination),
# install-launch (simctl), run (the whole simulator-use run). As root: culprit.py <udid> <step> <repo dir>
import json, os, subprocess, sys, time
udid, step, repo = sys.argv[1], sys.argv[2], sys.argv[3]
H = "/Users/nmsim2"; DEV = H + "/Library/Developer"
AS = ["launchctl", "asuser", "508", "sudo", "-u", "nmsim2", "-H", "env", "PATH=/usr/local/nomac-test/node/bin:/usr/bin:/bin:/usr/sbin:/sbin",
      f"HOME={H}", f"TMPDIR={DEV}/tmp/", "SIMULATOR_USE_NO_UPDATE=1", f"SIMULATOR_USE_CACHE_DIR={DEV}/su-cache"]
E = repo + "/vendor/axe/simulator-use-engine"
def engine_once(label):
    t = time.time()
    p = subprocess.run(AS + ["perl", "-e", "alarm 60; exec @ARGV", E, "--udid", udid], input='{"op":"describe","web":false}\n', capture_output=True, text=True)
    a = next((json.loads(l) for l in p.stdout.splitlines()[1:] if l.startswith("{")), {})
    print(f"  {label}: {'read' if a.get('tree') else 'FAILED ' + str(a.get('error') or 'no answer')} in {int((time.time() - t) * 1000)} ms (waited {a.get('session_wait_ms')}, recoveries {a.get('session_recoveries')})", flush=True)
def sh(label, cmd):
    t = time.time(); p = subprocess.run(AS + ["sh", "-c", cmd], capture_output=True, text=True)
    print(f"  {label}: exit {p.returncode} in {int((time.time() - t) * 1000)} ms {(p.stdout + p.stderr).strip().splitlines()[-1:] }", flush=True)
time.sleep(40)
engine_once("engine before")
time.sleep(3)
proj = f"{repo}/examples/edge-lab/EdgeLab.xcodeproj"
if step == "build":
    sh("xcodebuild build, the phone as destination", f"xcodebuild -project {proj} -scheme EdgeLab -destination id={udid} -derivedDataPath {DEV}/dd CODE_SIGNING_ALLOWED=NO build > {DEV}/tmp/build.log 2>&1; echo built")
elif step == "install-launch":
    sh("xcodebuild build, no destination (generic)", f"xcodebuild -project {proj} -scheme EdgeLab -destination 'generic/platform=iOS Simulator' -derivedDataPath {DEV}/dd ARCHS=arm64 CODE_SIGNING_ALLOWED=NO build > {DEV}/tmp/build.log 2>&1; echo built")
    time.sleep(3); engine_once("engine after a build that does not name the phone")
    app = subprocess.run(["sh", "-c", f"ls -d {DEV}/dd/Build/Products/*-iphonesimulator/*.app | head -1"], capture_output=True, text=True).stdout.strip()
    sh("simctl install and launch", f"xcrun simctl install {udid} '{app}' && xcrun simctl launch {udid} dev.simtap.edgelab")
elif step == "run":
    sh("simulator-use run", f"cd {repo} && node bin/simulator-use.js run examples/edge-lab --device {udid}")
time.sleep(3)
engine_once("engine after")
time.sleep(10)
engine_once("engine 10 s later")
