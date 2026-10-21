for u in 508; do launchctl bootout user/$u 2>/dev/null; pkill -9 -u $u; done; sleep 0.5
wipe_home nmsim2 >/dev/null
FIXED=5E55E550-0000-4000-8000-00000000A002; H=/Users/nmsim2; DEV=$H/Library/Developer; GU=/Library/NoMacSim/golden-user/nmsim2/$FIXED
diskutil apfs addVolume "$container" APFS nmu-nmsim2 -quota 30g -nomount >/dev/null; mkdir -p $DEV; diskutil mount -mountPoint $DEV nmu-nmsim2 >/dev/null; mdutil -i off $DEV >/dev/null 2>&1; chown root:wheel $DEV; chmod 1777 $DEV
mkdir -p $DEV/.golden $DEV/CoreSimulator/Devices; cp -R $GU $DEV/.golden/; chown nmsim2:staff $DEV/CoreSimulator $DEV/CoreSimulator/Devices; cp -c -R $DEV/.golden/$FIXED $DEV/CoreSimulator/Devices/; chown -R nmsim2:staff $DEV/CoreSimulator/Devices/$FIXED
as nmsim2 xcrun simctl boot $FIXED; as nmsim2 perl -e 'alarm 120; exec @ARGV' xcrun simctl bootstatus $FIXED -b >/dev/null; sleep 40
python3 /tmp/webread.py $FIXED
AXE=/usr/local/nomac-test/su-next/lib/node_modules/simulator-use/vendor/axe/axe
t=$(now); out=$(as nmsim2 perl -e 'alarm 90; exec @ARGV' $AXE describe-ui --udid $FIXED 2>&1); echo "  AXe describe-ui of the same page: exit $? in $(el $t) s, $(echo "$out" | wc -c | tr -d ' ') bytes, Example Domain: $(echo "$out" | grep -c 'Example Domain'), page text: $(echo "$out" | grep -c 'documentation examples')"
as nmsim2 xcrun simctl shutdown all >/dev/null 2>&1; launchctl bootout user/508 2>/dev/null; for i in 1 2 3; do pkill -9 -u 508; sleep 0.5; done
diskutil unmount $DEV >/dev/null; d=$(diskutil list | awk '/ nmu-nmsim2 / {print $NF}'); diskutil apfs deleteVolume $d >/dev/null; wipe_home nmsim2 >/dev/null; echo done
