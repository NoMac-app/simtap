# A golden made by the pool user at the exact path its sessions use (fixed UDID), copied out, then back in a new
# session: Safari at the same path and UDID (d), and the same copy under another UDID (e).
for u in 508; do launchctl bootout user/$u 2>/dev/null; pkill -9 -u $u; done; sleep 0.5
wipe_home nmsim2 >/dev/null
crashes() { ls /Library/Logs/DiagnosticReports | grep -c MobileSafari; }
FIXED=5E55E550-0000-4000-8000-00000000A002
H=/Users/nmsim2; D=$H/Library/Developer/CoreSimulator/Devices; GU=/Library/NoMacSim/golden-user/nmsim2
vol_up() { diskutil apfs addVolume "$container" APFS "$1" -quota 20g -nomount >/dev/null; mkdir -p $H/Library/Developer; chown nmsim2:staff $H/Library $H/Library/Developer; diskutil mount -mountPoint $H/Library/Developer "$1" >/dev/null; mdutil -i off $H/Library/Developer >/dev/null 2>&1; mkdir -p $D; chown -R nmsim2:staff $H/Library/Developer; chmod 700 $H/Library/Developer; }
vol_down() { as nmsim2 xcrun simctl shutdown all >/dev/null 2>&1; launchctl bootout user/508 2>/dev/null; for i in 1 2 3 4; do pkill -9 -u 508; sleep 0.5; done; local d=$(diskutil list | awk -v v="$1" '$0 ~ " "v" " {print $NF}'); diskutil apfs deleteVolume "$d" >/dev/null; }
echo "== the golden, made by nmsim2 at its session path"
vol_up nms-g1
NEW=$(as nmsim2 xcrun simctl create golden "iPhone 17 Pro" | tail -1)
as nmsim2 xcrun simctl shutdown all >/dev/null 2>&1; launchctl bootout user/508 2>/dev/null; pkill -9 -u 508; sleep 0.5
mv $D/$NEW $D/$FIXED; /usr/libexec/PlistBuddy -c "Set :UDID $FIXED" $D/$FIXED/device.plist
t=$(now); as nmsim2 xcrun simctl boot $FIXED; as nmsim2 perl -e 'alarm 200; exec @ARGV' xcrun simctl bootstatus $FIXED -b >/dev/null; echo "  first boot $(el $t) s; settling 90 s"; sleep 90
before=$(crashes); as nmsim2 xcrun simctl openurl $FIXED https://example.com; sleep 8; echo "  Safari in the golden itself: crash reports +$(( $(crashes) - before ))"
as nmsim2 xcrun simctl shutdown $FIXED; sleep 2
rm -rf $GU; mkdir -p $GU; cp -R $D/$FIXED $GU/; chown -R root:wheel /Library/NoMacSim/golden-user; chmod -R go-w /Library/NoMacSim/golden-user
echo "  golden saved: $(du -sh $GU | cut -f1); paths to its own place inside: $(grep -rl "$D/$FIXED" $GU 2>/dev/null | wc -l | tr -d ' '), to rentamac: $(grep -rl /Users/rentamac $GU 2>/dev/null | wc -l | tr -d ' ')"
vol_down nms-g1
echo "== (d) a new session: the copy at the same path and UDID"
vol_up nms-g2
cp -R $GU/$FIXED $D/; chown -R nmsim2:staff $D
t=$(now); as nmsim2 xcrun simctl boot $FIXED; as nmsim2 perl -e 'alarm 120; exec @ARGV' xcrun simctl bootstatus $FIXED -b >/dev/null; echo "  booted $(el $t) s"; sleep 30
before=$(crashes); as nmsim2 xcrun simctl openurl $FIXED https://example.com; sleep 8; echo "  (d) Safari: crash reports +$(( $(crashes) - before ))"
r=$(printf '%s\n' '{"op":"describe"}' '{"op":"describe"}' | as nmsim2 perl -e 'alarm 60; exec @ARGV' /usr/local/nomac-test/engine/simulator-use-engine --udid $FIXED | python3 /tmp/read.py | tail -1); echo "  (d) on screen: $(echo "$r" | cut -c1-150)"
vol_down nms-g2
echo "== (e) the same copy under another UDID"
vol_up nms-g3
OTHER=$(uuidgen); cp -R $GU/$FIXED $D/$OTHER; /usr/libexec/PlistBuddy -c "Set :UDID $OTHER" $D/$OTHER/device.plist; chown -R nmsim2:staff $D
as nmsim2 xcrun simctl boot $OTHER; as nmsim2 perl -e 'alarm 120; exec @ARGV' xcrun simctl bootstatus $OTHER -b >/dev/null; sleep 30
before=$(crashes); as nmsim2 xcrun simctl openurl $OTHER https://example.com; sleep 8; echo "  (e) Safari: crash reports +$(( $(crashes) - before ))"
vol_down nms-g3
wipe_home nmsim2 >/dev/null; echo done
