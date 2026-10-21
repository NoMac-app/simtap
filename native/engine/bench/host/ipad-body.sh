for u in 507; do launchctl bootout user/$u 2>/dev/null; pkill -9 -u $u; done; sleep 0.5
wipe_home nmsim1 >/dev/null
start nmsim1 ip; sleep 2
t=$(now); IU=$(as nmsim1 xcrun simctl create ipad "iPad Pro 13-inch (M5)" 2>/dev/null | tail -1); as nmsim1 xcrun simctl boot "$IU"; as nmsim1 perl -e 'alarm 200; exec @ARGV' xcrun simctl bootstatus "$IU" -b >/dev/null; echo "  a new iPad Pro 13-inch created and booted: $(el $t) s"
as nmsim1 xcrun simctl shutdown "$UDID" >/dev/null 2>&1; sleep 40
python3 /tmp/ipad.py "$IU"
finish nmsim1 ip
