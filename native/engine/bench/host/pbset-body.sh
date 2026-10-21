for u in 507; do launchctl bootout user/$u 2>/dev/null; pkill -9 -u $u; done; sleep 0.5
wipe_home nmsim1 >/dev/null
T=/usr/local/nomac-test/pbset; mkdir -p $T; :
xcrun -sdk iphonesimulator clang -arch arm64 -mios-simulator-version-min=17.0 -fobjc-arc -framework UIKit /tmp/pbset-main.m -o $T/pbset && codesign -s - $T/pbset && chmod 755 $T $T/pbset && echo "  helper built for the Simulator"
start nmsim1 ps3; U=$UDID; sleep 25
python3 /tmp/paste.py "$U" "Héllo 日本 🙂"
finish nmsim1 ps3
