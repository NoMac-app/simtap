# Expo Go, the way hostd would do it: Metro alone on the session's port, Expo Go installed by us, the URL opened with
# simctl; then an edit reaching the phone through Fast Refresh. As the pool user nmsim1.
for u in 507; do launchctl bootout user/$u 2>/dev/null; pkill -9 -u $u; done; sleep 0.5
wipe_home nmsim1 >/dev/null
start nmsim1 ex8; UE=$UDID
echo "  phone settling 30 s"; sleep 30
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
python3 /tmp/expo3.py "$UE" $W/demo/App.js /tmp/expo2-start.log
grep -i "error\|warn" /tmp/expo2-start.log | head -4 | cut -c1-160
pkill -u 507 -f "expo start"; pkill -u 507 node
finish nmsim1 ex8
