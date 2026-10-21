# Each wedge case on its own fresh phone (a clone of nmsim2's golden), the volume deleted after.
FIXED=5E55E550-0000-4000-8000-00000000A002; H=/Users/nmsim2; DEV=$H/Library/Developer; GU=/Library/NoMacSim/golden-user/nmsim2/$FIXED
pkill -f suites.sh; pkill -f "scripts/lab.sh"; pkill -f "scripts/golden.sh"
for case in ${CASES:-gap0 axe-beside}; do
  for u in 508; do launchctl bootout user/$u 2>/dev/null; for i in 1 2 3; do pkill -9 -u $u; sleep 0.5; done; done
  diskutil unmount force $DEV >/dev/null 2>&1; d=$(diskutil list | awk '/ nmu-nmsim2 / {print $NF}'); [ -n "$d" ] && diskutil apfs deleteVolume $d >/dev/null
  wipe_home nmsim2 >/dev/null
  diskutil apfs addVolume "$container" APFS nmu-nmsim2 -quota 30g -nomount >/dev/null; mkdir -p $DEV; diskutil mount -mountPoint $DEV nmu-nmsim2 >/dev/null; mdutil -i off $DEV >/dev/null 2>&1; chown root:wheel $DEV; chmod 1777 $DEV
  mkdir -p $DEV/.golden $DEV/CoreSimulator/Devices; cp -R $GU $DEV/.golden/; chown nmsim2:staff $DEV/CoreSimulator $DEV/CoreSimulator/Devices; cp -c -R $DEV/.golden/$FIXED $DEV/CoreSimulator/Devices/; chown -R nmsim2:staff $DEV/CoreSimulator/Devices/$FIXED
  as nmsim2 xcrun simctl boot $FIXED; as nmsim2 perl -e 'alarm 120; exec @ARGV' xcrun simctl bootstatus $FIXED -b >/dev/null
  echo "== case $case (phone booted, a minute's wait)"
  python3 /tmp/wedge.py $FIXED $case
done
as nmsim2 xcrun simctl shutdown all >/dev/null 2>&1; launchctl bootout user/508 2>/dev/null; for i in 1 2 3; do pkill -9 -u 508; sleep 0.5; done
diskutil unmount $DEV >/dev/null; d=$(diskutil list | awk '/ nmu-nmsim2 / {print $NF}'); diskutil apfs deleteVolume $d >/dev/null; wipe_home nmsim2 >/dev/null; echo done
