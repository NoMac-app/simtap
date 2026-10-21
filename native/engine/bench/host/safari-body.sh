# Does Safari start in a pool phone? (a) the pool user, golden copy; (b) the pool user, a brand-new phone;
# (c) the Mac's own user, a clone of the golden. And: can a pasteboard server run for a pool user?
for u in 507; do launchctl bootout user/$u 2>/dev/null; pkill -9 -u $u; done; sleep 0.5
wipe_home nmsim1 >/dev/null
crashes() { ls /Library/Logs/DiagnosticReports | grep -c MobileSafari; }
safari() { # label user udid [set]
  local label=$1 u=$2 d=$3 before=$(crashes)
  if [ "$u" = rentamac ]; then sudo -u rentamac xcrun simctl openurl "$d" https://example.com; else as "$u" xcrun simctl openurl "$d" https://example.com; fi
  sleep 8
  local fg; if [ "$u" = rentamac ]; then fg=$(sudo -u rentamac xcrun simctl spawn "$d" launchctl list 2>/dev/null | grep -c MobileSafari); else fg=$(as "$u" xcrun simctl spawn "$d" launchctl list 2>/dev/null | grep -c MobileSafari); fi
  echo "  $label: Safari crash reports +$(( $(crashes) - before )), Safari jobs running: $fg"
}
start nmsim1 sf; UA=$UDID; sleep 30
safari "(a) pool user, golden copy" nmsim1 "$UA"
D=/Users/nmsim1/Library/Developer/CoreSimulator/Devices
UB=$(as nmsim1 xcrun simctl create fresh "iPhone 17 Pro" 2>&1 | tail -1); as nmsim1 xcrun simctl boot "$UB"; as nmsim1 perl -e 'alarm 120; exec @ARGV' xcrun simctl bootstatus "$UB" -b >/dev/null; sleep 30
safari "(b) pool user, brand-new phone" nmsim1 "$UB"
UC=$(sudo -u rentamac xcrun simctl clone CDF6EA77-E9C4-4AC3-8B3E-0F3221B48846 safari-check 2>&1 | tail -1); sudo -u rentamac xcrun simctl boot "$UC"; sudo -u rentamac xcrun simctl bootstatus "$UC" -b >/dev/null; sleep 30
safari "(c) the Mac's own user, a clone of the golden" rentamac "$UC"
sudo -u rentamac xcrun simctl shutdown "$UC"; sudo -u rentamac xcrun simctl delete "$UC"
echo "== a pasteboard server for the pool user"
as nmsim1 sh -c 'exec /usr/libexec/pboard' >/dev/null 2>&1 & PB=$!; sleep 1
echo "  pboard running: $(pgrep -u 507 -x pboard | wc -l | tr -d ' ')"
out=$(as nmsim1 sh -c "echo from-the-agent | xcrun simctl pbcopy $UA" 2>&1); echo "  simctl pbcopy: exit $? $(echo $out | cut -c1-80)"
out=$(as nmsim1 xcrun simctl pbpaste "$UA" 2>&1); echo "  simctl pbpaste: '$out'"
finish nmsim1 sf
