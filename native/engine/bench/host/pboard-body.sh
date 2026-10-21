# The clipboard for a pool user: macOS's pasteboard agent loaded into the user's own launchd domain.
for u in 507; do launchctl bootout user/$u 2>/dev/null; pkill -9 -u $u; done; sleep 0.5
wipe_home nmsim1 >/dev/null
start nmsim1 pb; U=$UDID; sleep 20
out=$(launchctl bootstrap user/507 /System/Library/LaunchAgents/com.apple.pboard.plist 2>&1); echo "  bootstrap into user/507: exit $? $out"
launchctl print user/507/com.apple.pboard 2>&1 | grep -E "state =|pid =" | head -2 | sed 's/^/  /'
out=$(as nmsim1 sh -c "printf 'Héllo 日本 🙂' | xcrun simctl pbcopy $U" 2>&1); echo "  simctl pbcopy: exit $? $(echo $out | cut -c1-60)"
out=$(as nmsim1 xcrun simctl pbpaste "$U" 2>&1); echo "  simctl pbpaste: '$out'"
echo "  pboard processes of the user: $(pgrep -u 507 -x pboard | wc -l | tr -d ' ')"
finish nmsim1 pb
