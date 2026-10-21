# xcresulttool as the pool user, on a result bundle of the demo's tests.
FIXED=5E55E550-0000-4000-8000-00000000A002; H=/Users/nmsim2; DEV=$H/Library/Developer; GU=/Library/NoMacSim/golden-user/nmsim2/$FIXED
for u in 508; do launchctl bootout user/$u 2>/dev/null; for i in 1 2 3; do pkill -9 -u $u; sleep 0.5; done; done
diskutil unmount force $DEV >/dev/null 2>&1; d=$(diskutil list | awk '/ nmu-nmsim2 / {print $NF}'); [ -n "$d" ] && diskutil apfs deleteVolume $d >/dev/null
wipe_home nmsim2 >/dev/null
diskutil apfs addVolume "$container" APFS nmu-nmsim2 -quota 30g -nomount >/dev/null; mkdir -p $DEV; diskutil mount -mountPoint $DEV nmu-nmsim2 >/dev/null; mdutil -i off $DEV >/dev/null 2>&1; chown root:wheel $DEV; chmod 1777 $DEV
mkdir -p $DEV/.golden $DEV/CoreSimulator/Devices $DEV/tmp $DEV/work; cp -R $GU $DEV/.golden/; cp -c -R $DEV/.golden/$FIXED $DEV/CoreSimulator/Devices/; cp -R /tmp/simtap-repo $DEV/work/simtap
chown -R nmsim2:staff $DEV/CoreSimulator $DEV/tmp $DEV/work
as nmsim2 xcrun simctl boot $FIXED; as nmsim2 perl -e 'alarm 120; exec @ARGV' xcrun simctl bootstatus $FIXED -b >/dev/null
run() { as nmsim2 env PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME=$H TMPDIR=$DEV/tmp/ "$@"; }
run() { as nmsim2 env PATH=/usr/local/nomac-test/node/bin:/usr/bin:/bin:/usr/sbin:/sbin HOME=$H TMPDIR=$DEV/tmp/ SIMULATOR_USE_NO_UPDATE=1 SIMULATOR_USE_DEBUG=1 SIMULATOR_USE_CACHE_DIR=$DEV/su-cache "$@"; }
sleep 30
for i in 1 2; do
  out=$(run sh -c "cd $DEV/work/simtap && node bin/simulator-use.js test examples/swiftui-demo --device $FIXED" 2>&1); echo "  simulator-use test, run $i: exit $?"; echo "$out" | grep -E "reading|passed|couldn" | head -4 | sed 's/^/    /'
done
b=$(ls -d $DEV/su-cache/DerivedData/Demo-*/Results/*.xcresult 2>/dev/null | tail -1); echo "  bundle: $b"
for w in summary tests; do out=$(run xcrun xcresulttool get test-results $w --path "$b" 2>&1); echo "  xcresulttool $w now: exit $? $(echo "$out" | head -c 160)"; done
as nmsim2 xcrun simctl shutdown all >/dev/null 2>&1; launchctl bootout user/508 2>/dev/null; for i in 1 2 3; do pkill -9 -u 508; sleep 0.5; done
diskutil unmount $DEV >/dev/null; d=$(diskutil list | awk '/ nmu-nmsim2 / {print $NF}'); diskutil apfs deleteVolume $d >/dev/null; wipe_home nmsim2 >/dev/null; echo done
