# Expo Go, the way hostd would do it: Metro alone on the session's port, Expo Go installed by us, the URL opened with
# simctl; then an edit reaching the phone through Fast Refresh. As the pool user nmsim1.
for u in 507; do launchctl bootout user/$u 2>/dev/null; pkill -9 -u $u; done; sleep 0.5
wipe_home nmsim1 >/dev/null
start nmsim1 ex3; UE=$UDID
W=/Users/nmsim1/Library/Developer/work; NODE=/usr/local/nomac-test/node/bin; E=/usr/local/nomac-test/engine/simulator-use-engine
run() { as nmsim1 env PATH=$NODE:/usr/bin:/bin:/usr/sbin:/sbin HOME=/Users/nmsim1 TMPDIR=/Users/nmsim1/Library/Developer/tmp/ EXPO_NO_TELEMETRY=1 "$@"; }
mkdir -p $W /Users/nmsim1/Library/Developer/tmp; chown nmsim1:staff $W /Users/nmsim1/Library/Developer/tmp
t=$(now); run sh -c "cd $W && npx --yes create-expo-app@latest demo --template blank --no-install >/tmp/expo2-create.log 2>&1 && cd demo && npm install --no-audit --no-fund >>/tmp/expo2-create.log 2>&1"; echo "  create-expo-app + npm install: $(el $t) s"
G=/usr/local/nomac-test/expo-go; mkdir -p $G
if [ ! -d $G/Expo-Go-58.0.5.app ]; then
  t=$(now); curl -fsSL -o $G/expo-go.tar.gz https://github.com/expo/expo-go-releases/releases/download/Expo-Go-58.0.5/Expo-Go-58.0.5.tar.gz && mkdir -p $G/Expo-Go-58.0.5.app && tar -xzf $G/expo-go.tar.gz -C $G/Expo-Go-58.0.5.app && chmod -R a+rX $G
  echo "  Expo Go 58.0.5 downloaded and unpacked: $(el $t) s ($(du -sh $G/expo-go.tar.gz | cut -f1) download, $(du -sh $G/Expo-Go-58.0.5.app | cut -f1) app)"
fi
t=$(now); as nmsim1 xcrun simctl install "$UE" $G/Expo-Go-58.0.5.app; echo "  Expo Go installed in the phone: $(el $t) s"
t=$(now)
run sh -c "cd $W/demo && exec npx expo start --port 20101 </dev/null" > /tmp/expo2-start.log 2>&1 &
for i in $(seq 1 120); do grep -q "Waiting on\|Metro waiting\|exp://" /tmp/expo2-start.log && break; sleep 0.5; done
echo "  Metro up after $(el $t) s: $(grep -o 'Metro waiting on [^ ]*\|Waiting on [^ ]*' /tmp/expo2-start.log | head -1)"
t=$(now); as nmsim1 xcrun simctl openurl "$UE" "exp://127.0.0.1:20101"
# iOS asks 'Open in "Expo Go"?' first: tap Open, the way hostd would (simulator-use, as the pool user)
for i in $(seq 1 10); do
  o=$(as nmsim1 env PATH=$NODE:/usr/bin:/bin SIMULATOR_USE_ENGINE=$E perl -e 'alarm 60; exec @ARGV' /usr/local/nomac-test/su-next/bin/simulator-use act 'tap "Open"' 2>&1)
  echo "$o" | grep -qi "not found\|no element\|error" || break; sleep 1
done
echo "  the Open prompt tapped after $(el $t) s: $(echo "$o" | head -2 | tr '\n' ' ' | cut -c1-120)"
for i in $(seq 1 240); do grep -qi "bundled" /tmp/expo2-start.log && break; sleep 0.5; done
echo "  bundle served after $(el $t) s: $(grep -io 'ios bundled [^ ]* [^ ]*' /tmp/expo2-start.log | head -1)"
r=""
for i in $(seq 1 30); do
  r=$(printf '%s\n' '{"op":"describe"}' | as nmsim1 perl -e 'alarm 40; exec @ARGV' $E --udid "$UE" | python3 /tmp/read.py | tail -1)
  echo "$r" | grep -q "Open up App" && break; sleep 2
done
echo "  the app readable after $(el $t) s from openurl: $(echo "$r" | cut -c1-120)"
# Fast Refresh: change the text, read every 0.25 s with one engine
( sleep 1; printf '{"op":"describe"}\n'; for i in $(seq 1 30); do sleep 0.2; printf '{"op":"describe","keys":["AXLabel"]}\n'; done ) | as nmsim1 "$E" --udid "$UE" > /tmp/expo2-edit.jsonl 2>/dev/null &
EP=$!; sleep 2.5
t=$(now); run sed -i '' 's/Open up App.js to start working on your app!/Changed by the agent on NoMac/' $W/demo/App.js
wait $EP
python3 - "$t" <<'PY'
import json, sys
n = 0; ms = 0
for line in open("/tmp/expo2-edit.jsonl"):
    try: a = json.loads(line)
    except Exception: continue
    if "tree" not in a: continue
    n += 1
    if "Changed by the agent" in json.dumps(a["tree"]):
        print(f"  the edit was on screen at read {n} (reads 0.2 s apart plus about 0.3 s each, the edit made before read 3 or 4)"); break
else: print(f"  the edit did not show in {n} reads")
PY
grep -i "error\|warn" /tmp/expo2-start.log | head -4 | cut -c1-160
pkill -u 507 -f "expo start"; pkill -u 507 node
finish nmsim1 ex3
