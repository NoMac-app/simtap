# A permanent volume per pool user at ~/Library/Developer: root-owned and sticky (1777), holding the user's golden
# in a root-owned .golden; each session's phone is an APFS clone of it at the path it was made for; the end wipes
# everything but .golden. Instant phones and no 2 GB copy per session, if the tenant cannot touch .golden.
for u in 508; do launchctl bootout user/$u 2>/dev/null; pkill -9 -u $u; done; sleep 0.5
wipe_home nmsim2 >/dev/null
FIXED=5E55E550-0000-4000-8000-00000000A002; H=/Users/nmsim2; DEV=$H/Library/Developer; GU=/Library/NoMacSim/golden-user/nmsim2/$FIXED
used() { diskutil info nmu-nmsim2 | awk -F': *' '/Volume Used Space/ {print $2}' | cut -d'(' -f1; }
diskutil apfs addVolume "$container" APFS nmu-nmsim2 -quota 30g -nomount >/dev/null; mkdir -p $DEV; diskutil mount -mountPoint $DEV nmu-nmsim2 >/dev/null; mdutil -i off $DEV >/dev/null 2>&1
chown root:wheel $DEV; chmod 1777 $DEV
t=$(now); mkdir -p $DEV/.golden; cp -R $GU $DEV/.golden/; chown -R root:wheel $DEV/.golden; chmod -R go-w $DEV/.golden; chmod 755 $DEV/.golden
echo "  the user's golden placed once: $(el $t) s; volume used: $(used)"
echo "== the tenant against .golden"
echo "  rename it: $(as nmsim2 mv $DEV/.golden $DEV/x >/dev/null 2>&1 && echo DONE || echo refused)"
echo "  delete it: $(as nmsim2 rm -rf $DEV/.golden >/dev/null 2>&1; [ -d $DEV/.golden/$FIXED ] && echo refused || echo DONE)"
echo "  write into it: $(as nmsim2 sh -c "echo x > $DEV/.golden/$FIXED/x" >/dev/null 2>&1 && echo DONE || echo refused)"
echo "  make its own folders here: $(as nmsim2 mkdir -p $DEV/Xcode/DerivedData $DEV/XCTestDevices >/dev/null 2>&1 && echo yes || echo NO)"
for n in 1 2; do
  echo "== session $n"
  t=$(now); mkdir -p $DEV/CoreSimulator/Devices; chown nmsim2:staff $DEV/CoreSimulator $DEV/CoreSimulator/Devices
  cp -c -R $DEV/.golden/$FIXED $DEV/CoreSimulator/Devices/ && chown -R nmsim2:staff $DEV/CoreSimulator/Devices/$FIXED; echo "  the phone cloned: $(el $t) s; volume used: $(used)"
  t=$(now); as nmsim2 xcrun simctl boot $FIXED; as nmsim2 perl -e 'alarm 120; exec @ARGV' xcrun simctl bootstatus $FIXED -b >/dev/null; echo "  booted: $(el $t) s"; sleep 30
  before=$(ls /Library/Logs/DiagnosticReports | grep -c MobileSafari); as nmsim2 xcrun simctl openurl $FIXED https://example.com; sleep 6
  echo "  Safari crash reports: +$(( $(ls /Library/Logs/DiagnosticReports | grep -c MobileSafari) - before )); volume used after a boot and Safari: $(used)"
  r=$(printf '%s\n' '{"op":"describe"}' '{"op":"describe"}' | as nmsim2 perl -e 'alarm 60; exec @ARGV' /usr/local/nomac-test/engine/simulator-use-engine --udid $FIXED | python3 /tmp/read.py | tail -1); echo "  read: $(echo "$r" | cut -c1-100)"
  t=$(now); as nmsim2 xcrun simctl shutdown all >/dev/null 2>&1; launchctl bootout user/508 2>/dev/null; for i in 1 2 3 4; do pkill -9 -u 508; sleep 0.5; done
  find $DEV -mindepth 1 -maxdepth 1 ! -name .golden -exec rm -rf {} + 2>/dev/null; echo "  wiped all but .golden: $(el $t) s; left: $(ls -A $DEV | tr '\n' ' '); volume used: $(used)"
done
diskutil unmount $DEV >/dev/null; d=$(diskutil list | awk '/ nmu-nmsim2 / {print $NF}'); diskutil apfs deleteVolume $d >/dev/null; wipe_home nmsim2 >/dev/null; echo done
