# simulator-use's own suites (scripts/lab.sh, scripts/golden.sh) as the pool user nmsim2, on its cloned golden phone,
# with the engine in vendor/axe (the CLI starts it per command). Waits until the phone is WAIT_S old first.
for u in 508; do launchctl bootout user/$u 2>/dev/null; pkill -9 -u $u; done; sleep 0.5
wipe_home nmsim2 >/dev/null
FIXED=5E55E550-0000-4000-8000-00000000A002; H=/Users/nmsim2; DEV=$H/Library/Developer; GU=/Library/NoMacSim/golden-user/nmsim2/$FIXED
d=$(diskutil list | awk '/ nmu-nmsim2 / {print $NF}'); [ -n "$d" ] && diskutil apfs deleteVolume $d >/dev/null
diskutil apfs addVolume "$container" APFS nmu-nmsim2 -quota 30g -nomount >/dev/null; mkdir -p $DEV; diskutil mount -mountPoint $DEV nmu-nmsim2 >/dev/null; mdutil -i off $DEV >/dev/null 2>&1; chown root:wheel $DEV; chmod 1777 $DEV
mkdir -p $DEV/.golden $DEV/CoreSimulator/Devices; cp -R $GU $DEV/.golden/; chown nmsim2:staff $DEV/CoreSimulator $DEV/CoreSimulator/Devices; cp -c -R $DEV/.golden/$FIXED $DEV/CoreSimulator/Devices/; chown -R nmsim2:staff $DEV/CoreSimulator/Devices/$FIXED
mkdir -p $DEV/work; cp -R /tmp/simtap-repo $DEV/work/simtap; chown -R nmsim2:staff $DEV/work
as nmsim2 xcrun simctl boot $FIXED; as nmsim2 perl -e 'alarm 120; exec @ARGV' xcrun simctl bootstatus $FIXED -b >/dev/null
echo "  phone booted; waiting ${WAIT_S:-30} s"; sleep ${WAIT_S:-30}
run() { as nmsim2 env PATH=/usr/local/nomac-test/node/bin:/usr/local/nomac-test/xcodegen/bin:/usr/bin:/bin:/usr/sbin:/sbin HOME=$H TMPDIR=$DEV/tmp/ SIMULATOR_USE_NO_UPDATE=1 SIMULATOR_USE_CACHE_DIR=$DEV/su-cache "$@"; }
mkdir -p $DEV/tmp; chown nmsim2:staff $DEV/tmp
for suite in ${SUITES:-lab golden}; do
  t=$(now); echo "== scripts/$suite.sh"
  run sh -c "cd $DEV/work/simtap && bash scripts/$suite.sh golden" 2>&1 | sed 's/^/  /'
  echo "  ($suite: $(el $t) s)"
done
echo "== the engine's session log"; cat $DEV/tmp/simulator-use-engine-*.log 2>/dev/null | awk '{print $4, $5, $6, $7, $8, $9}' | sort | uniq -c | sort -nr | head -12
grep -E "refused|timed out" $DEV/tmp/simulator-use-engine-*.log 2>/dev/null | head -5
as nmsim2 xcrun simctl shutdown all >/dev/null 2>&1; launchctl bootout user/508 2>/dev/null; for i in 1 2 3; do pkill -9 -u 508; sleep 0.5; done
diskutil unmount $DEV >/dev/null; d=$(diskutil list | awk '/ nmu-nmsim2 / {print $NF}'); diskutil apfs deleteVolume $d >/dev/null; wipe_home nmsim2 >/dev/null; echo done
