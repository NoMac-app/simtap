# The small things an agent needs from its phone, each as the pool user nmsim1 on a pool phone (simctl, no screen session).
for u in 507; do launchctl bootout user/$u 2>/dev/null; pkill -9 -u $u; done; sleep 0.5
wipe_home nmsim1 >/dev/null
start nmsim1 sm; U=$UDID; echo "  phone settling 30 s"; sleep 30
P=/usr/local/nomac-test/prewarm; E=/usr/local/nomac-test/engine/simulator-use-engine
try() { local label=$1; shift; local t=$(now); local out; out=$(as nmsim1 perl -e 'alarm 60; exec @ARGV' "$@" 2>&1); local rc=$?; echo "  $label: exit $rc in $(el $t) s $(echo "$out" | head -1 | cut -c1-90)"; }
try "status bar fixed (9:41, full signal and battery)" xcrun simctl status_bar "$U" override --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100
try "dark mode" xcrun simctl ui "$U" appearance dark
try "appearance now" xcrun simctl ui "$U" appearance
try "a larger text size" xcrun simctl ui "$U" content_size extra-large
try "location set (San Francisco)" xcrun simctl location "$U" set 37.7749,-122.4194
try "the test app installed" xcrun simctl install "$U" $P/Prewarm.app
try "permissions granted before it asks (all)" xcrun simctl privacy "$U" grant all app.nomac.prewarm
printf '{"aps":{"alert":{"title":"NoMac","body":"A push from the agent"}}}' > /tmp/push.json; chmod a+r /tmp/push.json
try "a push notification" xcrun simctl push "$U" app.nomac.prewarm /tmp/push.json
sips -s format jpeg -z 400 400 /System/Library/Desktop\ Pictures/*.heic --out /tmp/photo.jpg >/dev/null 2>&1 || cp /System/Library/CoreServices/Finder.app/Contents/Resources/Finder.icns /tmp/photo.jpg; chmod a+r /tmp/photo.jpg
try "a photo added to the library" xcrun simctl addmedia "$U" /tmp/photo.jpg
try "clipboard into the phone" sh -c "echo from-the-agent | xcrun simctl pbcopy $U"
try "clipboard out of the phone" xcrun simctl pbpaste "$U"
try "language and region (German, Germany)" sh -c "xcrun simctl spawn $U defaults write -g AppleLanguages -array de && xcrun simctl spawn $U defaults write -g AppleLocale -string de_DE"
try "a web page opened in Safari" xcrun simctl openurl "$U" https://example.com
sleep 4
r=$(printf '%s\n' '{"op":"describe"}' '{"op":"describe"}' | as nmsim1 perl -e 'alarm 60; exec @ARGV' $E --udid "$U" | python3 /tmp/read.py | tail -1)
echo "  the screen after (engine): $(echo "$r" | cut -c1-160)"
rm -f /Users/nmsim1/Library/Developer/rec.mp4
as nmsim1 sh -c "xcrun simctl io $U recordVideo --codec h264 --force ~/Library/Developer/rec.mp4 & p=\$!; sleep 4; kill -INT \$p; wait \$p" >/dev/null 2>&1
echo "  a 4 s screen recording: $(ls -la /Users/nmsim1/Library/Developer/rec.mp4 2>/dev/null | awk '{print $5 " bytes"}')"
finish nmsim1 sm
